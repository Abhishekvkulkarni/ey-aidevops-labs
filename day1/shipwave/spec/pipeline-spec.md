# Spec: CI/CD pipeline for the Shipwave API

File to produce: `.github/workflows/ci.yml`. Service: `api/`.

## Requirements

1. **P1 Trigger.** Runs on every push to `main` and can be started by hand (`workflow_dispatch`).
2. **P2 Four jobs, named exactly** `lint`, `test`, `build`, `deploy`. Each one needs the one before it (`needs`).
3. **P3 Lint.** Run `ruff check` on `api/`. Fail the job on any error.
4. **P4 Test.** Run `pytest` with coverage on `api/`. Fail below 80% coverage.
5. **P5 Build.** Build the image and push it to ACR as `$ACR_LOGIN_SERVER/$NAMESPACE/shipwave-api:<commit SHA>`. Never use `latest`.
6. **P6 Deploy.** Run `helm upgrade --install shipwave-api helm/ -n $NAMESPACE` with `image.repository` set to `$ACR_LOGIN_SERVER/$NAMESPACE/shipwave-api` and `image.tag` set to the same commit SHA. Wait for the rollout (`--wait --timeout 3m`).
7. **P7 Secrets.** Read `ACR_USER`, `ACR_TOKEN` and `KUBECONFIG_B64` from GitHub secrets, and `ACR_LOGIN_SERVER` and `NAMESPACE` from GitHub variables. No secret value appears in the YAML or in a log.
8. **P8 Permissions.** Set `permissions: contents: read` at the top of the workflow.
9. **P9 Pinned actions.** Use a version tag on every `uses:` line (for example `actions/checkout@v4`).

## Acceptance checks

| # | Check | How |
|---|---|---|
| B1 | Latest run is green | `gh run list --limit 1` shows conclusion `success` |
| B2 | All four jobs ran and passed | `gh run view` lists `lint`, `test`, `build`, `deploy` as success |
| B3 | Cluster runs the pipeline's image | Deployed image tag is the commit SHA |
| B4 | Tests catch broken code | Mutation check kills 6 of 6 injected bugs |
