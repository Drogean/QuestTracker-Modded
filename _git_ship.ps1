# Commit + push + tag every shipped version (rollback points on GitHub).
# Run after _ship_check.ps1 passes:
#   powershell -NoProfile -ExecutionPolicy Bypass -File "_git_ship.ps1" -Version 1.1.6

param(
    [Parameter(Mandatory = $false)]
    [string]$Version
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$mingitRoot = Join-Path $root ".tools\mingit"
$git = Join-Path $mingitRoot "cmd\git.exe"
$env:PATH = "$(Join-Path $mingitRoot 'cmd');$(Join-Path $mingitRoot 'usr\bin');$env:PATH"

if (-not (Test-Path $git)) {
    Write-Error "Missing $git - run _push_to_github.ps1 once to bootstrap mingit."
}

Set-Location $root

function Ensure-GitIdentity {
    & $git config user.email 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return }
    $url = (& $git remote get-url origin 2>$null)
    $name = "QuestTracker-Modded"
    if ($url -match 'github\.com[:/]([^/]+)/') { $name = $Matches[1] }
    $email = "$name@users.noreply.github.com"
    $env:GIT_AUTHOR_NAME = $name
    $env:GIT_COMMITTER_NAME = $name
    $env:GIT_AUTHOR_EMAIL = $email
    $env:GIT_COMMITTER_EMAIL = $email
    Write-Host "Using ship identity: $name ($email)"
}

if (-not $Version) {
    $lua = Join-Path $root "reframework\autorun\quest_tracker.lua"
    foreach ($line in Get-Content $lua -ErrorAction Stop) {
        if ($line -match 'MOD_VERSION = "(.+)"') { $Version = $Matches[1]; break }
    }
}
if (-not $Version) { throw "Could not read MOD_VERSION - pass -Version X.Y.Z" }

$desc = ""
$ini = Join-Path $root "modinfo.ini"
if (Test-Path $ini) {
    foreach ($line in Get-Content $ini) {
        if ($line -match '(?i)^description\s*=\s*(.+)') { $desc = $Matches[1].Trim(); break }
    }
}

if (-not (Test-Path (Join-Path $root ".git"))) {
    Write-Host "No .git repo - initializing..."
    & $git init
    & $git branch -M main
}

$remoteOk = $false
& $git remote get-url origin 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $remoteOk = $true }

if (-not $remoteOk) {
    Write-Warning "No origin remote - run _push_to_github.ps1 once, then re-run _git_ship.ps1"
    exit 1
}

& $git fetch origin
Ensure-GitIdentity

& $git add -A
$status = & $git status --porcelain
if ($status) {
    $msg = "ship v$Version"
    if ($desc) { $msg = "$msg`: $desc" }
    & $git commit -m $msg
    if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
    Write-Host "Committed: $msg"
} else {
    Write-Host "Nothing new to commit (working tree clean)."
}

& $git pull --rebase origin main
if ($LASTEXITCODE -ne 0) { throw "git pull --rebase failed (resolve conflicts, then re-run)" }

& $git push -u origin main
if ($LASTEXITCODE -ne 0) { throw "git push failed" }

$tag = "v$Version"
& $git tag -a $tag -m "Quest Tracker Reduxx $tag" -f
& $git push origin $tag -f
if ($LASTEXITCODE -ne 0) { throw "git push tag failed" }

$hash = (& $git rev-parse --short HEAD).Trim()
Write-Host ('OK   GitHub: main ' + $hash + ' tag=' + $tag)
