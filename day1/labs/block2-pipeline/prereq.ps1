# prereq.ps1 - makes sure Block 2 has a valid API chart and secret. Called automatically by setup-github.ps1.
# Keeps YOUR chart from Block 1 if it lints clean AND uses image.repository / image.tag.
# Otherwise it saves yours in %TEMP% and installs the reference chart. -Force always installs the reference chart.
# It does NOT deploy: the pipeline does that.
param([switch]$Force)
$ErrorActionPreference = 'Continue'
if (-not $env:NAMESPACE -or -not $env:ACR_LOGIN_SERVER) { Write-Host 'Lab settings missing. Run first:  . .\lab-env.ps1' -ForegroundColor Red; exit 1 }
if (-not (Test-Path .\helm\templates)) { Write-Host 'Run this from the repo root: cd C:\EYLAB\ey-aidevops-labs' -ForegroundColor Red; exit 1 }

# 1. secret the API reads (same one Block 1 creates)
kubectl -n $env:NAMESPACE get secret shipwave-secrets 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    kubectl -n $env:NAMESPACE create secret generic shipwave-secrets --from-literal=api-key=demo-key-123
    if ($LASTEXITCODE -ne 0) { Write-Host 'Could not create the secret. Check kubectl and the namespace.' -ForegroundColor Red; exit 1 }
} else { Write-Host 'Secret shipwave-secrets already exists.' -ForegroundColor Green }

# 2. API chart: keep yours only if it works with the pipeline
$mine = @(Get-ChildItem .\helm\templates -File | Where-Object { $_.Name -ne 'worker.yaml' })
$replace = $true
if ($mine.Count -gt 0 -and -not $Force) {
    helm lint helm/ 2>&1 | Out-Null
    $lintOk = ($LASTEXITCODE -eq 0)
    $usesKeys = [bool](Select-String -Path .\helm\templates\* -Pattern '\.Values\.image\.repository' -Quiet)
    if ($lintOk -and $usesKeys) {
        $replace = $false
        Write-Host 'Your chart from Block 1 works with the pipeline. Keeping it.' -ForegroundColor Green
    } else {
        Write-Host 'Your chart from Block 1 does not work with the pipeline (lint fails, or it does not use image.repository / image.tag).' -ForegroundColor Yellow
    }
}
if ($replace) {
    if ($mine.Count -gt 0) {
        $bk = Join-Path $env:TEMP ('helm_backup_' + (Get-Date -Format 'HHmmss'))
        New-Item -ItemType Directory -Force $bk | Out-Null
        Copy-Item .\helm\values.yaml $bk
        $mine | Move-Item -Destination $bk
        Write-Host "Your old chart files are saved in $bk" -ForegroundColor Yellow
    }
    Copy-Item .\day1\labs\block2-pipeline\prereq\api.yaml .\helm\templates\api.yaml -Force
    @(
        '# The worker image is pre-built and shared by the trainer.',
        'worker:',
        '  image:',
        "    repository: $env:ACR_LOGIN_SERVER/shared/shipwave-worker",
        '    tag: "1.0"',
        '',
        '# API image: the pipeline sets the tag to the commit SHA at deploy time.',
        'image:',
        "  repository: $env:ACR_LOGIN_SERVER/$env:NAMESPACE/shipwave-api",
        '  tag: initial'
    ) | Set-Content .\helm\values.yaml -Encoding ascii
    Write-Host 'Installed the reference API chart (helm\templates\api.yaml) and image values.' -ForegroundColor Green
}

# 3. final check
helm lint helm/
