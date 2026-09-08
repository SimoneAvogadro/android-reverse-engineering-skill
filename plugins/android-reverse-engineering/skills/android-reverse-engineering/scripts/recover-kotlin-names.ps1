# recover-kotlin-names.ps1: Rebuild obfuscated -> real Kotlin class-name map
param(
    [Parameter(Position = 0)]
    [string]$SourceDir,
    [Parameter(Position = 1)]
    [string]$OutputDir,
    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    Write-Host @"
Usage: recover-kotlin-names.ps1 <decompiled-sources-dir> [output-dir]

Walks every *.java under <decompiled-sources-dir>, mines @DebugMetadata
and @Metadata annotations, and writes mapping.tsv, mapping.json, by_package/.
"@
    exit 0
}

if ($Help) { Show-Usage }
if (-not $SourceDir) { Show-Usage }
if (-not (Test-Path $SourceDir -PathType Container)) {
    Write-Host "not a directory: $SourceDir" -ForegroundColor Red
    exit 1
}

$pyScript = Join-Path $PSScriptRoot 'recover_kotlin_names.py'
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }

if ($py -and $py.Name -eq 'python') {
    if ($OutputDir) { & python $pyScript $SourceDir $OutputDir } else { & python $pyScript $SourceDir }
} elseif ($py) {
    if ($OutputDir) { & py -3 $pyScript $SourceDir $OutputDir } else { & py -3 $pyScript $SourceDir }
} else {
    Write-Host "Error: python not found. Install Python 3." -ForegroundColor Red
    exit 1
}
