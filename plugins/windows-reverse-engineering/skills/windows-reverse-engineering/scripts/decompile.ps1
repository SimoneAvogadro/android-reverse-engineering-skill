# decompile.ps1 — Decompile Windows EXE/DLL/.NET assemblies using Ghidra or ILSpy
#
# Usage: decompile.ps1 [OPTIONS] <file>
#
# Options:
#   -Output <dir>     Output directory (default: <filename>-decompiled)
#   -Engine <engine>  Decompiler engine: auto, ghidra, ilspy (default: auto)
#   -NoStrings        Skip strings extraction (faster)
#   -Help             Show help message

param(
    [Parameter(Position=0)]
    [string]$InputFile,

    [Alias('o')]
    [string]$Output = "",

    [ValidateSet('auto', 'ghidra', 'ilspy')]
    [string]$Engine = "auto",

    [switch]$NoStrings,

    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Show-Usage {
    @"
Usage: decompile.ps1 [OPTIONS] <file>

Decompile a Windows EXE, DLL, or .NET assembly.

Arguments:
  <file>              Path to the .exe, .dll, or .sys file

Options:
  -Output <dir>       Output directory (default: <filename>-decompiled)
  -Engine <engine>    Decompiler engine: auto, ghidra, ilspy (default: auto)
  -NoStrings          Skip strings extraction (faster)
  -Help               Show this help message

Engines:
  auto        Auto-detect binary type and choose the best engine (default)
  ghidra      Use Ghidra headless analyzer (native C/C++ binaries)
  ilspy       Use ilspycmd (for .NET assemblies)

Environment:
  GHIDRA_INSTALL_DIR  Path to Ghidra installation directory

Examples:
  decompile.ps1 MyApp.exe
  decompile.ps1 -Engine ilspy MyDotNetApp.dll
  decompile.ps1 -Engine ghidra -Output .\analysis NativeApp.exe
  decompile.ps1 -NoStrings LargeApp.dll
"@
    exit 0
}

if ($Help) { Show-Usage }

# --- Validate input ---
if (-not $InputFile) {
    Write-Host "Error: No input file specified." -ForegroundColor Red
    Show-Usage
}

if (-not (Test-Path $InputFile)) {
    Write-Host "Error: File not found: $InputFile" -ForegroundColor Red
    exit 1
}

$InputFileItem = Get-Item $InputFile
$InputFileAbs = $InputFileItem.FullName
$ext = $InputFileItem.Extension.ToLower()
$basename = $InputFileItem.BaseName

if ($ext -notin @('.exe', '.dll', '.sys')) {
    Write-Host "Error: Unsupported file type '$ext'. Expected .exe, .dll, or .sys" -ForegroundColor Red
    exit 1
}

if (-not $Output) {
    $Output = Join-Path (Split-Path $InputFileAbs -Parent) "${basename}-decompiled"
}

# --- Detect binary type ---
function Test-DotNetAssembly {
    param([string]$FilePath)

    try {
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)

        # Check MZ header
        if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
            return $false
        }

        # Get PE header offset from 0x3C
        $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
        if ($peOffset -le 0 -or ($peOffset + 4) -ge $bytes.Length) {
            return $false
        }

        # Check PE signature
        if ($bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset+1] -ne 0x45 -or
            $bytes[$peOffset+2] -ne 0x00 -or $bytes[$peOffset+3] -ne 0x00) {
            return $false
        }

        # COFF header starts at peOffset + 4
        $coffOffset = $peOffset + 4
        $sizeOfOptionalHeader = [BitConverter]::ToUInt16($bytes, $coffOffset + 16)

        if ($sizeOfOptionalHeader -eq 0) {
            return $false
        }

        # Optional header starts after COFF header (20 bytes)
        $optOffset = $coffOffset + 20
        $magic = [BitConverter]::ToUInt16($bytes, $optOffset)

        # PE32 (0x10B) or PE32+ (0x20B)
        if ($magic -eq 0x10B) {
            # PE32: CLI header is data directory index 14, at offset 208 from optional header start
            $cliDirOffset = $optOffset + 208
        } elseif ($magic -eq 0x20B) {
            # PE32+: CLI header is data directory index 14, at offset 224 from optional header start
            $cliDirOffset = $optOffset + 224
        } else {
            return $false
        }

        if (($cliDirOffset + 8) -gt $bytes.Length) {
            return $false
        }

        # Check if CLR header data directory has a non-zero RVA and size
        $cliRva = [BitConverter]::ToUInt32($bytes, $cliDirOffset)
        $cliSize = [BitConverter]::ToUInt32($bytes, $cliDirOffset + 4)

        return ($cliRva -gt 0 -and $cliSize -gt 0)
    } catch {
        return $false
    }
}

