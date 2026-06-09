# Build a Fluffy-ready zip: ONLY modinfo.ini + reframework/ (no dev junk).
# Run from repo root:
#   powershell -ExecutionPolicy Bypass -File _build_fluffy_zip.ps1
#
# Output: ../OTHERMODS/QuestTracker-Reduxx-vVERSION-fluffy.zip
# Install that zip in Fluffy Mod Manager (not the whole repo folder).

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$modinfo = Join-Path $root "modinfo.ini"
if (-not (Test-Path $modinfo)) { throw "Missing modinfo.ini" }

$version = "0.0.0"
foreach ($line in Get-Content -LiteralPath $modinfo) {
    if ($line -match '^\s*version\s*=\s*(.+)\s*$') {
        $version = $Matches[1].Trim()
        break
    }
}

$outDir = (Resolve-Path (Join-Path $root "..")).Path
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$staging = Join-Path $env:TEMP ("qt-fluffy-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Force -Path $staging | Out-Null

try {
    Copy-Item -LiteralPath $modinfo -Destination (Join-Path $staging "modinfo.ini")

    $srcRef = Join-Path $root "reframework"
    $dstRef = Join-Path $staging "reframework"
    New-Item -ItemType Directory -Force -Path $dstRef | Out-Null

    foreach ($sub in @("autorun", "data", "fonts")) {
        $src = Join-Path $srcRef $sub
        if (-not (Test-Path $src)) { continue }
        $dst = Join-Path $dstRef $sub
        New-Item -ItemType Directory -Force -Path $dst | Out-Null
        Get-ChildItem -LiteralPath $src -File -Recurse | Where-Object {
            $_.Extension -ne ".bak"
        } | ForEach-Object {
            $rel = $_.FullName.Substring($src.Length).TrimStart('\')
            $target = Join-Path $dst $rel
            $targetDir = Split-Path -Parent $target
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
            }
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        }
    }

    $zipName = "QuestTracker-Reduxx-v$version-fluffy.zip"
    $zipPath = Join-Path $outDir $zipName
    if (Test-Path $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $zipPath)

    $count = (Get-ChildItem -LiteralPath $staging -Recurse -File).Count
    Write-Host "Built $zipPath"
    Write-Host "Files in zip: $count (modinfo.ini + reframework only)"
    Write-Host "Fluffy: Install $zipName from OTHERMODS folder"
}
finally {
    if (Test-Path $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
}
