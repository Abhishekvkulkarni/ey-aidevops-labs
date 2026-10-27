# preflight.ps1  -  checks this VM before class.   Run from the repo folder, in a NEW terminal:   .\preflight.ps1
# Day 2 needs: git, GitHub sign-in, Python + pytest, VS Code + Copilot, the repo folder. Docker is only a warning on Day 2.
# Use  .\preflight.ps1 -Day 1  to also require Docker, the cluster and the registry.
param([int]$Day = 2)
$script:bad = @(); $script:warn = @()
function Check($name, [scriptblock]$test, $hint, [switch]$Soft) {
    $ok = $false; $global:LASTEXITCODE = $null
    try { $out = (& $test 2>&1 | Out-String).Trim(); $ok = (($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) -and $out -ne 'FAIL') } catch { $ok = $false }
    if ($ok) { Write-Host ("[PASS] {0}" -f $name) -ForegroundColor Green }
    elseif ($Soft) { $script:warn += $name; Write-Host ("[WARN] {0}  ->  {1}" -f $name, $hint) -ForegroundColor Yellow }
    else { $script:bad += $name; Write-Host ("[FAIL] {0}  ->  {1}" -f $name, $hint) -ForegroundColor Red }
}
$dockerSoft = ($Day -ge 2)
$d2soft = ($Day -ge 2)   # Day 2 labs only need git, Python+pytest, VS Code + Copilot: everything else is a warning

Check "in the repo folder"    { if ((Test-Path .\helm) -and (Test-Path .\day1) -and (Test-Path .\sync.ps1)) { 'ok' } else { 'FAIL' } } "run:  cd C:\EYLAB\ey-aidevops-labs"
Check "git"                   { git --version }               "install Git for Windows"
Check "GitHub CLI"            { gh --version }                "install gh"
Check "gh signed in"          { gh auth status }              "run: gh auth login" -Soft:$d2soft
Check "trainer remote (upstream)" { if ((git remote) -contains 'upstream') { 'ok' } else { 'FAIL' } } "run: .\sync.ps1  (it adds it)"
Check "helm/values.yaml clean"    { if (Select-String -Path .\helm\values.yaml -SimpleMatch 'REPLACE_WITH_SHARED_ACR' -Quiet) { 'FAIL' } else { 'ok' } } "run: .\sync.ps1  (it fixes the registry name)" -Soft:$d2soft
Check "Python 3.11+"          { python -c "import sys; sys.exit(0 if sys.version_info >= (3,11) else 1)" } "install Python 3.11 or newer"
Check "pytest + coverage"     { python -c "import pytest, pytest_cov, httpx, fastapi" } "run: pip install -r lab-requirements.txt"
Check "ruff"                  { ruff --version }              "run: pip install -r lab-requirements.txt"
Check "VS Code"               { code --version }              "install VS Code"
Check "Copilot extension"     { if ((code --list-extensions 2>$null) -match 'github.copilot') { 'ok' } else { 'FAIL' } } "VS Code > Extensions > install GitHub Copilot, then sign in"
Check "lab card loaded"       { if ($env:NAMESPACE -and $env:ACR_LOGIN_SERVER -and $env:AZURE_OPENAI_ENDPOINT -and $env:AZURE_OPENAI_API_KEY) { 'ok' } else { 'FAIL' } } "run: . C:\EYLAB\ey-aidevops-labs\lab-env.ps1   (once; later terminals load it by themselves)" -Soft:$d2soft
# tools must actually RUN (a file can exist and still be corrupt)
Check "kubectl runs"          { kubectl version --client }    "kubectl is missing or corrupt: tell the trainer" -Soft:$d2soft
Check "helm 3 runs"           { helm version --short }        "helm is missing or corrupt: tell the trainer" -Soft:$d2soft
Check "trivy runs"            { trivy --version }             "trivy is missing or corrupt: tell the trainer" -Soft:$d2soft
# Docker (engine answers, runs LINUX containers)
Check "Docker engine reachable" { docker version --format '{{.Server.Version}}' } "run: powershell -ExecutionPolicy Bypass -File .\install-docker.ps1" -Soft:$dockerSoft
Check "Docker runs Linux containers" { if ((docker info --format '{{.OSType}}') -eq 'linux') { 'ok' } else { 'FAIL' } } "run: powershell -ExecutionPolicy Bypass -File .\install-docker.ps1" -Soft:$dockerSoft
if ($Day -le 1) {
    Check "cluster reachable (your namespace)" { kubectl -n $env:NAMESPACE get pods } "check the lab card and your namespace"
    Check "ACR login"         { docker pull "$env:ACR_LOGIN_SERVER/shared/shipwave-worker:1.0" } "worker image missing or registry login failed"
}

Write-Host ""
$line = "PREFLIGHT $env:COMPUTERNAME day$Day | " + $(if ($script:bad.Count) { 'FAIL: ' + ($script:bad -join '; ') } else { 'OK' }) + $(if ($script:warn.Count) { ' | warn: ' + ($script:warn -join '; ') } else { '' })
if ($script:bad.Count -eq 0) { Write-Host "All required checks passed. Ready for Day $Day." -ForegroundColor Green }
else { Write-Host "$($script:bad.Count) required check(s) failed. Fix them or paste the line below in the call chat:" -ForegroundColor Red }
Write-Host $line
