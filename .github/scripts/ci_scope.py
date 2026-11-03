"""Conservative documentation-only CI scope; errors never emit a skip decision."""
import json
import os
from pathlib import Path
import re
import subprocess


def is_document(path):
    # CHANGELOG.md is a Flutter asset. Only these non-runtime Markdown paths qualify.
    parts = path.split(b"/")
    if any(part in (b"", b".", b"..") for part in parts):
        return False
    return path in (b"README.md", b"README.en.md") or (
        parts[0] in (b"docs", b"doc") and len(parts) > 1 and path.endswith(b".md")
    )


def git(*args):
    return subprocess.check_output(["git", *args], stderr=subprocess.PIPE)


def detect(event_name, event, ref, force_full=False):
    if force_full or event_name not in ("pull_request", "push"):
        return "true"
    if event_name == "pull_request":
        base = event["pull_request"]["base"]["sha"]
        head = event["pull_request"]["head"]["sha"]
        separator = "..."
    else:
        # Tags, release callers, and non-main pushes always retain full validation.
        if ref != "refs/heads/main":
            return "true"
        base, head = event["before"], event["after"]
        separator = ".."
    for sha in (base, head):
        if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", sha) or int(sha, 16) == 0:
            raise ValueError("Invalid or missing comparison commit")
        git("cat-file", "-e", f"{sha}^{{commit}}")
    # Disable rename detection: both old and new names must qualify, even across scopes.
    raw = git("diff", "--no-ext-diff", "--no-renames", "--name-only", "-z", f"{base}{separator}{head}", "--")
    if not raw:
        return "true"
    if not raw.endswith(b"\0"):
        raise ValueError("Unterminated diff output")
    paths = raw[:-1].split(b"\0")
    return "false" if all(is_document(path) for path in paths) else "true"


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    full = detect(os.environ["GITHUB_EVENT_NAME"], event, os.environ["GITHUB_REF"],
                  os.environ.get("FORCE_FULL", "false") == "true")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"full_ci={full}\n")
    print(f"full_ci={full}")


if __name__ == "__main__":
    main()
