# One-time: link this folder to GitHub and push main.
# Run from repo root in PowerShell:
#   powershell -ExecutionPolicy Bypass -File _push_to_github.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$git  = Join-Path $root ".tools\mingit\cmd\git.exe"
$gh   = Join-Path $root ".tools\gh\bin\gh.exe"

if (-not (Test-Path $git)) { throw "Missing $git — re-run setup or install Git for Windows." }
if (-not (Test-Path $gh))  { throw "Missing $gh — re-run setup or install GitHub CLI." }

Set-Location $root

$auth = & $gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "GitHub CLI not logged in. A browser window will open — finish login there."
    & $gh auth login -h github.com -p https -w
}

$repoName = "QuestTracker-Modded"
Write-Host "Creating GitHub repo '$repoName' (private) and pushing main..."
& $gh repo create $repoName --private --source=. --remote=origin --push
Write-Host "Done. Remote:"
& $git remote -v
