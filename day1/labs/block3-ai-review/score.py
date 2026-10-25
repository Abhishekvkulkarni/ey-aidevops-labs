#!/usr/bin/env python3
"""Score what the tools found in the seeded PR.

  python day1/labs/block3-ai-review/score.py            score everything found so far (Trivy + AI reviewer)
  python day1/labs/block3-ai-review/score.py --reveal   show the answer key (run this LAST)

Rules: 5 planted issues, 20 points each found by any tool. Minus 5 for each false positive.
A finding matches an issue when the file AND the category match. Trivy findings in files the
PR did not change are ignored. Reads day1/labs/block3-ai-review/trivy.json and day1/labs/block3-ai-review/ai_findings.json if they exist.
"""
import argparse
import base64
import json
import re
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
TRIVY = HERE / "trivy.json"
AI = HERE / "ai_findings.json"

KEY_B64 = "eyJmaWxlcyI6IFsiYXBpL2FwcC9jb25maWcucHkiLCAiYXBpL2FwcC9yb3V0ZXMvc2hpcG1lbnRzLnB5IiwgImFwaS9hcHAvbWFpbi5weSIsICJkZXBsb3kvZGVidWctdG9vbHMueWFtbCJdLCAiaXNzdWVzIjogW3siZmlsZSI6ICJhcGkvYXBwL2NvbmZpZy5weSIsICJjYXRlZ29yeSI6ICJoYXJkY29kZWQtc2VjcmV0IiwgIndoeSI6ICJBIG5vdGlmaWNhdGlvbi1zZXJ2aWNlIHRva2VuIGlzIGNvbW1pdHRlZCBpbiBzb3VyY2UuIEZpeDogcmVhZCBpdCBmcm9tIGFuIGVudmlyb25tZW50IHZhcmlhYmxlIG9yIHNlY3JldCBzdG9yZSwgYW5kIHJvdGF0ZSB0aGUgdG9rZW4uIn0sIHsiZmlsZSI6ICJhcGkvYXBwL3JvdXRlcy9zaGlwbWVudHMucHkiLCAiY2F0ZWdvcnkiOiAiaW5qZWN0aW9uIiwgIndoeSI6ICJzZWFyY2hfc2hpcG1lbnRzIGJ1aWxkcyBTUUwgd2l0aCBhbiBmLXN0cmluZyBhcm91bmQgdXNlciBpbnB1dCAoY2l0eSkuIEZpeDogdXNlIGEgcGFyYW1ldGVyaXNlZCBxdWVyeSAoV0hFUkUgY2l0eSA9ID8pLiJ9LCB7ImZpbGUiOiAiYXBpL2FwcC9yb3V0ZXMvc2hpcG1lbnRzLnB5IiwgImNhdGVnb3J5IjogImJyb2tlbi1hY2Nlc3MtY29udHJvbCIsICJ3aHkiOiAiREVMRVRFIC92Mi9zaGlwbWVudHMve2lkfSBoYXMgbm8gRGVwZW5kcyhyZXF1aXJlX2FwaV9rZXkpLCBzbyBhbnlvbmUgY2FuIGRlbGV0ZSBkYXRhLiBOZWVkcyBjb250ZXh0OiBldmVyeSBvdGhlciByb3V0ZSBpbiBtYWluLnB5IHVzZXMgdGhlIGRlcGVuZGVuY3kuIn0sIHsiZmlsZSI6ICJkZXBsb3kvZGVidWctdG9vbHMueWFtbCIsICJjYXRlZ29yeSI6ICJpYWMtbWlzY29uZmlnIiwgIndoeSI6ICJEZWJ1ZyBwb2QgcnVucyBwcml2aWxlZ2VkIGFzIHJvb3QuIEZpeDogZHJvcCBwcml2aWxlZ2VkLCBzZXQgcnVuQXNOb25Sb290LCBvciBkbyBub3QgY29tbWl0IHRoZSBtYW5pZmVzdC4ifSwgeyJmaWxlIjogImFwaS9hcHAvcm91dGVzL3NoaXBtZW50cy5weSIsICJjYXRlZ29yeSI6ICJsb2dpYy1idWciLCAid2h5IjogInBhZ2luYXRlKGl0ZW1zLCBwYWdlIC0gMSwgc2l6ZSk6IHBhZ2luYXRlIGlzIDEtYmFzZWQgKHNlZSBwYWdpbmF0aW9uLnB5KSwgc28gcGFnZSAxIGJlY29tZXMgMCBhbmQgcmFpc2VzIFZhbHVlRXJyb3IsIGEgNTAwIG9uIHRoZSBkZWZhdWx0IHJlcXVlc3QuIE5lZWRzIGNvbnRleHQ6IG9ubHkgdmlzaWJsZSBpZiB5b3UgcmVhZCBwYWdpbmF0aW9uLnB5LiJ9XX0="

