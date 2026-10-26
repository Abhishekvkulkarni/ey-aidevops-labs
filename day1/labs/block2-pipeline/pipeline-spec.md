# Pipeline spec (Block 2)
P1. Workflow file .github/workflows/ci.yml; triggers on push to main only.
P2. Four jobs with exactly these names: lint, test, build, deploy.
P3. Order: lint -> test -> build -> deploy (each job needs the previous one).
P4. test job: pip install -r api/requirements.txt pytest httpx, then run from the api folder: python -m pytest testsP5. Image tag is the commit SHA (github.sha). Never latest.
P6. build job: docker build api/ and push to ${ACR_LOGIN_SERVER}/${NAMESPACE}/api:<sha>.
P7. Secrets come from GitHub secrets (ACR_USER, ACR_TOKEN, KUBECONFIG_B64) and variables (NAMESPACE, ACR_LOGIN_SERVER). Nothing hardcoded, nothing echoed.
P8. deploy job: decode KUBECONFIG_B64, then helm upgrade --install with image tag = the SHA, in namespace NAMESPACE.
P9. Every action uses a version tag (for example actions/checkout@v4). Never @main or @master.