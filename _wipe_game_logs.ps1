# Truncate game logs after a builder ship (never delete files).
# Run from repo root: powershell -File _wipe_game_logs.ps1 [-Version 3.0.80]

param(
    [string]$Version = "unknown"
)

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

$paths = @(
    'C:\Program Files (x86)\Steam\steamapps\common\Dragons Dogma 2\reframework\data\quest_tracker_log.txt',
    'C:\Program Files (x86)\Steam\steamapps\common\Dragons Dogma 2\re2_framework_log.txt',
    'C:\Program Files (x86)\Steam\steamapps\common\Dragons Dogma 2\MM\Data\Log.txt'
)

foreach ($p in $paths) {
    $header = "-- wiped by Quest Tracker builder ship v$Version $stamp`n"
    try {
        if (Test-Path -LiteralPath $p) {
            [System.IO.File]::WriteAllText($p, $header, [System.Text.UTF8Encoding]::new($false))
            Write-Host "wiped: $p"
        } else {
            $dir = Split-Path -Parent $p
            if (-not (Test-Path -LiteralPath $dir)) {
                Write-Host "skip (dir missing): $p"
            } else {
                [System.IO.File]::WriteAllText($p, $header, [System.Text.UTF8Encoding]::new($false))
                Write-Host "created empty: $p"
            }
        }
    } catch {
        Write-Host "FAILED: $p - $($_.Exception.Message)"
    }
}
