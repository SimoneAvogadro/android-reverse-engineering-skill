# asc-query.ps1 — Rapid on-demand queries using ASC (Android Source Code)
# Allows instant class decompilation, manifest decoding, and xref searches
# without unpacking or pre-indexing the full APK.
param(
    [Parameter(Position=0)]
    [string]$ApkFile,
    [Parameter(Position=1)]
    [string]$Subcommand,
    [Alias('h')]
    [switch]$Help,
    [Parameter(Position=2, ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    Write-Host @"
Usage: asc-query.ps1 <apk_file> <subcommand> [args...]

Subcommands:
  getclass <class_name> [-o output.java]
      Locate and decompile a single class in ~180ms.
      Example: .\asc-query.ps1 app.apk getclass com.example.MainActivity

  findrefs <string|type|method|field|extends|impl> <target> [-o output.txt]
      Find cross-references across all DEX entries in seconds.
      Example: .\asc-query.ps1 app.apk findrefs string "https://api"
      Example: .\asc-query.ps1 app.apk findrefs extends androidx.lifecycle.ViewModel

  listclass [--prefix <prefix>] [-o output.txt]
      List class descriptors across all DEX entries.
      Example: .\asc-query.ps1 app.apk listclass --prefix com.example

  getmanifest [-o AndroidManifest.xml]
      Extract and decode AndroidManifest.xml directly from the APK.
      Example: .\asc-query.ps1 app.apk getmanifest
"@
    exit 0
}

if ($Help -or -not $ApkFile -or -not $Subcommand -or $ApkFile -eq '-h' -or $ApkFile -eq '--help') {
    Show-Usage
}

if (-not (Test-Path $ApkFile)) {
    Write-Host "Error: File not found: $ApkFile" -ForegroundColor Red
    exit 1
}

$apkAbs = (Resolve-Path $ApkFile).Path

# Locate ASC tool
function Find-Asc {
    $cmd = Get-Command droidasc -ErrorAction SilentlyContinue
    if ($cmd) { return 'droidasc' }
    $cmd = Get-Command rust_ASC -ErrorAction SilentlyContinue
    if ($cmd) { return 'rust_ASC' }
    $cmd = Get-Command rust_ASC.exe -ErrorAction SilentlyContinue
    if ($cmd) { return 'rust_ASC.exe' }
    try {
        $pyHelp = & python -m droidasc --help 2>&1 | Select-Object -First 1
        if ($pyHelp -match 'ASC|droidasc') { return 'python -m droidasc' }
    } catch {}
    return $null
}

$ascCmd = Find-Asc
if (-not $ascCmd) {
    Write-Host "Error: ASC decompiler is not installed." -ForegroundColor Red
    Write-Host "Install via: pip install droidasc or run .\install-dep.ps1 asc" -ForegroundColor Yellow
    exit 1
}

$validSubs = @('getclass', 'listclass', 'getmanifest', 'findrefs')
if ($Subcommand -notin $validSubs) {
    Write-Host "Error: Unknown subcommand '$Subcommand'. Valid subcommands: $($validSubs -join ', ')" -ForegroundColor Red
    Show-Usage
}

$fullArgs = @($Subcommand, $apkAbs)
if ($RemainingArgs) {
    $fullArgs += $RemainingArgs
}

if ($ascCmd -eq 'python -m droidasc') {
    & python -m droidasc @fullArgs
} else {
    & $ascCmd @fullArgs
}
