# Sets the GitHub variables and secrets that the pipeline reads (spec P7).
# Run from the repo root AFTER `. C:\EYLAB\ey-aidevops-labs\lab-env.ps1` and after the repo exists on GitHub.
#   .\day1\labs\block2-pipeline\setup-github.ps1

$required = "NAMESPACE", "ACR_LOGIN_SERVER", "ACR_USER", "ACR_TOKEN", "KUBECONFIG_B64"
$missing = $required | Where-Object { -not (Get-Item "env:$_" -ErrorAction SilentlyContinue) }
if ($missing) {
    Write-Host "Missing: $($missing -join ', '). Run  . C:\EYLAB\ey-aidevops-labs\lab-env.ps1  first." -ForegroundColor Red
    exit 1
}

gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "Not signed in. Run: gh auth login" -ForegroundColor Red; exit 1 }

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
