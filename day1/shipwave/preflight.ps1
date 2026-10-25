# Checks that this VM has everything Day 1 needs.   Run:  . C:\EYLAB\lab-env.ps1   then   .\preflight.ps1
$script:bad = 0
function Check($name, [scriptblock]$test, $hint) {
    $ok = $false; $detail = ""
    try { $detail = (& $test 2>&1 | Out-String).Trim(); $ok = ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) -and $detail -ne "FAIL" } catch { $detail = $_.Exception.Message }
    if ($ok) { Write-Host ("[PASS] {0}" -f $name) -ForegroundColor Green }
    else { $script:bad++; Write-Host ("[FAIL] {0}  ->  {1}" -f $name, $hint) -ForegroundColor Red }
}

Check "git"            { git --version }            "install Git for Windows"
Check "GitHub CLI"     { gh --version }             "install gh, then run: gh auth login"
Check "gh signed in"   { gh auth status }           "run: gh auth login"
Check "Python 3.11+"   { python -c "import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)" } "install Python 3.11 or newer and add it to PATH"
Check "Python packages" { python -c "import fastapi, httpx, pytest, pytest_cov" } "run: pip install -r lab-requirements.txt"
Check "ruff"           { ruff --version }           "run: pip install -r lab-requirements.txt"
Check "VS Code"        { code --version }           "install VS Code with the GitHub Copilot extension"
# Docker runs inside WSL2; start it if it is not up yet (set up by install-docker.ps1)
if (-not $env:DOCKER_HOST -or -not (docker version --format '{{.Server.Version}}' 2>$null)) {
    if (Test-Path C:\ProgramData\EYLAB\start-docker.ps1) { Write-Host "Starting Docker..."; & C:\ProgramData\EYLAB\start-docker.ps1 }
}
Check "Docker engine running" { docker version --format '{{.Server.Version}}' } "run: C:\ProgramData\EYLAB\start-docker.ps1  (then open a NEW PowerShell window)"
Check "Docker runs LINUX containers" { if ((docker info --format '{{.OSType}}') -eq 'linux') { 'ok' } else { 'FAIL' } } "Docker must run in WSL2 (Linux). Trainer: run install-docker.ps1 on this VM"
Check "base image pulled" { docker image inspect python:3.12-slim } "run: docker pull python:3.12-slim"
Check "kubectl"        { kubectl version --client } "install kubectl"
Check "helm 3"         { helm version --short }     "install helm 3"
Check "trivy"          { trivy --version }          "install trivy and run: trivy image --download-db-only"
Check "lab card loaded" { if ($env:NAMESPACE -and $env:ACR_LOGIN_SERVER -and $env:ACR_USER -and $env:ACR_TOKEN -and $env:KUBECONFIG -and $env:AZURE_OPENAI_ENDPOINT -and $env:AZURE_OPENAI_API_KEY) { 'ok' } else { 'FAIL' } } "run: . C:\EYLAB\lab-env.ps1 (and check C:\EYLAB\lab-card.json)"
Check "cluster reachable (your namespace)" { kubectl -n $env:NAMESPACE get pods } "check the kubeconfig and your namespace"
Check "ACR login"      { docker pull "$env:ACR_LOGIN_SERVER/shared/shipwave-worker:1.0" } "worker image missing or ACR login failed (trainer: push the worker image)"

if ($script:bad -eq 0) { Write-Host "`nAll checks passed. Ready for Day 1." -ForegroundColor Green }
else { Write-Host "`n$script:bad check(s) failed. Fix them or tell the trainer." -ForegroundColor Red }
