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
$env:AZURE_OPENAI_ENDPOINT    = $card.openai_endpoint      # used by day1\labs\block3-ai-review\ai_review.py
$env:AZURE_OPENAI_API_KEY     = $card.openai_key
$env:AZURE_OPENAI_DEPLOYMENT  = $card.openai_deployment   # e.g. gpt-4o-mini

# Log docker in to the registry (token passed on stdin, never on the command line)
$env:ACR_TOKEN | docker login $env:ACR_LOGIN_SERVER --username $env:ACR_USER --password-stdin | Out-Null

Write-Host "Lab environment loaded. Namespace: $env:NAMESPACE  Registry: $env:ACR_LOGIN_SERVER" -ForegroundColor Green
