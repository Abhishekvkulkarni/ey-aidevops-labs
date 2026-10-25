# Dot-source this at the start of every terminal:   . C:\EYLAB\ey-aidevops-labs\lab-env.ps1
# It reads your lab card (C:\EYLAB\lab-card.json, placed on your VM by the trainer) and sets environment variables.
# Nothing secret is stored in this file.

$cardPath = "C:\EYLAB\lab-card.json"
if (-not (Test-Path $cardPath)) {
    Write-Host "Lab card not found at $cardPath. Ask the trainer." -ForegroundColor Red
    return
}
$card = Get-Content $cardPath -Raw | ConvertFrom-Json

$env:NAMESPACE                = $card.namespace            # e.g. ff-u07
$env:ACR_LOGIN_SERVER         = $card.acr_login_server     # e.g. devproacr.azurecr.io
$env:ACR_USER                 = $card.acr_user
$env:ACR_TOKEN                = $card.acr_token
$env:KUBECONFIG               = $card.kubeconfig_path      # file restricted to your namespace
$env:KUBECONFIG_B64           = [Convert]::ToBase64String([IO.File]::ReadAllBytes($card.kubeconfig_path))
$env:AZURE_OPENAI_ENDPOINT    = $card.openai_endpoint      # used by lab2\ai_review.py
$env:AZURE_OPENAI_API_KEY     = $card.openai_key
$env:AZURE_OPENAI_DEPLOYMENT  = $card.openai_deployment   # e.g. gpt-4o-mini

# Log docker in to the registry (token passed on stdin, never on the command line)
$env:ACR_TOKEN | docker login $env:ACR_LOGIN_SERVER --username $env:ACR_USER --password-stdin | Out-Null

Write-Host "Lab environment loaded. Namespace: $env:NAMESPACE  Registry: $env:ACR_LOGIN_SERVER" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Lab 1 helpers: a fair "basic prompt vs spec" comparison.
#   Start-BasicRun   hide spec\, reset api\ and helm\ (do this, then use a NEW Copilot chat)
#   Get-LabScore     run lab1\verify.py and record the score for the current run
#   Start-SpecRun    keep the basic work in Git, restore spec\, reset api\ and helm\
#   Show-Scores      print both scores side by side
# ---------------------------------------------------------------------------
$global:Lab1Repo  = "C:\EYLAB\ey-aidevops-labs"
$global:Lab1State = "C:\EYLAB\lab1-state.json"
$global:Lab1Hide  = "C:\EYLAB\.hidden-spec"

function Get-Lab1State {
    if (Test-Path $global:Lab1State) { return (Get-Content $global:Lab1State -Raw | ConvertFrom-Json) }
    return [pscustomobject]@{ base = $null; phase = $null; basic = $null; spec = $null }
}

function Save-Lab1State($state) {
    $state | ConvertTo-Json | Set-Content -Path $global:Lab1State -Encoding UTF8
}

function Reset-Lab1Work($base) {
    # Put api\ and helm\ back exactly as they were at the start (removes files the AI added).
    $added = git diff --name-only --diff-filter=A $base -- api helm
    foreach ($f in $added) { git rm -f -q -- $f 2>$null }
    git checkout $base -- api helm 2>$null
    git clean -fdq -- api helm
}

function Start-BasicRun {
    param([switch]$Fresh)
    Push-Location $global:Lab1Repo
    try {
        $s = Get-Lab1State
        if ($Fresh -or -not $s.base) {
            $s = [pscustomobject]@{ base = (git rev-parse HEAD).Trim(); phase = $null; basic = $null; spec = $null }
        }
        # hide the spec so the AI cannot read it
        if (Test-Path "spec") {
            if (Test-Path "$global:Lab1Hide\spec") { Remove-Item "$global:Lab1Hide\spec" -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $global:Lab1Hide | Out-Null
            Move-Item "spec" "$global:Lab1Hide\spec"
        }
        Reset-Lab1Work $s.base
        $s.phase = "basic"
        $s.basic = $null
        Save-Lab1State $s
        Write-Host "BASIC RUN ready. spec\ is hidden and api\ + helm\ are reset." -ForegroundColor Green
        Write-Host "Next: open a NEW Copilot chat (agent mode), send the basic prompt, then run Get-LabScore" -ForegroundColor Yellow
    } finally { Pop-Location }
}

function Get-LabScore {
    Push-Location $global:Lab1Repo
    try {
        $out = (python lab1\verify.py 2>&1 | Out-String)
        Write-Host $out
        $s = Get-Lab1State
        if (-not $s.phase) {
            Write-Host "Run Start-BasicRun first, so the score is recorded." -ForegroundColor Red
            return
        }
        if ($out -match 'Total:\s*(\d+)/100') {
            $score = [int]$Matches[1]
            if ($s.phase -eq "spec") { $s.spec = $score } else { $s.basic = $score }
            Save-Lab1State $s
            Write-Host "Recorded $($s.phase) score: $score/100" -ForegroundColor Green
        }
    } finally { Pop-Location }
}

function Start-SpecRun {
    Push-Location $global:Lab1Repo
    try {
        $s = Get-Lab1State
        if ($s.phase -ne "basic") { Write-Host "Run Start-BasicRun first." -ForegroundColor Red; return }
        if ($null -eq $s.basic) { Write-Host "Run Get-LabScore first, to score the basic version." -ForegroundColor Red; return }
        # bring the spec back, then keep the basic work in Git
        if ((-not (Test-Path "spec")) -and (Test-Path "$global:Lab1Hide\spec")) {
            Move-Item "$global:Lab1Hide\spec" "spec"
        }
        git add -A
        git commit -q -m "basic prompt version" 2>$null
        Reset-Lab1Work $s.base
        git commit -q -m "reset api and helm for the spec run" 2>$null
        $s.phase = "spec"
        $s.spec = $null
        Save-Lab1State $s
        Write-Host "SPEC RUN ready. spec\ is back and api\ + helm\ are reset." -ForegroundColor Green
        Write-Host "Next: open a NEW Copilot chat, attach spec\api-container-spec.md, send the spec prompt, then run Get-LabScore" -ForegroundColor Yellow
    } finally { Pop-Location }
}

function Show-Scores {
    $s = Get-Lab1State
    $b = if ($null -ne $s.basic) { "$($s.basic)/100" } else { "not scored" }
    $p = if ($null -ne $s.spec)  { "$($s.spec)/100" }  else { "not scored" }
    Write-Host ""
    Write-Host "  Basic prompt : $b"
    Write-Host "  Spec-driven  : $p"
    if (($null -ne $s.basic) -and ($null -ne $s.spec)) {
        Write-Host "  Difference   : +$($s.spec - $s.basic) points" -ForegroundColor Green
    }
    Write-Host ""
}
