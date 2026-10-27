# lab-env.ps1  -  loads your lab card into this terminal. Loaded AUTOMATICALLY in every new terminal after the first run.
# First time:  . C:\EYLAB\ey-aidevops-labs\lab-env.ps1        (note the dot and the space at the start)
# It reads C:\EYLAB\lab-card.json (placed on your VM by the trainer). Nothing secret is stored in this file.
param([switch]$Quiet)
function Say($m, $c = 'Green') { if (-not $Quiet) { Write-Host $m -ForegroundColor $c } }

$cardPath = 'C:\EYLAB\lab-card.json'
if (-not (Test-Path $cardPath)) { Say "Lab card not found at $cardPath. Ask the trainer." 'Red'; return }
$card = Get-Content $cardPath -Raw | ConvertFrom-Json

$env:NAMESPACE                = $card.namespace            # e.g. ff-u07
$env:ACR_LOGIN_SERVER         = $card.acr_login_server
$env:ACR_USER                 = $card.acr_user
$env:ACR_TOKEN                = $card.acr_token
$env:KUBECONFIG               = $card.kubeconfig_path      # file restricted to your namespace
if (Test-Path $card.kubeconfig_path) { $env:KUBECONFIG_B64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($card.kubeconfig_path)) }
$env:AZURE_OPENAI_ENDPOINT    = $card.openai_endpoint      # used by the ai_review / release-notes scripts
$env:AZURE_OPENAI_API_KEY     = $card.openai_key
$env:AZURE_OPENAI_DEPLOYMENT  = $card.openai_deployment

# Docker (only if it was set up on this VM): refresh DOCKER_HOST, start the engine if it is down
$ey = 'C:\ProgramData\EYLAB'
if ((Test-Path "$ey\bin") -and ($env:Path -notlike "*$ey\bin*")) { $env:Path += ";$ey\bin" }
function Test-Engine {
    if (-not (Test-Path "$ey\docker-host.txt")) { return $false }
    $u = (Get-Content "$ey\docker-host.txt" -Raw).Trim()
    if ($u -notmatch '^tcp://([\d\.]+):(\d+)$') { return $false }
    try {
        $t = New-Object Net.Sockets.TcpClient; $r = $t.BeginConnect($Matches[1], [int]$Matches[2], $null, $null)
        $ok = $r.AsyncWaitHandle.WaitOne(1500) -and $t.Connected; $t.Close()
        if ($ok) { $env:DOCKER_HOST = $u }
        return $ok
    } catch { return $false }
}
$dockerOk = Test-Engine
if (-not $dockerOk -and (Test-Path "$ey\start-docker.ps1")) {
    Say 'Starting Docker (up to a minute, only the first terminal after a restart)...' 'Yellow'
    & "$ey\start-docker.ps1" -Quiet
    $dockerOk = Test-Engine
}
if ($dockerOk) {
    try { $env:ACR_TOKEN | docker login $env:ACR_LOGIN_SERVER --username $env:ACR_USER --password-stdin 2>$null | Out-Null } catch {}
}

# Load this file in every new terminal (also the VS Code terminal): adds one line to your PowerShell profile, once
try {
    $prof = $PROFILE.CurrentUserAllHosts
    $mark = 'ey-aidevops-labs\lab-env.ps1'
    if (-not (Test-Path $prof) -or -not (Select-String -Path $prof -SimpleMatch $mark -Quiet)) {
        New-Item -ItemType File -Force -Path $prof | Out-Null
        Add-Content -Path $prof -Value "`n# EY lab environment (added by lab-env.ps1)`nif (Test-Path 'C:\EYLAB\ey-aidevops-labs\lab-env.ps1') { . 'C:\EYLAB\ey-aidevops-labs\lab-env.ps1' -Quiet }"
    }
} catch {}

Say "Lab environment loaded. Namespace: $env:NAMESPACE   Registry: $env:ACR_LOGIN_SERVER   Docker: $(if ($dockerOk) { 'ready' } else { 'not running (not needed on Day 2)' })"
