# install-docker.ps1  -  Docker Engine (Linux containers) on a Windows Server 2022 lab VM, via WSL2 + Ubuntu.
# Run ONCE per VM, in an ADMIN PowerShell, signed in as the lab user (e.g. azureuser):
#     powershell -ExecutionPolicy Bypass -File C:\EYLAB\install-docker.ps1
# Safe to re-run.
$ErrorActionPreference = 'Stop'
function Say($m) { Write-Host "== $m" -ForegroundColor Cyan }
function WslClean($x) { ($x -replace "`0", '' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() }) }

# 1. WSL2 + an Ubuntu distro must exist (needs nested virtualization on the VM size)
$distros = @()
try { $distros = @(WslClean (wsl -l -q 2>$null)) } catch {}
if (-not $distros) {
    Say "No WSL distro found. Installing WSL + Ubuntu (a reboot may be needed)"
    wsl --install -d Ubuntu --no-launch
    Write-Host "If Windows asked for a reboot: restart the VM, then run this script again." -ForegroundColor Yellow
    Write-Host "If no reboot was asked: run  ubuntu install --root  then run this script again." -ForegroundColor Yellow
    exit 1
}
$distro = $distros | Where-Object { $_ -like 'Ubuntu*' } | Select-Object -First 1
if (-not $distro) { $distro = $distros[0] }
Say "Using WSL distro: $distro"
$ver = WslClean (wsl -l -v) | Where-Object { $_ -match [regex]::Escape($distro) }
if ($ver -notmatch '\s2\s*$') { Write-Host "Distro is not WSL version 2. Run: wsl --set-version $distro 2" -ForegroundColor Red; exit 1 }

# 2. Docker Engine inside Ubuntu (our own start script runs dockerd, so turn off the packaged service)
Say "Installing Docker Engine in $distro"
wsl -d $distro -u root -- bash -c "command -v dockerd >/dev/null || (apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io)"
wsl -d $distro -u root -- bash -c "systemctl disable --now docker docker.socket 2>/dev/null; service docker stop 2>/dev/null; pkill dockerd 2>/dev/null; sleep 2; rm -f /var/run/docker.pid; true"

# 3. Windows docker CLI
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Say "Installing docker CLI"
    choco install docker-cli -y --no-progress
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

# 4. Start script: runs dockerd in WSL, finds the WSL IP, sets DOCKER_HOST (user env + this process)
#    (Windows localhost forwarding drops 'docker run' output, so we connect to the WSL IP directly.)
New-Item -ItemType Directory -Force C:\ProgramData\EYLAB | Out-Null
$start = @'
$ErrorActionPreference = 'SilentlyContinue'
$d = '__DISTRO__'
$up = wsl -d $d -u root -- bash -c "pgrep -x dockerd"
if (-not $up) {
    Start-Process wsl -WindowStyle Hidden -ArgumentList "-d $d -u root -- dockerd -H tcp://0.0.0.0:2375 -H unix:///var/run/docker.sock"
}
$ok = $false
for ($i = 0; $i -lt 40 -and -not $ok; $i++) {
    Start-Sleep -Seconds 2
    $ip = ((wsl -d $d -- hostname -I) -replace "`0", '').Trim().Split(' ')[0]
    if ($ip) { $null = docker -H "tcp://${ip}:2375" version --format '{{.Server.Version}}' 2>$null; $ok = ($LASTEXITCODE -eq 0) }
}
if ($ok) {
    $env:DOCKER_HOST = "tcp://${ip}:2375"
    [Environment]::SetEnvironmentVariable('DOCKER_HOST', $env:DOCKER_HOST, 'User')
    Write-Host "Docker ready: $env:DOCKER_HOST  (open a NEW PowerShell window to pick it up)"
} else { Write-Host "Docker did not start. Run: wsl -d $d -u root -- dockerd" -ForegroundColor Red }
'@
Set-Content -Path C:\ProgramData\EYLAB\start-docker.ps1 -Value $start.Replace('__DISTRO__', $distro) -Encoding ASCII

# 5. Start Docker at every logon of this user
Say "Registering logon task"
$user = "$env:USERDOMAIN\$env:USERNAME"
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\ProgramData\EYLAB\start-docker.ps1'
$trg = New-ScheduledTaskTrigger -AtLogOn -User $user
$prn = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'LabDocker' -Action $act -Trigger $trg -Principal $prn -Force | Out-Null

# 6. Start now and verify
Say "Starting Docker"
& C:\ProgramData\EYLAB\start-docker.ps1
Say "Verify"
docker info --format 'OSType={{.OSType}}  Server={{.ServerVersion}}'
Say "Pulling python:3.12-slim"
docker pull python:3.12-slim
$id = docker run --rm --entrypoint id python:3.12-slim
Write-Host "docker run output: $id"
if ($id -match 'uid=') { Write-Host "`nDOCKER OK. Open a NEW PowerShell window before using docker." -ForegroundColor Green }
else { Write-Host "`nDocker started but 'docker run' printed nothing. Tell the trainer." -ForegroundColor Red }
