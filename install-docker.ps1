# install-docker.ps1  -  Docker (Linux containers) on a Windows Server lab VM, using WSL2 + Ubuntu.
# ONE self-contained script. No Chocolatey. Safe to run again at any time (it repairs a half-done setup).
#
# Run it in PowerShell (right-click > Run as administrator) as the lab user, e.g. azureuser:
#     cd C:\EYLAB\ey-aidevops-labs
#     powershell -ExecutionPolicy Bypass -File .\install-docker.ps1
#
# What it does:
#   1. finds WSL2 + Ubuntu (installs them if missing; a reboot may be needed once)
#   2. turns on systemd inside Ubuntu and installs Docker Engine there (apt, docker.io)
#   3. makes the engine listen on TCP 2375 with a systemd override (NOT daemon.json "hosts", which clashes with -H fd://)
#   4. installs the Windows docker CLI by direct download (falls back to a tiny wrapper that calls docker inside WSL)
#   5. sets DOCKER_HOST permanently and starts the engine at every logon
#   6. self-test: docker version, then docker run (must print output)
# A log is saved to C:\EYLAB\docker-setup.log. If anything fails, send that file to the trainer.
param([switch]$SkipPull)
$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function Say($m)  { Write-Host "== $m" -ForegroundColor Cyan }
function Good($m) { Write-Host "   OK  $m" -ForegroundColor Green }
function Warn($m) { Write-Host "   !!  $m" -ForegroundColor Yellow }
function Stop-Here($m) { Write-Host "`nFAILED: $m" -ForegroundColor Red; Write-Host "Send C:\EYLAB\docker-setup.log to the trainer." -ForegroundColor Red; try { Stop-Transcript | Out-Null } catch {}; exit 1 }
function WslClean($x) { ($x -replace "`0", '' | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() }) }

$EY  = 'C:\ProgramData\EYLAB'
$BIN = "$EY\bin"
New-Item -ItemType Directory -Force $EY, $BIN, C:\EYLAB | Out-Null
try { icacls $EY /grant "Users:(OI)(CI)M" 2>&1 | Out-Null } catch {}
try { Start-Transcript -Path C:\EYLAB\docker-setup.log -Force | Out-Null } catch {}

# ---------------------------------------------------------------- 1. WSL2 + Ubuntu
Say "1/6  WSL2 and Ubuntu"
$distros = @()
try { $distros = @(WslClean (wsl -l -q 2>$null)) } catch {}
if (-not $distros -or $distros.Count -eq 0) {
    Say "No WSL distro found. Installing WSL + Ubuntu"
    wsl --install -d Ubuntu --no-launch
    Write-Host "If Windows asked for a restart: restart the VM, then run this script again." -ForegroundColor Yellow
    Write-Host "If it did not ask: run   ubuntu install --root   and then run this script again." -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}
$distro = $distros | Where-Object { $_ -like 'Ubuntu*' } | Select-Object -First 1
if (-not $distro) { $distro = $distros[0] }
$ver = WslClean (wsl -l -v) | Where-Object { $_ -match [regex]::Escape($distro) }
if ("$ver" -notmatch '\s2\s*$') { Stop-Here "distro $distro is not WSL version 2. Run: wsl --set-version $distro 2" }
Good "WSL distro: $distro (version 2)"

# ---------------------------------------------------------------- bash helper that runs INSIDE Ubuntu
$sh = @'
#!/bin/bash
# usage: engine-setup.sh conf | engine <systemd|manual>        (R = test-only path prefix, empty in real use)
R="${ROOT_PREFIX:-}"
cmd="$1"; mode="$2"
if [ "$cmd" = "conf" ]; then
  f="$R/etc/wsl.conf"; mkdir -p "$(dirname "$f")"; touch "$f"
  if ! grep -qE '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true' "$f"; then
    sed -i -E '/^[[:space:]]*systemd[[:space:]]*=/d' "$f"
    if grep -q '^\[boot\]' "$f"; then sed -i '/^\[boot\]/a systemd=true' "$f"; else printf '\n[boot]\nsystemd=true\n' >> "$f"; fi
    echo "CONF_CHANGED"
  else echo "CONF_OK"; fi
  exit 0
