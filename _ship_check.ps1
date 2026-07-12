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
    'quest_tracker_map_labels.lua',
    'quest_data_loader.lua',
    'quest_tracker_journal.lua',
    'quest_tracker_window_child.lua'
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
    $gatherLines = Get-Content -LiteralPath $gather
    $resolveLine = 0
    $getPosLine = 0
    for ($i = 0; $i -lt $gatherLines.Count; $i++) {
        if ($gatherLines[$i] -match 'local function resolve_teleport_pos') { $resolveLine = $i + 1 }
        if ($gatherLines[$i] -match 'local function get_character_world_pos') { $getPosLine = $i + 1 }
    }
    if ($resolveLine -gt 0 -and $getPosLine -gt 0 -and $resolveLine -lt $getPosLine) {
        Fail "gather.lua resolve_teleport_pos (L$resolveLine) before get_character_world_pos (L$getPosLine)"
    } elseif ($resolveLine -gt 0 -and $getPosLine -gt 0) {
        Ok "gather resolve_teleport_pos after get_character_world_pos"
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
    $mainRaw = Get-Content -LiteralPath $main -Raw
    if ($mainRaw -match 'function _teleport_player_to' -and $mainRaw -notmatch 'FerrystoneFlowController') {
        Fail 'quest_tracker.lua _teleport_player_to must use FerrystoneFlowController'
    } elseif ($mainRaw -match 'FerrystoneFlowController') {
        Ok 'ferrystone TP wired in quest_tracker.lua'
    }
    if ($mainRaw -match 'p\.x, p\.y, p\.z = x, y, z' -and $mainRaw -notmatch 'plupos_fallback') {
        Fail 'quest_tracker.lua still has raw UniversalPosition write as primary TP path'
    }
}

$flatOverlay = Join-Path $autorun 'quest_tracker_overlay.lua'
if (Test-Path -LiteralPath $flatOverlay) {
    Fail 'quest_tracker_overlay.lua must NOT be in flat autorun/ — use autorun/quest_tracker/'
}

$subOverlay = Join-Path $autorun 'quest_tracker\quest_tracker_overlay.lua'
if (-not (Test-Path -LiteralPath $subOverlay)) {
    Fail 'missing autorun/quest_tracker/quest_tracker_overlay.lua'
} else {
    Ok 'overlay in quest_tracker/ subfolder'
}

if (Test-Path -LiteralPath $main) {
    $mainLines = Get-Content -LiteralPath $main
    $ctxModLine = 0
    $overlayInstallLine = 0
    for ($i = 0; $i -lt $mainLines.Count; $i++) {
        if ($mainLines[$i] -match '^\s*ctx\.mod\s*=\s*mod\s*$') { $ctxModLine = $i + 1 }
        if ($mainLines[$i] -match 'Overlay\.install') { $overlayInstallLine = $i + 1 }
    }
    if ($overlayInstallLine -gt 0 -and $ctxModLine -gt 0 -and $overlayInstallLine -lt $ctxModLine) {
        Fail "Overlay.install (L$overlayInstallLine) before ctx.mod=mod (L$ctxModLine)"
    } elseif ($overlayInstallLine -gt 0 -and $ctxModLine -gt 0) {
        Ok 'overlay install after ctx.mod'
    }
    if (Test-Path -LiteralPath $subOverlay) {
        $subRaw = Get-Content -LiteralPath $subOverlay -Raw
        if ($subRaw -notmatch '\[QT\] overlay module') {
            Fail 'quest_tracker_overlay.lua missing boot log [QT] overlay module'
        } else {
            Ok 'overlay boot log string present'
        }
    }
}

