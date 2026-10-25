#!/usr/bin/env python3
"""Score the Dockerfile and Helm chart against spec/api-container-spec.md (R1 to R8).
Static checks only: nothing is built or deployed.

Usage (from the repo root):  python lab1/verify.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCKERFILE = ROOT / "api" / "Dockerfile"
DOCKERIGNORE = ROOT / "api" / ".dockerignore"
HELM = ROOT / "helm"


def read(p):
    try:
        return p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None


def dockerfile_lines(text):
    """Dockerfile instructions with comments removed and line continuations joined."""
    text = re.sub(r"\\\s*\n", " ", text)
    return [l.strip() for l in text.splitlines() if l.strip() and not l.strip().startswith("#")]


def api_templates():
    """All chart templates except the pre-built worker's."""
    out = []
    tdir = HELM / "templates"
    if tdir.is_dir():
        for p in sorted(tdir.rglob("*")):
            if p.is_file() and p.suffix in (".yaml", ".yml", ".tpl") and not p.name.lower().startswith("worker"):
                out.append(read(p) or "")
    return "\n".join(out)


def r1(df, **_):
    if df is None:
        return 0, "api/Dockerfile not found"
    stages, bad = set(), []
    for l in dockerfile_lines(df):
        m = re.match(r"FROM\s+(?:--platform=\S+\s+)?(\S+)(?:\s+AS\s+(\S+))?", l, re.I)
        if not m:
            continue
        image, alias = m.group(1), m.group(2)
        if image in stages or image.lower() == "scratch":
            pass
        elif "@sha256:" in image:
            pass
        elif ":" not in image.split("/")[-1] or image.endswith(":latest"):
            bad.append(image)
        if alias:
            stages.add(alias)
    if not stages and not any(re.match(r"FROM\s", l, re.I) for l in dockerfile_lines(df)):
        return 0, "no FROM line"
    return (0, "base image not pinned: " + ", ".join(bad)) if bad else (1, "every base image has an exact tag")


def r2(df, **_):
    if df is None:
        return 0, "api/Dockerfile not found"
    users = [l.split(None, 1)[1].strip() for l in dockerfile_lines(df) if re.match(r"USER\s+\S+", l, re.I)]
    if not users:
        return 0, "no USER line, so the container runs as root"
    u = users[-1].split(":")[0]
    if u.lower() == "root" or u == "0":
        return 0, "last USER is root"
    if u.isdigit() and int(u) < 1000:
        return 0, f"USER {u} is below UID 1000"
    return 1, f"runs as {users[-1]}"


def r3(df, **_):
    if df is None:
        return 0, "api/Dockerfile not found"
    froms = [l for l in dockerfile_lines(df) if re.match(r"FROM\s", l, re.I)]
    got, notes = 0.0, []
    if len(froms) >= 2:
        got += 0.7
    else:
        notes.append("not multi-stage")
    if DOCKERIGNORE.is_file():
        got += 0.3
    else:
        notes.append("no api/.dockerignore")
    return got, ("; ".join(notes) or "multi-stage and .dockerignore present")


def r4(tpl, **_):
    if not tpl:
        return 0, "no API templates in helm/templates"
    ro = re.search(r"readOnlyRootFilesystem:\s*true", tpl)
    tmp = re.search(r"emptyDir", tpl) and re.search(r"mountPath:\s*/tmp\b", tpl)
    got, notes = 0.0, []
    if ro:
        got += 0.6
    else:
        notes.append("readOnlyRootFilesystem not true")
    if tmp:
        got += 0.4
    else:
        notes.append("no emptyDir mounted at /tmp")
    return got, ("; ".join(notes) or "read-only root with writable /tmp")


def r5(tpl, values, **_):
    blob = (tpl or "") + "\n" + (values or "")
    if not tpl:
        return 0, "no API templates in helm/templates"
    ok = all(re.search(p, blob) for p in (r"requests:", r"limits:", r"cpu:", r"memory:"))
    return (1, "requests and limits set") if ok else (0, "requests/limits for cpu and memory missing")


def r6(tpl, **_):
    if not tpl:
        return 0, "no API templates in helm/templates"
    live, ready = "livenessProbe" in tpl, "readinessProbe" in tpl
    path = "/health" in tpl
    got, notes = 0.0, []
    for flag, w, msg in ((live, 0.35, "no livenessProbe"), (ready, 0.35, "no readinessProbe"), (path, 0.3, "probes do not use /health")):
        if flag:
            got += w
        else:
            notes.append(msg)
    return got, ("; ".join(notes) or "liveness and readiness on /health")


def r7(df, tpl, values, **_):
    leaks = []
    for l in dockerfile_lines(df or ""):
        if re.search(r"\b(ENV|ARG)\s+API_KEY\b", l):
            leaks.append("Dockerfile sets API_KEY")
    if values and re.search(r"(?i)api[_-]?key\s*:\s*\S", values):
        leaks.append("values.yaml holds an api key")
    ref = tpl and "secretKeyRef" in tpl and "shipwave-secrets" in tpl and re.search(r"key:\s*[\"']?api-key", tpl)
    if leaks:
        return 0, "; ".join(leaks)
    if not ref:
        return 0, "API_KEY is not read from Secret shipwave-secrets (key api-key)"
    return 1, "API_KEY comes from the Kubernetes Secret"


def r8(tpl, values, **_):
    chart = (HELM / "Chart.yaml").is_file()
    got, notes = 0.0, []
    if chart:
        got += 0.3
    else:
        notes.append("no helm/Chart.yaml")
    if values and re.search(r"repository:", values) and re.search(r"tag:", values):
        got += 0.4
    else:
        notes.append("values.yaml has no image repository and tag")
    if tpl and re.search(r"\.Values\.[\w.]*image", tpl):
        got += 0.3
    else:
        notes.append("templates do not read the image from values")
    return got, ("; ".join(notes) or "chart is parameterised by image")


CHECKS = [
    ("R1", "Base image pinned", 12, r1),
    ("R2", "Runs as non-root", 14, r2),
    ("R3", "Multi-stage and .dockerignore", 12, r3),
    ("R4", "Read-only root filesystem", 12, r4),
    ("R5", "CPU and memory requests/limits", 12, r5),
    ("R6", "Liveness and readiness probes", 12, r6),
    ("R7", "Secret handling", 14, r7),
    ("R8", "Helm chart parameterised", 12, r8),
]


def main():
    ctx = dict(df=read(DOCKERFILE), tpl=api_templates(), values=read(HELM / "values.yaml"))
    total = 0
    print("Shipwave container spec check (R1-R8)\n")
    for rid, name, weight, fn in CHECKS:
        frac, why = fn(**ctx)
        pts = round(weight * frac)
        total += pts
        tag = "PASS" if frac >= 1 else ("PART" if frac > 0 else "FAIL")
        print(f"[{tag}] {rid} {name:<34} {pts:>2}/{weight}  {why}")
    print(f"\nTotal: {total}/100")
    return 0


if __name__ == "__main__":
    sys.exit(main())