function Get-PeInfo {
    param([string]$FilePath)

    $info = @{
        Architecture = "unknown"
        Subsystem = "unknown"
        IsDotNet = $false
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
        $coffOffset = $peOffset + 4

        # Machine type
        $machine = [BitConverter]::ToUInt16($bytes, $coffOffset)
        switch ($machine) {
            0x14C  { $info.Architecture = "x86" }
            0x8664 { $info.Architecture = "x64" }
            0xAA64 { $info.Architecture = "ARM64" }
            default { $info.Architecture = "unknown (0x{0:X4})" -f $machine }
        }

        # Optional header
        $optOffset = $coffOffset + 20
        $magic = [BitConverter]::ToUInt16($bytes, $optOffset)

        if ($magic -eq 0x10B) {
            # PE32
            $subsystem = [BitConverter]::ToUInt16($bytes, $optOffset + 68)
        } elseif ($magic -eq 0x20B) {
            # PE32+
            $subsystem = [BitConverter]::ToUInt16($bytes, $optOffset + 68)
        } else {
            $subsystem = 0
        }

        switch ($subsystem) {
            1 { $info.Subsystem = "Native (driver)" }
            2 { $info.Subsystem = "GUI" }
            3 { $info.Subsystem = "Console" }
            default { $info.Subsystem = "unknown ($subsystem)" }
        }

        $info.IsDotNet = Test-DotNetAssembly $FilePath
    } catch {
        # Silently fail — info will have defaults
    }

    return $info
}

# --- Determine engine ---
$peInfo = Get-PeInfo $InputFileAbs
$isDotNet = $peInfo.IsDotNet

Write-Host "=== Decompiling $InputFile ===" -ForegroundColor Cyan
Write-Host "Architecture: $($peInfo.Architecture)"
Write-Host "Subsystem: $($peInfo.Subsystem)"
Write-Host ".NET Assembly: $isDotNet"
Write-Host ""

if ($Engine -eq 'auto') {
    if ($isDotNet) {
        $Engine = 'ilspy'
        Write-Host "Auto-detected: .NET assembly -> using ILSpy" -ForegroundColor Green
    } else {
        $Engine = 'ghidra'
        Write-Host "Auto-detected: Native PE -> using Ghidra" -ForegroundColor Green
    }
}

Write-Host "Engine: $Engine"
Write-Host "Output directory: $Output"
Write-Host ""

# --- ILSpy decompilation ---
function Invoke-ILSpy {
    if (-not (Get-Command ilspycmd -ErrorAction SilentlyContinue)) {
        Write-Host "Error: ilspycmd is not installed. Run: dotnet tool install -g ilspycmd" -ForegroundColor Red
        exit 1
    }

    $sourcesDir = Join-Path $Output "sources"
    New-Item -ItemType Directory -Path $sourcesDir -Force | Out-Null

    Write-Host "Running: ilspycmd -p -o `"$sourcesDir`" `"$InputFileAbs`"" -ForegroundColor Yellow
    & ilspycmd -p -o $sourcesDir $InputFileAbs 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Warning: ilspycmd exited with code $LASTEXITCODE. Output may be incomplete." -ForegroundColor Yellow
    }

    # Count output files
    if (Test-Path $sourcesDir) {
        $csFiles = Get-ChildItem -Path $sourcesDir -Recurse -Filter "*.cs" | Measure-Object
        Write-Host ""
        Write-Host "C# files decompiled: $($csFiles.Count)" -ForegroundColor Green

        # List top-level structure
        Write-Host ""
        Write-Host "Top-level structure:" -ForegroundColor Cyan
        Get-ChildItem -Path $sourcesDir -Depth 1 | ForEach-Object {
            $prefix = if ($_.PSIsContainer) { "[DIR] " } else { "      " }
            Write-Host "  $prefix$($_.Name)"
        }
    }
}

