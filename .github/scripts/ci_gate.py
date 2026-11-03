"""Require successful work, or explicit documentation-only skips, for every CI gate."""
import json
import os
import sys


def validate(needs, jobs, event_name):
    scope = needs["changes"]
    full = scope.get("outputs", {}).get("full_ci")
    if scope.get("result") != "success" or full not in ("true", "false"):
        raise ValueError("Scope detection failed or returned an invalid decision")
    for job in jobs:
        required = full == "true" and (job != "dependency_review" or event_name == "pull_request")
        expected = "success" if required else "skipped"
        actual = needs[job]["result"]
        if actual != expected:
            raise ValueError(f"{job}: expected {expected}, got {actual}")


def main():
    validate(json.loads(os.environ["CI_NEEDS"]), sys.argv[1:], os.environ["GITHUB_EVENT_NAME"])
    print("CI gate passed")


if __name__ == "__main__":
    main()
