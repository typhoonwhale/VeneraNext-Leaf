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


if __name__ == '__main__':
    unittest.main()
