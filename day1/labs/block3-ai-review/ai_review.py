#!/usr/bin/env python3
"""AI reviewer for the seeded PR. Reads the PR diff, asks a model to review it, saves day1/labs/block3-ai-review/ai_findings.json.

Usage (from the repo root):
  python day1/labs/block3-ai-review/ai_review.py               review with context (diff + full source files)
  python day1/labs/block3-ai-review/ai_review.py --no-context  review the diff only

Needs the environment from  . C:\\EYLAB\\ey-aidevops-labs\\lab-env.ps1  (AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_API_KEY,
AZURE_OPENAI_DEPLOYMENT).  Trainer dry run without a model:  --mock
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

def _find_root():
    """The repo root is the folder that holds api/ and helm/ (works wherever this script lives)."""
    for p in Path(__file__).resolve().parents:
        if (p / "api").is_dir() and (p / "helm").is_dir():
            return p
    return Path.cwd()


ROOT = _find_root()
HERE = Path(__file__).resolve().parent
OUT = HERE / "ai_findings.json"

# ---------------------------------------------------------------------------------------------
# SOLO CHALLENGE: this is the prompt you rewrite as a spec. Keep the rest of the file as it is.
# ---------------------------------------------------------------------------------------------
REVIEW_PROMPT = """You are a code reviewer. Review this pull request and report any problems you find."""
# ---------------------------------------------------------------------------------------------

# Required by the scorer. Do not remove.
OUTPUT_FORMAT = """Reply with ONLY a JSON array, no other text. Each item must look like:
{"file": "path/in/repo.py", "line": 12, "category": "short-category-name", "evidence": "the exact code that is wrong"}
Reply with [] if nothing is wrong."""

MOCK = [
    {"file": "api/app/config.py", "line": 7, "category": "hardcoded-secret", "evidence": "NOTIFY_TOKEN = \"ghp_...\""},
    {"file": "api/app/routes/shipments.py", "line": 13, "category": "injection", "evidence": "f\"SELECT ... WHERE city = '{city}'\""},
    {"file": "api/app/main.py", "line": 8, "category": "logic-bug", "evidence": "router included twice"},
]


def git(*args):
    p = subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True)
    if p.returncode != 0:
        sys.exit("git " + " ".join(args) + " failed: " + (p.stderr or p.stdout).strip())
    return p.stdout


def build_user_message(with_context):
    base_file = HERE / ".pr_base"
    if not base_file.exists():
        sys.exit("Seeded PR not loaded yet. Run:  python day1/labs/block3-ai-review/apply_pr.py")
    base = base_file.read_text().strip()
    diff = git("diff", base, "HEAD")
    parts = ["PULL REQUEST DIFF:\n" + diff]
    if with_context:
        files = sorted(ROOT.glob("api/app/**/*.py")) + sorted(ROOT.glob("deploy/*.yaml"))
        blocks = []
        for f in files:
            if f.stat().st_size == 0:
                continue
            blocks.append(f"--- {f.relative_to(ROOT).as_posix()} ---\n{f.read_text(encoding='utf-8', errors='replace')}")
        parts.append("FULL CURRENT SOURCE FILES (for context):\n" + "\n\n".join(blocks))
    return "\n\n".join(parts)


def call_model(system, user):
    endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT", "").rstrip("/")
    key = os.environ.get("AZURE_OPENAI_API_KEY", "")
    deployment = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "")
    version = os.environ.get("AZURE_OPENAI_API_VERSION", "2024-10-21")
    missing = [n for n, v in (("AZURE_OPENAI_ENDPOINT", endpoint), ("AZURE_OPENAI_API_KEY", key),
                              ("AZURE_OPENAI_DEPLOYMENT", deployment)) if not v]
    if missing:
        sys.exit("Missing environment: " + ", ".join(missing) + "\nRun  . C:\\EYLAB\\ey-aidevops-labs\\lab-env.ps1  in this terminal.")
    url = f"{endpoint}/openai/deployments/{deployment}/chat/completions?api-version={version}"
    body = json.dumps({
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "temperature": 0.2,
    }).encode("utf-8")
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json", "api-key": key})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        sys.exit(f"Model call failed: HTTP {e.code}. {e.read().decode('utf-8', 'replace')[:300]}")
    except urllib.error.URLError as e:
        sys.exit(f"Could not reach the model endpoint: {e.reason}")
    return data["choices"][0]["message"]["content"]


def parse_findings(text):
    text = text.strip()
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text)
    start, end = text.find("["), text.rfind("]")
    if start < 0 or end < start:
        sys.exit("The model did not return a JSON array. Raw reply:\n" + text[:500])
    items = json.loads(text[start:end + 1])
    return [i for i in items if isinstance(i, dict) and i.get("file")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-context", action="store_true", help="send only the diff, not the full files")
    ap.add_argument("--mock", action="store_true", help="trainer dry run: skip the model, use canned findings")
    args = ap.parse_args()

    if args.mock:
        findings = MOCK
        print("[mock mode: canned findings, no model call]")
    else:
        system = REVIEW_PROMPT.strip() + "\n\n" + OUTPUT_FORMAT
        findings = parse_findings(call_model(system, build_user_message(not args.no_context)))

    OUT.write_text(json.dumps(findings, indent=2) + "\n", encoding="utf-8")
    mode = "diff only" if args.no_context else "diff + full files"
    print(f"AI reviewer ({mode}) reported {len(findings)} finding(s):")
    for f in findings:
        print(f"  {f.get('file')}:{f.get('line', '?')}  [{f.get('category', '?')}]  {str(f.get('evidence', ''))[:70]}")
    print("\nSaved to day1/labs/block3-ai-review/ai_findings.json. Now run:  python day1/labs/block3-ai-review/score.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
