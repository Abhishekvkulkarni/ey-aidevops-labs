# sync.ps1  -  run from your repo folder:   .\sync.ps1
# Brings the trainer's newest pages and scripts into your folder. NO merge, so it never stops on your own changes.
# Your own work in api/ and helm/ is not touched. Nothing is pushed to GitHub (you only push when a lab says so).
#
# If your copy of this script is the old one and fails, get the new one first (one line, from the repo folder):
#   irm https://raw.githubusercontent.com/askanilkumar/ey-aidevops-labs/main/sync.ps1 -OutFile sync.ps1; .\sync.ps1
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Set-Location $here
$upstreamUrl = 'https://github.com/askanilkumar/ey-aidevops-labs.git'

function Fail($m) { Write-Host "`n$m" -ForegroundColor Red; exit 1 }
git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "This is not the repo folder. Run:  cd C:\EYLAB\ey-aidevops-labs   then  .\sync.ps1" }

# 1. make sure the trainer's repo is registered as 'upstream' (forks do not have it)
$remotes = @(git remote)
if ($remotes -contains 'upstream') { git remote set-url upstream $upstreamUrl } else { git remote add upstream $upstreamUrl; Write-Host "Added remote 'upstream'." }

# 2. download the trainer's latest (read-only)
git fetch upstream main --quiet
if ($LASTEXITCODE -ne 0) { Fail "Could not reach GitHub. Check the VM's internet and run .\sync.ps1 again." }

# 3. copy the trainer-owned files over yours. No merge. api/ and helm/ are yours and are never overwritten.
$paths = @('day1', 'day2', 'day3', 'day4', 'lab-requirements.txt', 'lab-env.ps1', 'preflight.ps1', 'install-docker.ps1', '.gitignore', 'sync.ps1')
$got = @()
foreach ($p in $paths) {
    git cat-file -e "upstream/main:$p" 2>$null
    if ($LASTEXITCODE -eq 0) { git checkout upstream/main -- $p 2>$null; if ($LASTEXITCODE -eq 0) { $got += $p } }
}
git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    $u = if ($env:USERNAME) { $env:USERNAME } else { 'lab' }
    git -c user.name="$u" -c user.email="$u@lab.local" commit -q -m "sync trainer files"
    if ($LASTEXITCODE -ne 0) { Fail "Could not save the synced files. Tell the trainer (message above)." }
    Write-Host "Updated: $($got -join ', ')" -ForegroundColor Green
} else { Write-Host "Already up to date." -ForegroundColor Green }

# 4. repair helm/values.yaml if it still has the placeholder (uses the registry name from your lab card)
$vals = Join-Path $here 'helm\values.yaml'
if (Test-Path $vals) {
    $txt = [IO.File]::ReadAllText($vals)
    if ($txt -match 'REPLACE_WITH_SHARED_ACR') {
        $acr = 'eylabacr31b021.azurecr.io'
        try { $c = Get-Content 'C:\EYLAB\lab-card.json' -Raw | ConvertFrom-Json; if ($c.acr_login_server) { $acr = $c.acr_login_server } } catch {}
        $txt = [regex]::Replace($txt, 'REPLACE_WITH_SHARED_ACR(\.azurecr\.io)?', $acr)
        [IO.File]::WriteAllText($vals, $txt, (New-Object Text.UTF8Encoding $false))
        Write-Host "Fixed the registry name in helm/values.yaml ($acr)." -ForegroundColor Green
    }
}

# 5. say what is available
$days = Get-ChildItem -Directory -Filter 'day*' | Where-Object { Test-Path (Join-Path $_.FullName 'content\index.html') } | ForEach-Object Name
Write-Host "`nSynced. Open in VS Code:  C:\EYLAB\ey-aidevops-labs   (always the repo ROOT, never a sub-folder)" -ForegroundColor Green
Write-Host "Pages available: $($days -join ', ')   (open dayN\content\index.html)"
Write-Host "`nChecking your machine (Day 2)..." -ForegroundColor Cyan
& (Join-Path $here 'preflight.ps1') -Day 2