fi
# ---- engine
if ! command -v dockerd >/dev/null 2>&1; then
  echo "== installing docker.io (apt)"
  DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io || { echo "ENGINE_FAIL apt-install"; exit 1; }
fi
# undo an earlier live fix: "hosts" in daemon.json makes the packaged service fail (it already passes -H fd://)
python3 - "$R" <<'PY'
import json, os, sys
p = sys.argv[1] + "/etc/docker/daemon.json"
if os.path.exists(p):
    try: d = json.load(open(p))
    except Exception: d = None
    if isinstance(d, dict) and "hosts" in d:
        d.pop("hosts")
        if d: json.dump(d, open(p, "w"), indent=2)
        else: os.remove(p)
        print("daemon.json: removed hosts")
PY
if [ "$mode" = "systemd" ]; then
  d="$R/etc/systemd/system/docker.service.d"; mkdir -p "$d"
  printf '[Service]\nExecStart=\nExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375 --containerd=/run/containerd/containerd.sock\n' > "$d/override.conf"
  [ -n "$R" ] && { echo "ENGINE_OK mode=systemd (test)"; exit 0; }
  pkill -x dockerd 2>/dev/null; rm -f /var/run/docker.pid
  systemctl daemon-reload
  systemctl unmask docker docker.socket containerd 2>/dev/null
  systemctl enable docker.socket docker containerd >/dev/null 2>&1
  systemctl restart docker
  for i in $(seq 1 25); do
    if systemctl is-active --quiet docker && timeout 2 bash -c 'echo > /dev/tcp/127.0.0.1/2375' 2>/dev/null; then echo "ENGINE_OK mode=systemd"; exit 0; fi
    sleep 1
  done
  echo "--- journalctl -u docker (last lines)"; journalctl -u docker -n 15 --no-pager 2>/dev/null
  echo "ENGINE_FAIL systemd"; exit 2
