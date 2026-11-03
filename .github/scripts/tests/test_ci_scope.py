import importlib.util
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
ROOT = SCRIPTS.parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


scope = load('ci_scope')
gate = load('ci_gate')


class ScopeTests(unittest.TestCase):
    def test_allowlist_excludes_runtime_and_unknown_files(self):
        for path in [b'README.md', b'README.en.md', b'docs/todo.md', b'doc/a/b.md', b'docs/line\nbreak.md']:
            self.assertTrue(scope.is_document(path), path)
        for path in [b'', b'CHANGELOG.md', b'pubspec.yaml', b'lib/README.md', b'docs/run.py',
                     b'.github/workflows/analyze.yml', b'docs/image.png', b'docs/../lib/a.md', b'docs//a.md']:
            self.assertFalse(scope.is_document(path), path)

    def test_non_diff_events_and_reusable_release_always_full(self):
        for event, ref, forced in [('workflow_dispatch', 'refs/heads/main', False),
                                   ('schedule', 'refs/heads/main', False),
                                   ('workflow_call', 'refs/heads/main', False),
                                   ('push', 'refs/tags/v1.2.3', False),
                                   ('push', 'refs/heads/main', True),
                                   ('pull_request', 'refs/pull/1/merge', True)]:
            with patch.object(scope, 'git', side_effect=AssertionError('must not query diff')):
                self.assertEqual(scope.detect(event, {}, ref, forced), 'true')

    def test_invalid_missing_commit_and_diff_failures_do_not_allow_skip(self):
        for sha in ['', '0' * 40, '-bad', None]:
            with self.assertRaises((ValueError, KeyError)):
                scope.detect('push', {'before': sha, 'after': 'a' * 40}, 'refs/heads/main')
        event = {'before': 'a' * 40, 'after': 'b' * 40}
        for effects in [[subprocess.CalledProcessError(1, 'git')],
                        [b'', b'', subprocess.CalledProcessError(1, 'diff')],
                        [b'', b'', b'docs/a.md']]:
            with patch.object(scope, 'git', side_effect=effects), self.assertRaises((ValueError, subprocess.CalledProcessError)):
                scope.detect('push', event, 'refs/heads/main')
        with patch.object(scope, 'git', side_effect=[b'', b'', b'']):
            self.assertEqual(scope.detect('push', event, 'refs/heads/main'), 'true')

    def test_real_git_multicommit_rename_delete_and_pr_merge_base(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = {**os.environ, 'GIT_AUTHOR_NAME': 'CI Test', 'GIT_COMMITTER_NAME': 'CI Test',
                   'GIT_AUTHOR_EMAIL': 'ci@example.test', 'GIT_COMMITTER_EMAIL': 'ci@example.test'}
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root, env=env, stderr=subprocess.PIPE)
            def commit(path, content):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(content)
                git('add', '--all'); git('commit', '-m', 'fixture')
                return git('rev-parse', 'HEAD').decode().strip()
            def detect(base, head, pr=False):
                event = {'pull_request': {'base': {'sha': base}, 'head': {'sha': head}}} if pr else {'before': base, 'after': head}
                with patch.object(scope, 'git', side_effect=git):
                    return scope.detect('pull_request' if pr else 'push', event, 'refs/heads/main')
            git('init', '-b', 'main')
            base = commit('lib/code.dart', 'code')
            first = commit('docs/line\nbreak.md', 'doc')
            second = commit('README.md', 'readme')
            self.assertEqual(detect(base, second), 'false')
            git('mv', 'docs/line\nbreak.md', 'docs/renamed.md')
            git('commit', '-m', 'rename')
            renamed = git('rev-parse', 'HEAD').decode().strip()
            self.assertEqual(detect(second, renamed), 'false')
            git('rm', 'docs/renamed.md'); git('commit', '-m', 'delete')
            deleted = git('rev-parse', 'HEAD').decode().strip()
            self.assertEqual(detect(renamed, deleted), 'false')
            (root / 'docs').mkdir(exist_ok=True)
            git('mv', 'lib/code.dart', 'docs/code.md'); git('commit', '-m', 'rename code')
            moved = git('rev-parse', 'HEAD').decode().strip()
            self.assertEqual(detect(deleted, moved), 'true')
            self.assertEqual(detect(base, moved), 'true')
            git('checkout', '-b', 'docs', second)
            doc_head = commit('doc/user.md', 'new doc')
            git('checkout', 'main')
            main_head = commit('lib/new.dart', 'new code on base only')
            self.assertEqual(detect(main_head, doc_head, pr=True), 'false')
            self.assertEqual(detect(main_head, doc_head), 'true')
            self.assertEqual(detect(first, first), 'true')

    def test_cli_failure_leaves_output_unset(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'event').write_text('{"before": "bad", "after": "bad"}')
            result = subprocess.run(['python3', str(SCRIPTS / 'ci_scope.py')], capture_output=True,
                                    env={**os.environ, 'GITHUB_EVENT_PATH': str(root / 'event'),
                                         'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF': 'refs/heads/main',
                                         'GITHUB_OUTPUT': str(root / 'output')})
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / 'output').exists())


