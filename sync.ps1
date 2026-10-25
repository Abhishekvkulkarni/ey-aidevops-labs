# Run each morning from the repo folder:   .\sync.ps1
# Brings the new day's pages from the trainer's repo into your fork. Your own work is kept.
git checkout main
if ($LASTEXITCODE -ne 0) { Write-Host "Could not switch to main. Commit or stash your changes first." -ForegroundColor Red; exit 1 }
git fetch upstream
git pull upstream main --no-rebase --no-edit
if ($LASTEXITCODE -ne 0) { Write-Host "Merge stopped. Tell the trainer." -ForegroundColor Red; exit 1 }
git push origin main
Write-Host "`nSynced. Open the new day's folder, for example day2\index.html" -ForegroundColor Green