fi
# manual mode: the Windows start script runs dockerd itself; make sure the packaged service stays out of the way
rm -f "$R/etc/systemd/system/docker.service.d/override.conf"
systemctl disable --now docker docker.socket 2>/dev/null; pkill -x dockerd 2>/dev/null; rm -f /var/run/docker.pid
echo "ENGINE_OK mode=manual"
'@
[IO.File]::WriteAllText("$EY\engine-setup.sh", ($sh -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
$shWsl = '/mnt/c/ProgramData/EYLAB/engine-setup.sh'

# ---------------------------------------------------------------- 2. systemd + engine
Say "2/6  Docker Engine inside $distro (systemd)"
$pid1 = "$(wsl -d $distro -u root -- bash -c 'ps -p 1 -o comm=' 2>$null)".Replace("`0", '').Trim()
$conf = "$(wsl -d $distro -u root -- bash $shWsl conf 2>&1)"
if ($pid1 -ne 'systemd' -or $conf -match 'CONF_CHANGED') {
    if ($conf -match 'CONF_CHANGED' -or $pid1 -ne 'systemd') {
        Warn "restarting WSL so systemd starts"
        wsl --terminate $distro | Out-Null; Start-Sleep -Seconds 4
        $pid1 = "$(wsl -d $distro -u root -- bash -c 'ps -p 1 -o comm=' 2>$null)".Replace("`0", '').Trim()
    }
}
$mode = if ($pid1 -eq 'systemd') { 'systemd' } else { 'manual' }
Good "init in $distro is '$pid1' -> mode: $mode"
$out = wsl -d $distro -u root -- bash $shWsl engine $mode 2>&1 | ForEach-Object { "$_".Replace("`0", '') }
$out | ForEach-Object { Write-Host "   $_" }
if (-not ($out -match 'ENGINE_OK') -and $mode -eq 'systemd') {
    Warn "systemd start failed, falling back to manual mode"
    $mode = 'manual'
    $out = wsl -d $distro -u root -- bash $shWsl engine $mode 2>&1 | ForEach-Object { "$_".Replace("`0", '') }
    $out | ForEach-Object { Write-Host "   $_" }
}
if (-not ($out -match 'ENGINE_OK')) { Stop-Here "Docker Engine could not be set up inside $distro (see lines above)" }
Good "engine configured ($mode)"

# ---------------------------------------------------------------- 3. Windows docker CLI
Say "3/6  Windows docker CLI"
function Test-Cli($exe) { try { $v = & $exe --version 2>&1; return ($LASTEXITCODE -eq 0 -and "$v" -match 'Docker version') } catch { return $false } }
$cli = $null
foreach ($c in @(Get-Command docker.exe -All -ErrorAction SilentlyContinue)) { if (-not $cli -and (Test-Cli $c.Source)) { $cli = $c.Source } }
if (-not $cli -and (Test-Path "$BIN\docker.exe") -and (Test-Cli "$BIN\docker.exe")) { $cli = "$BIN\docker.exe" }
if (-not $cli) {
    foreach ($v in '27.5.1', '27.3.1', '26.1.4', '24.0.7') {
        $zip = "$env:TEMP\docker-$v.zip"; $dir = "$env:TEMP\docker-$v"
        try {
            Warn "downloading docker CLI $v"
            Invoke-WebRequest -UseBasicParsing -Uri "https://download.docker.com/win/static/stable/x86_64/docker-$v.zip" -OutFile $zip -TimeoutSec 180
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
            Expand-Archive -Path $zip -DestinationPath $dir -Force
            Copy-Item "$dir\docker\docker.exe" "$BIN\docker.exe" -Force
            if (Test-Cli "$BIN\docker.exe") { $cli = "$BIN\docker.exe"; break }
            Remove-Item "$BIN\docker.exe" -Force -ErrorAction SilentlyContinue
        } catch { Warn "download of $v failed: $($_.Exception.Message)" }
    }
}
if (-not $cli) {
    Warn "could not download the CLI. Installing a wrapper: 'docker' will run the docker inside $distro"
    [IO.File]::WriteAllText("$BIN\docker.cmd", "@echo off`r`nwsl.exe -d $distro -u root -- docker %*`r`n", [Text.Encoding]::ASCII)
    $cli = "$BIN\docker.cmd"
}
Good "docker CLI: $cli"
# put our bin folder on the user PATH (new terminals) and on this session
$up = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $up) { $up = '' }
if ($up -notlike "*$BIN*") { [Environment]::SetEnvironmentVariable('Path', ($up.TrimEnd(';') + ";$BIN").TrimStart(';'), 'User') }
if ($env:Path -notlike "*$BIN*") { $env:Path += ";$BIN" }
$cliDir = Split-Path $cli
if ($env:Path -notlike "*$cliDir*") { $env:Path += ";$cliDir" }

# ---------------------------------------------------------------- 4. start script (also refreshes DOCKER_HOST)
Say "4/6  Start script and logon task"
$start = @'
# start-docker.ps1  -  starts the Docker engine in WSL, finds its address, sets DOCKER_HOST. Written by install-docker.ps1.
param([switch]$Quiet)
$ErrorActionPreference = 'SilentlyContinue'
$d = '__DISTRO__'; $mode = '__MODE__'; $EY = 'C:\ProgramData\EYLAB'
if (Test-Path "$EY\bin") { if ($env:Path -notlike "*$EY\bin*") { $env:Path += ";$EY\bin" } }
function Say($m) { if (-not $Quiet) { Write-Host $m } }
# keep the WSL VM alive (it stops when idle, and then the engine stops too)
$ka = Get-CimInstance Win32_Process -Filter "Name='wsl.exe'" | Where-Object { $_.CommandLine -match 'sleep infinity' }
if (-not $ka) { Start-Process wsl.exe -WindowStyle Hidden -ArgumentList "-d $d -u root -- sleep infinity" }
if ($mode -eq 'systemd') { wsl -d $d -u root -- systemctl start docker 2>$null | Out-Null }
else {
    $up = wsl -d $d -u root -- bash -c "pgrep -x dockerd"
    if (-not $up) { Start-Process wsl.exe -WindowStyle Hidden -ArgumentList "-d $d -u root -- dockerd -H tcp://0.0.0.0:2375 -H unix:///var/run/docker.sock" }
}
$ok = $false; $ip = ''
for ($i = 0; $i -lt 40 -and -not $ok; $i++) {
    $ip = ((wsl -d $d -- hostname -I) -replace "`0", '').Trim().Split(' ')[0]
    if ($ip) {
        $tcp = New-Object Net.Sockets.TcpClient
        $iar = $tcp.BeginConnect($ip, 2375, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(2000) -and $tcp.Connected
        $tcp.Close()
    }
    if (-not $ok) { Start-Sleep -Seconds 2 }
}
if ($ok) {
    $url = "tcp://${ip}:2375"
    $env:DOCKER_HOST = $url
    [Environment]::SetEnvironmentVariable('DOCKER_HOST', $url, 'User')
    Set-Content -Path "$EY\docker-host.txt" -Value $url -Encoding ASCII
    Say "Docker ready: $url"
} else {
    Remove-Item "$EY\docker-host.txt" -Force
    Say "Docker did not start. Run: powershell -ExecutionPolicy Bypass -File C:\EYLAB\ey-aidevops-labs\install-docker.ps1"
}
'@
Set-Content -Path "$EY\start-docker.ps1" -Value $start.Replace('__DISTRO__', $distro).Replace('__MODE__', $mode) -Encoding ASCII
# start at every logon of this user (registry Run key: works without admin); remove the older scheduled task if present
$runCmd = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\ProgramData\EYLAB\start-docker.ps1 -Quiet'
New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Force | Out-Null
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'LabDocker' -Value $runCmd
try { Unregister-ScheduledTask -TaskName 'LabDocker' -Confirm:$false -ErrorAction SilentlyContinue } catch {}
Good "start script: $EY\start-docker.ps1  (logon entry set)"

# ---------------------------------------------------------------- 5. start now
Say "5/6  Starting Docker now"
& "$EY\start-docker.ps1"
if (-not $env:DOCKER_HOST) { Stop-Here "the engine does not answer on the WSL address (port 2375). Mode was $mode." }

# ---------------------------------------------------------------- 6. self-test
Say "6/6  Self-test"
$sv = & docker version --format 'client={{.Client.Version}} server={{.Server.Version}} os={{.Server.Os}}' 2>&1
if ($LASTEXITCODE -ne 0) { Write-Host ($sv | Out-String); Stop-Here "'docker version' cannot reach the engine at $env:DOCKER_HOST" }
Good "docker version: $sv"
if ("$sv" -notmatch 'os=linux') { Stop-Here "engine is not a Linux engine" }
if (-not $SkipPull) {
    Say "pulling python:3.12-slim (about 1 minute)"
    docker pull python:3.12-slim | Select-Object -Last 2
}
$id = & docker run --rm --entrypoint id python:3.12-slim 2>&1
if ("$id" -notmatch 'uid=') { Stop-Here "docker run printed no output (got: '$id'). Output from containers is lost." }
Good "docker run output: $id"

Write-Host "`nDOCKER OK on this VM.  DOCKER_HOST=$env:DOCKER_HOST" -ForegroundColor Green
Write-Host "Open a NEW PowerShell window before using docker (this window already has it)." -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch {}
