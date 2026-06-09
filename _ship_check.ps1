# Run before telling user to install in Fluffy. Fails fast on known ship blockers.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$autorun = Join-Path $root 'reframework\autorun'
$main = Join-Path $autorun 'quest_tracker.lua'
$modinfo = Join-Path $root 'modinfo.ini'
$LOCAL_MAX = 180
$fail = 0

function Fail($msg) { Write-Host "FAIL $msg" -ForegroundColor Red; $script:fail++ }
function Ok($msg)   { Write-Host "OK   $msg" -ForegroundColor Green }

$required = @(
    'quest_tracker.lua',
    'quest_tracker_steps.lua',
    'quest_tracker_steps_resolve.lua',
    'quest_tracker_prefs.lua',
    'quest_tracker_sdk.lua',
    'quest_tracker_gather.lua',
    'quest_tracker_cache.lua',
    'quest_tracker_autolock.lua',
    'quest_tracker_map.lua',
    'quest_data_loader.lua',
    'quest_tracker_journal.lua'
)
foreach ($f in $required) {
    $p = Join-Path $autorun $f
    if (Test-Path -LiteralPath $p) { Ok $f } else { Fail "missing $f" }
}

if (Test-Path -LiteralPath $main) {
    $locals = @(Select-String -LiteralPath $main -Pattern '^local ').Count
    if ($locals -gt $LOCAL_MAX) { Fail "quest_tracker.lua locals=$locals max=$LOCAL_MAX split before ship" }
    else { Ok "locals $locals / $LOCAL_MAX" }
}

$gather = Join-Path $autorun 'quest_tracker_gather.lua'
if (Test-Path -LiteralPath $gather) {
    $has_local = @(Select-String -LiteralPath $gather -Pattern 'local dump_quest_id_enum = ctx\.dump_quest_id_enum').Count -gt 0
    if (-not $has_local) {
        Fail 'gather.lua missing: local dump_quest_id_enum = ctx.dump_quest_id_enum'
    } else {
        Ok 'gather dump_quest_id_enum wired via local'
    }
}

if ((Test-Path -LiteralPath $main) -and (Test-Path -LiteralPath $modinfo)) {
    $ver = $null
    $iniVer = $null
    foreach ($line in Get-Content -LiteralPath $main) {
        if ($line -match 'MOD_VERSION = "(.+)"') { $ver = $Matches[1]; break }
    }
    foreach ($line in Get-Content -LiteralPath $modinfo) {
        if ($line -match '(?i)^version\s*=\s*(\S+)') { $iniVer = $Matches[1]; break }
    }
    if ($ver -and $iniVer -and ($ver -eq $iniVer)) { Ok "version $ver" }
    else { Fail "version mismatch lua=$ver ini=$iniVer" }
}

if ($fail -gt 0) {
    Write-Host ""
    Write-Host "DO NOT SHIP - $fail failure(s)" -ForegroundColor Red
    exit 1
}
$zipScript = Join-Path $root '_build_fluffy_zip.ps1'
if (-not (Test-Path -LiteralPath $zipScript)) {
    Fail 'missing _build_fluffy_zip.ps1'
    Write-Host ""
    Write-Host "DO NOT SHIP - $fail failure(s)" -ForegroundColor Red
    exit 1
}
try {
    $zipOut = & $zipScript 2>&1
    $zipLine = $zipOut | Where-Object { $_ -match '^Built ' } | Select-Object -First 1
    if ($zipLine) { Ok ($zipLine -replace '^Built ', 'fluffy zip ') }
    else { Ok 'fluffy zip built in OTHERMODS/' }
} catch {
    Fail "fluffy zip: $_"
    Write-Host ""
    Write-Host "DO NOT SHIP - $fail failure(s)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Ship check passed. Install OTHERMODS\*-fluffy.zip in Fluffy." -ForegroundColor Green
exit 0