# Words that map a free-text AI category onto one of the five scoring categories.
ALIASES = [
    ("hardcoded-secret", ("secret", "credential", "token", "password", "api-key", "apikey")),
    ("injection", ("inject", "sql")),
    ("broken-access-control", ("access", "authz", "authoriz", "authenticat", "auth")),
    ("iac-misconfig", ("misconfig", "privileg", "iac", "kubernetes", "container-security")),
    ("logic-bug", ("logic", "bug", "off-by", "pagination", "boundary", "error")),
]


def key():
    return json.loads(base64.b64decode(KEY_B64).decode("utf-8"))


def norm_file(p):
    p = str(p).replace("\\", "/").strip()
    return re.sub(r"^\./", "", p)


def norm_category(c):
    c = re.sub(r"[\s_]+", "-", str(c).strip().lower())
    for target, words in ALIASES:
        if c == target or any(w in c for w in words):
            return target
    return c


def load_trivy(pr_files):
    out = []
    if not TRIVY.exists():
        return out
    try:
        data = json.loads(TRIVY.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        print("Could not read day1/labs/block3-ai-review/trivy.json (not valid JSON). Re-run the trivy command.")
        return out
    for r in data.get("Results") or []:
        f = norm_file(r.get("Target", ""))
        if f not in pr_files:
            continue
        if r.get("Secrets"):
            out.append((f, "hardcoded-secret", "trivy"))
        if r.get("Misconfigurations"):
            out.append((f, "iac-misconfig", "trivy"))
    return out


def load_ai():
    out = []
    if not AI.exists():
        return out
    try:
        items = json.loads(AI.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        print("Could not read day1/labs/block3-ai-review/ai_findings.json. Re-run ai_review.py.")
        return out
    for i in items:
        if isinstance(i, dict) and i.get("file"):
            out.append((norm_file(i["file"]), norm_category(i.get("category", "")), "ai"))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reveal", action="store_true")
    args = ap.parse_args()
    k = key()

    if args.reveal:
        print("ANSWER KEY: 5 planted issues\n")
        for n, it in enumerate(k["issues"], 1):
            print(f"{n}. {it['file']}  [{it['category']}]\n   {it['why']}\n")
        return 0

    pr_files = set(k["files"])
    findings = load_trivy(pr_files) + load_ai()
    if not findings:
        print("No findings to score yet. Run the Trivy scan and/or ai_review.py first.")
        print("\nScore: 0/100")
        return 0

    sources = {}
    for _, _, src in findings:
        sources[src] = sources.get(src, 0) + 1
    print("Findings counted: " + ", ".join(f"{s} ({n})" for s, n in sorted(sources.items())) + "\n")

    found, matched_keys = 0, set()
    for f, c, src in findings:
        for it in k["issues"]:
            if (it["file"], it["category"]) == (f, c):
                matched_keys.add((f, c))
                break
    found = len(matched_keys)

    seen_fp = set()
    for f, c, src in findings:
        if (f, c) in matched_keys:
            print(f"[FOUND] {f}  [{c}]  via {src}")
        elif (f, c) not in seen_fp:
            seen_fp.add((f, c))
            print(f"[FALSE POSITIVE] {f}  [{c}]  via {src}  (-5)")

    score = max(0, min(100, found * 20 - len(seen_fp) * 5))
    print(f"\nFound {found} of 5 issues, {len(seen_fp)} false positive(s).")
    print(f"Score: {score}/100")
    return 0


if __name__ == "__main__":
    sys.exit(main())