$luac = $null
foreach ($c in @('luac', 'C:\Program Files\Lua\5.4\luac.exe', 'C:\Program Files (x86)\Lua\5.4\luac.exe')) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) { $luac = $cmd.Source; break }
    if (Test-Path -LiteralPath $c) { $luac = $c; break }
}
$luacFiles = @(
    'quest_tracker_sniff.lua',
    'quest_tracker_plugins.lua',
    'quest_tracker_prefs.lua',
    'quest_tracker_map.lua',
    'quest_tracker_map_labels.lua',
    'quest_tracker_window.lua',
    'quest_tracker_window_child.lua',
    'quest_tracker.lua'
)
if ($luac) {
    foreach ($lf in $luacFiles) {
        $lp = Join-Path $autorun $lf
        if (-not (Test-Path -LiteralPath $lp)) { continue }
        $out = & $luac -p $lp 2>&1
        if ($LASTEXITCODE -ne 0) { Fail "luac -p $lf : $out" }
        else { Ok "luac -p $lf" }
    }
} else {
    Write-Host "WARN luac not on PATH - syntax check skipped (install Lua 5.4, add luac to PATH)" -ForegroundColor Yellow
}

$wikiHints = Join-Path $root 'reframework\data\quest_tracker_wiki_hints.json'
if (Test-Path -LiteralPath $wikiHints) {
    $san = Join-Path $root 'tools\sanitize_wiki_hints.py'
    if (Test-Path -LiteralPath $san) {
        $sanOut = & python $san 2>&1
        if ($LASTEXITCODE -ne 0) { Fail "wiki hints paragraph gate: $sanOut" }
        else { Ok 'wiki hints paragraph gate (sanitize)' }
    }
    $merge = Join-Path $root 'tools\merge_quest_sources.py'
    if (Test-Path -LiteralPath $merge) {
        $mergeOut = & python $merge 2>&1
        Write-Host ($mergeOut | Out-String)
        if ($LASTEXITCODE -ne 0) { Fail "wiki step coverage gate (merge_quest_sources)" }
        else { Ok 'wiki step_order + step_hints coverage' }
    }
}

$resolveLua = Join-Path $autorun 'quest_tracker_steps_resolve.lua'
if (Test-Path -LiteralPath $resolveLua) {
    $resRaw = Get-Content -LiteralPath $resolveLua -Raw
    if ($resRaw -notmatch 'journal_open' -or $resRaw -notmatch '\[QT\]\[resolve\]') {
        Fail 'steps_resolve missing journal-first resolve path'
    } else {
        Ok 'journal-first resolve wired'
    }
}

$mapLua = Join-Path $autorun 'quest_tracker_map.lua'
if (Test-Path -LiteralPath $mapLua) {
    $mapRaw = Get-Content -LiteralPath $mapLua -Raw
    if ($mapRaw -notmatch 'overlay never blocked') {
        Fail 'map.lua missing overlay-never-blocked map_close'
    } elseif ($mapRaw -notmatch '_inject_done_for_gen' -or $mapRaw -notmatch 'add_labeled_markers_for_all_pins') {
        Fail 'map.lua missing diamond once-per-gen + labels every hook'
    } else {
        Ok 'map diamond once-per-gen + labels + overlay not blocked'
    }
}

