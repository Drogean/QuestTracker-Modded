# One-time: link this folder to GitHub and push main (PUBLIC repo).
# Run from repo root in PowerShell:
#   powershell -ExecutionPolicy Bypass -File _push_to_github.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$mingitRoot = Join-Path $root ".tools\mingit"
$git  = Join-Path $mingitRoot "cmd\git.exe"
$gh   = Join-Path $root ".tools\gh\bin\gh.exe"
$env:GH_CONFIG_DIR = Join-Path $env:USERPROFILE ".config\gh"
$env:PATH = "$(Join-Path $mingitRoot 'cmd');$(Join-Path $mingitRoot 'usr\bin');$env:PATH"
New-Item -ItemType Directory -Force -Path $env:GH_CONFIG_DIR | Out-Null

if (-not (Test-Path $git)) { throw "Missing $git - re-run setup or install Git for Windows." }
if (-not (Test-Path $gh))  { throw "Missing $gh - re-run setup or install GitHub CLI." }

Set-Location $root

$prevEap = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
& $gh auth status *> $null
$needLogin = $LASTEXITCODE -ne 0
$ErrorActionPreference = $prevEap

if ($needLogin) {
    Write-Host "GitHub CLI not logged in. A browser window will open - finish login there."
    & $gh auth login -h github.com -p https -w
}

$repoName = "QuestTracker-Modded"
$hasRemote = $false
& $git remote get-url origin *> $null
if ($LASTEXITCODE -eq 0) { $hasRemote = $true }

if ($hasRemote) {
    Write-Host "Pushing main to existing origin..."
    & $git push -u origin main
} else {
    Write-Host "Creating GitHub repo '$repoName' (public) and pushing main..."
    & $gh repo create $repoName --public --source=. --remote=origin --push
}

Write-Host "Done. Remote:"
& $git remote -v
