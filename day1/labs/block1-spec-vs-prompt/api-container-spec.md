# Spec: containerize and deploy the Shipwave API

Service: `api/` (FastAPI, port 8000). Target: your AKS namespace `$NAMESPACE`.

## Requirements

1. **R1 Base image.** Pinned to an exact version tag (for example `python:3.12-slim`). Never `latest`.
2. **R2 Non-root.** The container runs as a non-root user with a numeric UID of 1000 or higher (for example `USER 1000`). If the chart sets `runAsNonRoot: true`, also set `runAsUser` to the same UID.
3. **R3 Small image.** Multi-stage build, `.dockerignore` present, no build tools in the final image.
4. **R4 Read-only filesystem.** `readOnlyRootFilesystem: true`. Writable paths only through an `emptyDir` mounted at `/tmp`.
5. **R5 Resources.** CPU and memory requests and limits set on every container. Use 2 replicas, requests of `100m` CPU and `128Mi` memory, limits of `250m` CPU and `256Mi` memory, so the namespace quota still has room for a rolling update.
6. **R6 Probes.** Liveness and readiness probes on `GET /health`.
7. **R7 Secret handling.** `API_KEY` comes from the Kubernetes Secret `shipwave-secrets` (key `api-key`). It never appears in the Dockerfile, `values.yaml` or the image.
8. **R8 Helm.** One chart in `helm/` that installs the API with `helm upgrade --install`. Image repository and tag are values (`image.repository`, `image.tag`). Add the API as a Deployment named `shipwave-api` and a Service named `shipwave-api` on port 8000. Keep the existing worker template as it is.

## Acceptance checks (all must pass)

| # | Check | How |
|---|---|---|
| A1 | Image builds | `docker build` exits 0 |
| A2 | Runs as non-root | `docker run --rm --entrypoint id <image>` shows a UID other than 0 |
| A3 | No HIGH or CRITICAL findings | `trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 <image>` exits 0 |
| A4 | Chart is valid | `helm lint helm/` reports 0 charts failed |
| A5 | Pods Ready | `kubectl get pods` shows every API pod Running and READY n/n |
| A6 | Health endpoint | `GET /health` returns 200 through a port-forward |

## Out of scope

The worker image is pre-built. Terraform for storage is shown by the trainer (Anil) and is not part of this lab.