$windowLua = Join-Path $autorun 'quest_tracker_window.lua'
if (Test-Path -LiteralPath $windowLua) {
    $winRaw = Get-Content -LiteralPath $windowLua -Raw
    if ($winRaw -match 're\.on_draw_ui[\s\S]{0,800}begin_window') {
        Fail 'quest_tracker_window.lua begin_window inside on_draw_ui (must be on_frame only)'
    } else {
        Ok 'begin_window not in on_draw_ui'
    }
    if ($winRaw -match 'Pin Ongoing' -and $winRaw -match 'pin_all_current') {
        Ok 'window Pin Ongoing button'
    } else {
        Fail 'quest_tracker_window.lua missing Pin Ongoing button'
    }
}
$mapLua = Join-Path $autorun 'quest_tracker_map.lua'
$labelsLua = Join-Path $autorun 'quest_tracker_map_labels.lua'
if (Test-Path -LiteralPath $mapLua) {
    $mapRaw = Get-Content -LiteralPath $mapLua -Raw
    if ($mapRaw -match 'QuestTargetMarkerList[\s\S]{0,200}RemoveAt' -or $mapRaw -match '_wipe_injected_diamonds') {
        Fail 'quest_tracker_map.lua blind QuestTargetMarkerList RemoveAt banned'
    } else {
        Ok 'map no blind marker-list wipe'
    }
    if ($mapRaw -match '_inject_done_for_gen\[gen\] = true') {
        Ok 'map diamond inject once per gen'
    } else {
        Fail 'quest_tracker_map.lua missing _inject_done_for_gen once-per-gen'
    }
    if ($mapRaw -match 'MAIN label-only fallback to normal pin') {
        Fail 'quest_tracker_map.lua MAIN npc fallback banned (Test1 dual diamond)'
    } elseif ($mapRaw -match 'journal-label-deferred' -or $mapRaw -match 'MAIN label-only deferred') {
        Ok 'map MAIN label-only defer (no npc fallback)'
    } else {
        Fail 'quest_tracker_map.lua missing MAIN label-only defer'
    }
    if ($mapRaw -match 'clear_restore_MAIN' -or $mapRaw -match 'Always restore MAIN name banner') {
        Ok 'map Clear restores MAIN label'
    } else {
        Fail 'quest_tracker_map.lua missing Clear MAIN restore'
    }
    if ($mapRaw -match 'y = p\.y, p\.z,' ) {
        Fail 'quest_tracker_map.lua manual pinned_pos missing z= key (z=0 dupe bug)'
    } else {
        Ok 'map manual pinned_pos has z= key'
    }
    if ($mapRaw -match 'not_acceptable' -and $mapRaw -match 'acceptable_ids') {
        Ok 'map Pin Available gates on acceptable_ids'
    } else {
        Fail 'quest_tracker_map.lua Pin Available missing acceptable_ids gate'
    }
    if ($mapRaw -match 'map_force_MAIN_label' -or $mapRaw -match 'hyp=H10') {
        Ok 'map force MAIN label on setupMapIcon'
    } else {
        Fail 'quest_tracker_map.lua missing map_force_MAIN_label (Test1)'
    }
    if ($mapRaw -match 'main_upcoming' -and $mapRaw -match 'upcoming_ids') {
        Ok 'map Pin Available upcoming sides + skip main_upcoming'
    } else {
        Fail 'quest_tracker_map.lua missing upcoming side pin path'
    }
    if ($mapRaw -match 'pin_all_current' -and $mapRaw -match 'Pin Ongoing force unpin all Ongoing') {
        Ok 'map Pin Ongoing / pin_all_current force_repin Ongoing'
    } else {
        Fail 'quest_tracker_map.lua missing pin_all_current / Ongoing force_repin'
    }
}
if (Test-Path -LiteralPath $labelsLua) {
    $labelsRaw = Get-Content -LiteralPath $labelsLua -Raw
    if ($labelsRaw -match 'QuestNameId' -and ($labelsRaw -match 'call6_false' -or $labelsRaw -match 'name_guid,\s*false')) {
        Ok 'map label TU6 call6_false / QuestNameId'
    } else {
        Fail 'quest_tracker_map_labels.lua missing TU6 call6_false / QuestNameId'
    }
    if ($labelsRaw -match 'Never scan "Message' -or $labelsRaw -match 'not fn:find\("Message"') {
        Ok 'map label Guid scan excludes Message fields'
    } elseif ($labelsRaw -match 'or fn:find\("Message"' -or $labelsRaw -match "or fn:find\('Message'") {
        Fail 'quest_tracker_map_labels.lua Message Guid scan banned (wrong banners)'
    } else {
        Ok 'map label Guid scan excludes Message fields'
    }
    if ($labelsRaw -match 'addMapIconInfoList", info, 0,' -or $labelsRaw -match "addMapIconInfoList', info, 0,") {
        Ok 'map label Vanilla addMapIconInfoList p2=0'
    } else {
        Fail 'quest_tracker_map_labels.lua missing Vanilla addMapIconInfoList call'
    }
    # Invent / regression paths REJECTED
    $inventHit = $false
    if ($labelsRaw -match '(?m)^\s*info\.UniqId\s*=' -or $labelsRaw -match 'LABEL_ICON_COLOR\s*=' -or $labelsRaw -match ':set_Color\(' -or $labelsRaw -match 'path = "vanilla5"' -or $labelsRaw -match "path = 'vanilla5'") {
        $inventHit = $true
    }
    # 5-arg-only call (no trailing false) is banned on current TU
    if ($labelsRaw -match 'addMapIconInfoList", info, 0, idx_obj:get_address\(\) \+ INT_T_VOFF, -1, name_guid\)' -and $labelsRaw -notmatch 'name_guid,\s*false') {
        $inventHit = $true
    }
    if ($labelsRaw -match 'this:call\("updateMapIcon"\)') {
        Fail 'quest_tracker_map_labels.lua per-add updateMapIcon banned'
    } else {
        Ok 'map label no per-add updateMapIcon'
    }
    if ($inventHit) {
        Fail 'quest_tracker_map_labels.lua invent/5-arg path banned'
    } else {
        Ok 'map label no invent (UniqId/color/vanilla5)'
    }
    if ($labelsRaw -match 'label skip out_of_range' -and $labelsRaw -match 'return nil') {
        if ($labelsRaw -match 'label oor note') {
            Ok 'map label OOR log-only (no hard skip)'
        } else {
            Fail 'quest_tracker_map_labels.lua hard OOR skip banned (Hugo detail)'
        }
    } else {
        Ok 'map label no hard OOR skip'
    }
} else {
    Fail 'missing quest_tracker_map_labels.lua'
}