# --- Ghidra decompilation ---
function Invoke-Ghidra {
    # Find Ghidra
    $ghidraDir = $env:GHIDRA_INSTALL_DIR
    if (-not $ghidraDir) {
        # Try common locations
        $locations = @(
            "$env:ProgramFiles\Ghidra",
            "$env:USERPROFILE\.local\share\ghidra",
            "C:\Tools\Ghidra",
            "C:\ghidra"
        )
        foreach ($loc in $locations) {
            $candidates = Get-ChildItem -Path $loc -Directory -Filter "ghidra_*" -ErrorAction SilentlyContinue
            if ($candidates) {
                $ghidraDir = ($candidates | Sort-Object Name -Descending | Select-Object -First 1).FullName
                if (Test-Path "$ghidraDir\support\analyzeHeadless.bat") {
                    break
                }
                $ghidraDir = $null
            }
        }
    }

    if (-not $ghidraDir -or -not (Test-Path "$ghidraDir\support\analyzeHeadless.bat")) {
        Write-Host "Error: Ghidra not found. Set GHIDRA_INSTALL_DIR environment variable." -ForegroundColor Red
        exit 1
    }

    $analyzeHeadless = "$ghidraDir\support\analyzeHeadless.bat"
    $ghidraScriptsDir = Join-Path $ScriptDir "ghidra-scripts"
    $projectDir = Join-Path $env:TEMP "GhidraProjects"
    $projectName = "DecompileProject"

    # Create project directory
    New-Item -ItemType Directory -Path $projectDir -Force | Out-Null
    New-Item -ItemType Directory -Path $Output -Force | Out-Null

    Write-Host "Running Ghidra headless analysis..." -ForegroundColor Yellow
    Write-Host "Project: $projectDir\$projectName" -ForegroundColor DarkGray
    Write-Host "Script: $ghidraScriptsDir\ExportDecompiled.py" -ForegroundColor DarkGray
    Write-Host ""

    & cmd /c "`"$analyzeHeadless`" `"$projectDir`" `"$projectName`" -import `"$InputFileAbs`" -scriptPath `"$ghidraScriptsDir`" -postScript `"ExportDecompiled.py`" `"$Output`" -deleteProject -overwrite" 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Warning: Ghidra exited with code $LASTEXITCODE. Output may be incomplete." -ForegroundColor Yellow
    }

    # Report results
    $decompDir = Join-Path $Output "decompiled"
    if (Test-Path $decompDir) {
        $cFiles = Get-ChildItem -Path $decompDir -Recurse -Filter "*.c" | Measure-Object
        Write-Host ""
        Write-Host "C pseudocode files: $($cFiles.Count)" -ForegroundColor Green
    }

    $importsFile = Join-Path $Output "imports.txt"
    if (Test-Path $importsFile) {
        $importLines = (Get-Content $importsFile | Where-Object { $_ -match '^\s+\w' }).Count
        Write-Host "Imported functions: $importLines"
    }

    $exportsFile = Join-Path $Output "exports.txt"
    if (Test-Path $exportsFile) {
        $exportLines = (Get-Content $exportsFile | Where-Object { $_ -match '^\w' -and $_ -notmatch '^#' }).Count
        Write-Host "Exported functions: $exportLines"
    }

    $summaryFile = Join-Path $Output "summary.txt"
    if (Test-Path $summaryFile) {
        Write-Host ""
        Write-Host "--- Analysis Summary ---" -ForegroundColor Cyan
        Get-Content $summaryFile | Write-Host
    }
}

# --- Strings extraction ---
function Invoke-StringsExtraction {
    if ($NoStrings) {
        Write-Host "Skipping strings extraction (-NoStrings flag set)"
        return
    }

    $stringsOutput = Join-Path $Output "strings.txt"

    # Check if strings were already extracted by Ghidra
    if (Test-Path $stringsOutput) {
        $existingLines = (Get-Content $stringsOutput | Measure-Object).Count
        if ($existingLines -gt 5) {
            Write-Host "Strings already extracted by decompiler ($existingLines references)"
            return
        }
    }

    if (Get-Command strings2 -ErrorAction SilentlyContinue) {
        Write-Host "Extracting strings with strings2..."
        & strings2 $InputFileAbs > $stringsOutput 2>$null
    } elseif (Get-Command strings -ErrorAction SilentlyContinue) {
        Write-Host "Extracting strings with SysInternals strings..."
        & strings -q -accepteula $InputFileAbs > $stringsOutput 2>$null
    } else {
        Write-Host "No strings tool available. Skipping strings extraction."
        Write-Host "Install strings2 or SysInternals strings for embedded string analysis."
        return
    }

    if (Test-Path $stringsOutput) {
        $stringCount = (Get-Content $stringsOutput | Measure-Object).Count
        Write-Host "Strings extracted: $stringCount"
    }
}

# --- Run ---
switch ($Engine) {
    'ilspy' {
        Invoke-ILSpy
    }
    'ghidra' {
        Invoke-Ghidra
    }
}

Invoke-StringsExtraction

Write-Host ""
Write-Host "=== Decompilation complete ===" -ForegroundColor Green
Write-Host "Output: $Output"
