# lookup-name.ps1: Query the mapping produced by recover-kotlin-names.ps1
param(
    [Parameter(Position = 0)]
    [string]$MappingDir,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$QueryArgs,
    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    Write-Host @"
Usage: lookup-name.ps1 <mapping-dir> <query>
       lookup-name.ps1 <mapping-dir> -o <obf-fqn>
       lookup-name.ps1 <mapping-dir> -p <real-package-substring>
       lookup-name.ps1 <mapping-dir> --grep <regex> <sources-dir>
"@
    exit 0
}

if ($Help) { Show-Usage }
if (-not $MappingDir -or $QueryArgs.Count -eq 0) { Show-Usage }

$mapFile = Join-Path $MappingDir 'mapping.json'
if (-not (Test-Path $mapFile)) {
    Write-Host "no mapping.json in $MappingDir" -ForegroundColor Red
    exit 1
}

$pyScript = Join-Path $PSScriptRoot 'lookup_names.py'
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }

$allArgs = @($MappingDir) + $QueryArgs
if ($py -and $py.Name -eq 'python') {
    & python $pyScript @allArgs
} elseif ($py) {
    & py -3 $pyScript @allArgs
} else {
    Write-Host "Error: python not found. Install Python 3." -ForegroundColor Red
    exit 1
}