$tiersJson = Join-Path $root 'reframework\data\quest_tracker_quest_tiers.json'
if (Test-Path -LiteralPath $tiersJson) {
    try {
        Get-Content -LiteralPath $tiersJson -Raw | ConvertFrom-Json | Out-Null
        Ok 'quest_tracker_quest_tiers.json parse'
    } catch {
        Fail "quest_tracker_quest_tiers.json invalid JSON: $_"
    }
}

$dataJson = Join-Path $root 'reframework\data\quest_tracker_data.json'
if (-not (Test-Path -LiteralPath $dataJson)) {
    Fail 'missing reframework/data/quest_tracker_data.json'
} else {
    try {
        $dj = Get-Content -LiteralPath $dataJson -Raw | ConvertFrom-Json
        $qc = 0
        if ($dj.quests) { $qc = @($dj.quests.PSObject.Properties).Count }
        if ($qc -lt 50) { Fail "quest_tracker_data.json quests=$qc (need >=50)" }
        else { Ok "quest_tracker_data.json quests=$qc" }
    } catch {
        Fail "quest_tracker_data.json invalid JSON: $_"
    }
}

$guidanceVal = Join-Path $root 'tools\_validate_guidance_data.py'
if (Test-Path -LiteralPath $guidanceVal) {
    $gvOut = & python $guidanceVal 2>&1
    Write-Host ($gvOut | Out-String)
    if ($LASTEXITCODE -ne 0) { Fail "guidance full-catalog gate: $gvOut" }
    else { Ok 'guidance full-catalog coverage gate' }
}

$resolverCorpus = Join-Path $root 'tools\_test_resolver_corpus.py'
if (Test-Path -LiteralPath $resolverCorpus) {
    $rcOut = & python $resolverCorpus 2>&1
    Write-Host ($rcOut | Out-String)
    if ($LASTEXITCODE -ne 0) { Fail "resolver corpus gate: $rcOut" }
    else { Ok 'offline resolver corpus gate' }
}

$manifestPath = Join-Path $root 'tools\data\quest_catalog_manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Fail 'missing tools/data/quest_catalog_manifest.json'
} else {
    try {
        $man = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ([int]$man.catalog_records -ne 85) { Fail "catalog_records=$($man.catalog_records) (need 85)" }
        else { Ok "quest catalog manifest records=$($man.catalog_records) playable=$($man.playable_records)" }
    } catch {
        Fail "quest_catalog_manifest.json invalid JSON: $_"
    }
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
