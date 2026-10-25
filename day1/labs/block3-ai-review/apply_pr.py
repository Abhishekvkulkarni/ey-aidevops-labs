#!/usr/bin/env python3
"""Load the seeded pull request onto a local branch (feature/shipment-search).

The patch contains a placeholder instead of the fake token, so GitHub never sees a token-shaped
string in your main branch. The token is filled in only here, on a local branch.
DO NOT PUSH THE feature/shipment-search BRANCH to GitHub: GitHub will block it.

Usage (from the repo root):  python day1/labs/block3-ai-review/apply_pr.py
"""
import subprocess
import sys
from pathlib import Path

def _find_root():
    """The repo root is the folder that holds api/ and helm/ (works wherever this script lives)."""
    for p in Path(__file__).resolve().parents:
        if (p / "api").is_dir() and (p / "helm").is_dir():
            return p
    return Path.cwd()


ROOT = _find_root()
HERE = Path(__file__).resolve().parent
PATCH = HERE / "pr.patch"
BRANCH = "feature/shipment-search"
# Fake value, shaped like a GitHub token so the scanner can find it. It is not a real credential.
# Built from pieces so this file itself never contains a token-shaped string (GitHub push protection).
FAKE_TOKEN = "ghp" + "_" + "0123456789" + "abcdefghijklmnopqrstuvwxyz"

IDENT = ["-c", "user.name=Lab Contributor", "-c", "user.email=contributor@example.com"]


def git(*args, stdin=None, check=True):
    p = subprocess.run(["git", *args], cwd=ROOT, input=stdin, text=True, capture_output=True)
    if check and p.returncode != 0:
        print("git " + " ".join(args) + " failed:\n" + (p.stderr or p.stdout).strip())
        sys.exit(1)
    return p.stdout.strip()


def main():
    if not (ROOT / ".git").exists():
        print("This folder is not a git repository. Run:  git init  then commit your files first.")
        return 1
    current = git("rev-parse", "--abbrev-ref", "HEAD")
    existing = git("branch", "--list", BRANCH)
    if existing:
        git("checkout", BRANCH)
        print(f"Branch {BRANCH} already exists; switched to it. Base branch: {(HERE / '.pr_base').read_text().strip() if (HERE / '.pr_base').exists() else current}")
        return 0
    if git("status", "--porcelain", "--untracked-files=no"):
        print("You have uncommitted changes. Commit them first:\n  git add -A\n  git commit -m \"save work\"")
        return 1

    patch = PATCH.read_text(encoding="utf-8").replace("__TOKEN__", FAKE_TOKEN)
    git("checkout", "-b", BRANCH)
    git("apply", "--index", "--ignore-whitespace", "-", stdin=patch)
    git(*IDENT, "commit", "-q", "-m", "Add shipment search and delete endpoints, debug pod")
    (HERE / ".pr_base").write_text(current + "\n", encoding="utf-8")

    changed = git("diff", "--name-only", current, "HEAD").splitlines()
    print(f"Seeded PR loaded on branch {BRANCH} (base: {current}). Files changed:")
    for f in changed:
        print("  " + f)
    print("\nDo NOT push this branch to GitHub. It contains a fake token on purpose.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
