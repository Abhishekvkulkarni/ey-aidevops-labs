# prereq.ps1 - run ONCE from the repo root if you did not finish Block 1 (no shipwave-api chart in helm\templates).
#   . .\lab-env.ps1        (only if this terminal has no lab settings yet)
#   .\day1\labs\block2-pipeline\prereq.ps1
# It adds: the API secret, the API chart, and the image values. It does NOT deploy: the pipeline does that.
$ErrorActionPreference = 'Continue'
if (-not $env:NAMESPACE -or -not $env:ACR_LOGIN_SERVER) { Write-Host 'Lab settings missing. Run first:  . .\lab-env.ps1' -ForegroundColor Red; exit 1 }
if (-not (Test-Path .\helm\templates)) { Write-Host 'Run this from the repo root: cd C:\EYLAB\ey-aidevops-labs' -ForegroundColor Red; exit 1 }

# 1. secret the API reads (same one Block 1 creates)
kubectl -n $env:NAMESPACE get secret shipwave-secrets 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    kubectl -n $env:NAMESPACE create secret generic shipwave-secrets --from-literal=api-key=demo-key-123
    if ($LASTEXITCODE -ne 0) { Write-Host 'Could not create the secret. Check kubectl and the namespace.' -ForegroundColor Red; exit 1 }
} else { Write-Host 'Secret shipwave-secrets already exists.' -ForegroundColor Green }

# 2. API chart (skipped if you already have your own from Block 1)
$mine = @(Get-ChildItem .\helm\templates -File | Where-Object { $_.Name -ne 'worker.yaml' })
if ($mine.Count -gt 0) {
    Write-Host 'helm\templates already has your API template. Keeping yours.' -ForegroundColor Green
} else {
    Copy-Item .\day1\labs\block2-pipeline\prereq\api.yaml .\helm\templates\api.yaml
    Write-Host 'Added helm\templates\api.yaml' -ForegroundColor Green
    # image values for our chart (the pipeline overrides the tag with the commit SHA)
    if (-not (Select-String -Path .\helm\values.yaml -Pattern '^image:' -Quiet)) {
        Add-Content -Path .\helm\values.yaml -Value "`nimage:`n  repository: $env:ACR_LOGIN_SERVER/$env:NAMESPACE/shipwave-api`n  tag: initial"
        Write-Host 'Added image values to helm\values.yaml' -ForegroundColor Green
    }
}

# 4. check the chart
helm lint helm/
