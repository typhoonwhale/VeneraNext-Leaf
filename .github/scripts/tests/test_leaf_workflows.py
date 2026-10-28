import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
WORKFLOWS = ROOT / ".github/workflows"


def step_script(filename, name):
    text = (WORKFLOWS / filename).read_text()
    match = re.search(
        rf"^      - name: {re.escape(name)}\n(?:        [^\n]*\n)*?"
        r"        run: \|\n(?P<body>(?:          [^\n]*\n|\n)+)",
        text,
        re.MULTILINE,
    )
    if match is None:
        raise AssertionError(f"Missing workflow step: {name}")
    return "\n".join(line[10:] for line in match['body'].splitlines())


class LeafWorkflowTests(unittest.TestCase):
    def test_artifact_gate_rejects_missing_wrong_and_extra_apks(self):
        script = step_script('build.yml', '校验单一 ARM64 产物并生成摘要')
        arm64 = 'VeneraNext-Leaf-1.18.2-android-arm64-v8a.apk'
        cases = [([], False), ([arm64], True),
                 (['VeneraNext-Leaf-1.18.2-android.apk'], False),
                 ([arm64, 'another-arm64-v8a.apk'], False),
                 ([arm64, 'android-x86_64.apk'], False)]
        for names, success in cases:
            with self.subTest(names=names), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / 'build/app/outputs/apk/release'
                output.mkdir(parents=True)
                for name in names:
                    (output / name).write_bytes(b'fixture')
                result = subprocess.run(['bash', '-e', '-c', script], cwd=directory,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, success, result.stderr)
                if success:
                    self.assertIn(arm64, (output / 'SHA256SUMS.txt').read_text())

    def test_signature_gate_accepts_only_fixed_certificate(self):
        script = step_script('build.yml', '校验 APK 签名证书')
        expected = 'ddf1ca6f03578cd9b41470670cd3a21637772ea9e3ceab4f6d9ea9c0e8d5e909'
        fake = (
            '#!/bin/bash\n'
            'if [[ "${FAKE_VERIFY_FAIL:-}" == 1 ]]; then echo "DOES NOT VERIFY" >&2; exit 1; fi\n'
            'echo "Verifies"\n'
            'if [[ -n "${FAKE_SCHEME_FORMAT:-}" ]]; then\n'
            '  echo "V2 Signer: certificate DN: CN=Leaf"\n'
            '  echo "V2 Signer: certificate SHA-256 digest: $FAKE_DIGEST_1"\n'
            '  [[ -n "${FAKE_V3_DIGEST:-}" ]] && '
            'echo "V3 Signer: certificate SHA-256 digest: $FAKE_V3_DIGEST"\n'
            '  [[ -n "${FAKE_DIGEST_2:-}" ]] && '
            'echo "V2 Signer #2: certificate SHA-256 digest: $FAKE_DIGEST_2"\n'
            '  exit 0\n'
            'fi\n'
            'echo "Signer #1 certificate DN: CN=Leaf"\n'
            'echo "Signer #1 certificate SHA-256 digest: $FAKE_DIGEST_1"\n'
            '[[ -n "${FAKE_DIGEST_2:-}" ]] && '
            'echo "Signer #2 certificate SHA-256 digest: $FAKE_DIGEST_2"\n'
            'exit 0\n'
        )
        cases = [
            ('match', {}, True), ('uppercase', {'FAKE_DIGEST_1': expected.upper()}, True),
            ('mismatch', {'FAKE_DIGEST_1': '0' * 64}, False),
            ('two signers', {'FAKE_DIGEST_2': expected}, False),
            ('scheme format', {'FAKE_SCHEME_FORMAT': '1'}, True),
            ('scheme format v2 and v3', {'FAKE_SCHEME_FORMAT': '1', 'FAKE_V3_DIGEST': expected}, True),
            ('scheme format mismatch', {'FAKE_SCHEME_FORMAT': '1', 'FAKE_DIGEST_1': '0' * 64}, False),
            ('scheme format conflicting schemes',
             {'FAKE_SCHEME_FORMAT': '1', 'FAKE_V3_DIGEST': '0' * 64}, False),
            ('scheme format two signers',
             {'FAKE_SCHEME_FORMAT': '1', 'FAKE_DIGEST_2': expected}, False),
            ('verify fails', {'FAKE_VERIFY_FAIL': '1'}, False),
            ('no apksigner', {'NO_APKSIGNER': '1'}, False),
        ]
        for label, extra, success in cases:
            with self.subTest(label), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                if 'NO_APKSIGNER' not in extra:
                    tool = root / 'sdk/build-tools/34.0.0/apksigner'
                    tool.parent.mkdir(parents=True)
                    tool.write_text(fake)
                    tool.chmod(0o755)
                else:
                    (root / 'sdk/build-tools').mkdir(parents=True)
                output = root / 'build/app/outputs/apk/release'
                output.mkdir(parents=True)
                (output / 'VeneraNext-Leaf-1.18.2-android-arm64-v8a.apk').write_bytes(b'fixture')
                env = {**os.environ, 'ANDROID_HOME': str(root / 'sdk'),
                       'EXPECTED_CERT_SHA256': expected, 'FAKE_DIGEST_1': expected, **extra}
                result = subprocess.run(['bash', '-e', '-c', script], cwd=directory,
                                        capture_output=True, text=True, env=env)
                self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
                if not success:
                    self.assertIn('::error::', result.stdout + result.stderr)

    def test_pr_gate_allows_skips_but_rejects_build_failures(self):
        script = step_script('pr_build.yml', '汇总平台构建结果')
        for changes, android, success in [
            ('success', 'success', True), ('success', 'skipped', True),
            ('failure', 'skipped', False), ('success', 'failure', False),
            ('success', 'cancelled', False),
        ]:
            with self.subTest(changes=changes, android=android):
                result = subprocess.run(
                    ['bash', '-e', '-c', script], capture_output=True, text=True,
                    env={**os.environ, 'CHANGES_RESULT': changes, 'ANDROID_RESULT': android},
                )
                self.assertEqual(result.returncode == 0, success, result.stderr)

    def test_formal_release_tag_must_be_on_main(self):
        script = step_script('main.yml', '校验正式版标签位于 main')

        def git(cwd, *args):
            subprocess.run(['git', *args], cwd=cwd, check=True, capture_output=True,
                           env={**os.environ, 'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@t',
                                'GIT_COMMITTER_NAME': 't', 'GIT_COMMITTER_EMAIL': 't@t'})

        cases = [('v1.18.5', 'main', True), ('v1.18.5', 'feature', False),
                 ('v1.18.5-rc.1', 'main', True), ('v1.18.5-rc.1', 'feature', True)]
        for tag, branch, success in cases:
            with self.subTest(tag=tag, branch=branch), tempfile.TemporaryDirectory() as directory:
                origin = Path(directory) / 'origin.git'
                work = Path(directory) / 'work'
                git(directory, 'init', '--bare', '-b', 'main', str(origin))
                git(directory, 'clone', str(origin), str(work))
                git(work, 'checkout', '-b', 'main')
                git(work, 'commit', '--allow-empty', '-m', 'base')
                git(work, 'push', 'origin', 'main')
                if branch == 'feature':
                    git(work, 'checkout', '-b', 'feature')
                    git(work, 'commit', '--allow-empty', '-m', 'feature only')
                git(work, 'tag', tag)
                result = subprocess.run(
                    ['bash', '-e', '-c', script], cwd=work, capture_output=True, text=True,
                    env={**os.environ, 'GITHUB_REF_NAME': tag})
                self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
                if not success:
                    self.assertIn('::error::', result.stdout)

    def run_cleanup(self, tag, fail_delete=False):
        script = step_script('main.yml', '清理同版本预发布')
        fake = (
            '#!/bin/bash\n'
            'echo "$*" >> "$GH_LOG"\n'
            'case "$1 $2" in\n'
            '  "release list") printf "%s\\n" v1.18.5-rc.1 v1.18.5 v1.18.50-rc.1 v1.18.4-rc.1;;\n'
            '  "api --paginate") printf "%s\\n" refs/tags/v1.18.5-rc.1 refs/tags/v1.18.5-rc.2 '
            'refs/tags/v1.18.5-beta;;\n'
            '  *) [[ -n "${FAKE_FAIL_DELETE:-}" ]] && exit 1;;\n'
            'esac\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'bin').mkdir()
            gh = root / 'bin/gh'
            gh.write_text(fake)
            gh.chmod(0o755)
            env = {**os.environ, 'PATH': f"{root / 'bin'}:{os.environ['PATH']}",
                   'GH_LOG': str(root / 'log'), 'GITHUB_REF_NAME': tag,
                   'GITHUB_REPOSITORY': 'o/r'}
            if fail_delete:
                env['FAKE_FAIL_DELETE'] = '1'
            (root / 'log').touch()
            result = subprocess.run(['bash', '-c', script], cwd=directory,
                                    capture_output=True, text=True, env=env)
            deletes = [line for line in (root / 'log').read_text().splitlines()
                       if line.startswith(('release delete', 'api -X DELETE'))]
            return result, deletes

    def test_cleanup_removes_only_same_version_prereleases(self):
        result, deletes = self.run_cleanup('v1.18.5')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(sorted(deletes), sorted([
            'release delete v1.18.5-rc.1 --cleanup-tag --yes',
            'api -X DELETE repos/o/r/git/refs/tags/v1.18.5-rc.2',
            'api -X DELETE repos/o/r/git/refs/tags/v1.18.5-beta',
        ]))

    def test_cleanup_skips_prerelease_runs(self):
        result, deletes = self.run_cleanup('v1.18.5-rc.3')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(deletes, [])

    def test_cleanup_failure_only_warns(self):
        result, deletes = self.run_cleanup('v1.18.5', fail_delete=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(deletes), 3)
        self.assertEqual(result.stdout.count('::warning::'), 3)

    def test_analyze_skips_windows_script_tests_only(self):
        script = step_script('analyze.yml', '运行脚本单元测试')
        with tempfile.TemporaryDirectory() as directory:
            tests = Path(directory) / '.github/scripts/tests'
            tests.mkdir(parents=True)
            for name in ['test_alpha', 'test_windows_build', 'test_windows_installer',
                         'test_windows_headless_output', 'test_beta']:
                (tests / f'{name}.py').write_text(
                    'import unittest\n'
                    f'class T(unittest.TestCase):\n'
                    f'    def test_ran(self):\n'
                    f'        open("ran_{name}", "w").close()\n')
            result = subprocess.run(['bash', '-c', script], cwd=directory,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            ran = sorted(p.name for p in Path(directory).glob('ran_*'))
            self.assertEqual(ran, ['ran_test_alpha', 'ran_test_beta'])


if __name__ == '__main__':
    unittest.main()
