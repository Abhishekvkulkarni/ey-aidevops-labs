#!/usr/bin/env python3
"""Mutation check: inject 6 known bugs into a COPY of api/, run your tests against each,
and count how many bugs your tests catch. Your real code is never changed.

Usage (from the repo root):  python lab3/mutation_check.py
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
API = ROOT / "api"

# (file, original text, mutated text, plain-English description)
MUTANTS = [
    ("app/pagination.py", "start = (page - 1) * size", "start = page * size", "page 1 skips the first page"),
    ("app/pagination.py", "if page < 1", "if page < 0", "page 0 is accepted"),
    ("app/pagination.py", "items[start:start + size]", "items[start:start + size + 1]", "one item too many per page"),
    ("app/auth.py", "x_api_key != expected", "x_api_key == expected", "the key check is inverted"),
    ("app/auth.py", "status_code=401", "status_code=403", "wrong status code for a bad key"),
    ("app/main.py", '{"status": "ok"}', '{"status": "down"}', "health endpoint reports down"),
]


def run_tests(workdir):
    env = dict(os.environ)
    env.setdefault("API_KEY", "test-key")
    p = subprocess.run(
        [sys.executable, "-m", "pytest", "-x", "-q", "-p", "no:cacheprovider", "tests"],
        cwd=workdir, env=env, capture_output=True, text=True, timeout=180,
    )
    return p.returncode, p.stdout + p.stderr


def main():
    tests = list((API / "tests").glob("test_*.py"))
    if not tests:
        print("No tests found in api/tests. Copy the ready-made file first:")
        print("  Copy-Item lab3\\ready_made_tests\\test_api.py api\\tests\\")
        print("Mutants killed: 0/6")
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp) / "api"
        shutil.copytree(API, work, ignore=shutil.ignore_patterns("__pycache__", ".pytest_cache", ".coverage"))

        code, out = run_tests(work)
        if code != 0:
            print("Your tests fail on the ORIGINAL code, so the check cannot start.")
            print("\n".join(out.strip().splitlines()[-15:]))
            print("Mutants killed: 0/6")
            return 1
        print("Baseline: your tests pass on the original code.\n")

        killed = 0
        for i, (rel, old, new, what) in enumerate(MUTANTS, 1):
            target = work / rel
            src = target.read_text(encoding="utf-8")
            if old not in src:
                print(f"Mutant {i}: SKIPPED ({rel} was changed, so this bug cannot be injected)")
                continue
            target.write_text(src.replace(old, new, 1), encoding="utf-8")
            try:
                code, _ = run_tests(work)
            finally:
                target.write_text(src, encoding="utf-8")
            if code != 0:
                killed += 1
                print(f"Mutant {i}: KILLED   {what}")
            else:
                print(f"Mutant {i}: SURVIVED {what}   <- your tests did not notice")

    print(f"\nMutants killed: {killed}/6")
    return 0


if __name__ == "__main__":
    sys.exit(main())
