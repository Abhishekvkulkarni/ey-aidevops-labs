# Sets the GitHub variables and secrets that the pipeline reads (spec P7).
# Run from the repo root AFTER `. C:\EYLAB\ey-aidevops-labs\lab-env.ps1` and after the repo exists on GitHub.
#   .\day1\labs\block2-pipeline\setup-github.ps1

$required = "NAMESPACE", "ACR_LOGIN_SERVER", "ACR_USER", "ACR_TOKEN", "KUBECONFIG_B64"
$missing = $required | Where-Object { -not (Get-Item "env:$_" -ErrorAction SilentlyContinue) }
if ($missing) {
    Write-Host "Missing: $($missing -join ', '). Run  . C:\EYLAB\ey-aidevops-labs\lab-env.ps1  first." -ForegroundColor Red
    exit 1
}

# make sure the API chart and secret are ready (keeps your Block 1 chart if it works, else installs the reference chart)
& "$PSScriptRoot\prereq.ps1"

gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "Not signed in. Run: gh auth login" -ForegroundColor Red; exit 1 }
# sync.ps1 adds a second remote (upstream = trainer repo), which confuses gh. GH_REPO tells gh to always use YOUR fork (origin).
$o = (git remote get-url origin 2>$null)
if ($o -match 'github\.com[:/]([^/\s]+/[^/\s]+?)(\.git)?$') { $env:GH_REPO = $Matches[1]; Write-Host "Using your fork: $($Matches[1])" -ForegroundColor Green }
else { Write-Host 'Could not read the origin remote. Run: git remote -v and tell the trainer.' -ForegroundColor Red; exit 1 }

# Variables (not secret)
gh variable set NAMESPACE        --body $env:NAMESPACE
gh variable set ACR_LOGIN_SERVER --body $env:ACR_LOGIN_SERVER

# Secrets (value is piped in, never shown or stored in a file)
$env:ACR_USER       | gh secret set ACR_USER
$env:ACR_TOKEN      | gh secret set ACR_TOKEN
$env:KUBECONFIG_B64 | gh secret set KUBECONFIG_B64

Write-Host "`nVariables:" -ForegroundColor Green
gh variable list
Write-Host "`nSecrets (names only):" -ForegroundColor Green
gh secret list