class GateTests(unittest.TestCase):
    def needs(self, full, result='success', scope_result='success'):
        return {'changes': {'result': scope_result, 'outputs': {'full_ci': full}},
                'job': {'result': result}}

    def test_required_work_must_succeed(self):
        gate.validate(self.needs('true'), ['job'], 'pull_request')
        for result in ['skipped', 'cancelled', 'failure', '']:
            with self.subTest(result=result), self.assertRaises(ValueError):
                gate.validate(self.needs('true', result), ['job'], 'pull_request')

    def test_docs_require_explicit_skip_and_trusted_scope(self):
        gate.validate(self.needs('false', 'skipped'), ['job'], 'pull_request')
        for full in ['', None, 'False', 'unknown']:
            with self.assertRaises(ValueError):
                gate.validate(self.needs(full, 'skipped'), ['job'], 'pull_request')
        for result in ['failure', 'cancelled', 'skipped']:
            with self.assertRaises(ValueError):
                gate.validate(self.needs('false', 'skipped', result), ['job'], 'pull_request')
        for result in ['failure', 'cancelled', 'success']:
            with self.assertRaises(ValueError):
                gate.validate(self.needs('false', result), ['job'], 'pull_request')

    def test_dependency_review_is_only_required_on_pr(self):
        for event in ['pull_request', 'push', 'workflow_dispatch', 'schedule']:
            for full in ['true', 'false']:
                needs = self.needs(full)
                needs['dependency_review'] = {'result': 'success' if full == 'true' and event == 'pull_request' else 'skipped'}
                gate.validate(needs, ['dependency_review'], event)
        needs = self.needs('true'); needs['dependency_review'] = {'result': 'skipped'}
        with self.assertRaises(ValueError):
            gate.validate(needs, ['dependency_review'], 'pull_request')

    def test_workflow_wiring_keeps_all_gates_and_release_checks(self):
        configurations = [('analyze.yml', 'quality_gate', ['analyze', 'rhttp-native', 'flutter-tests']),
                          ('dependency_review.yml', 'dependency_gate', ['dependency_review', 'rust_audit']),
                          ('pr_build.yml', 'platform_gate', ['android'])]
        for filename, gate_id, jobs in configurations:
            text = (ROOT / '.github/workflows' / filename).read_text()
            self.assertNotIn('paths-ignore:', text)
            self.assertNotIn('\n    paths:', text)
            self.assertIn('fetch-depth: 0', text)
            self.assertIn('run: python3 .github/scripts/ci_scope.py', text)
            gate_text = text.split(f'  {gate_id}:\n')[1]
            self.assertIn('if: ${{ always() }}', gate_text)
            self.assertIn(f"needs: [changes, {', '.join(jobs)}]", gate_text)
            self.assertIn(f"run: python3 .github/scripts/ci_gate.py {' '.join(jobs)}", gate_text)
            for job in jobs:
                job_text = re.split(r'\n  [a-z_][^\n]*:\n', text.split(f'  {job}:\n')[1], maxsplit=1)[0]
                self.assertIn("needs.changes.outputs.full_ci == 'true'", job_text)
        analyze = (ROOT / '.github/workflows/analyze.yml').read_text()
        self.assertIn('default: true', analyze)
        self.assertIn('FORCE_FULL: ${{ inputs.full_ci || false }}', analyze)
        self.assertIn('needs: [changes, rhttp-native]', analyze)
        self.assertIn('uses: ./.github/workflows/analyze.yml', (ROOT / '.github/workflows/main.yml').read_text())


if __name__ == '__main__':
    unittest.main()
