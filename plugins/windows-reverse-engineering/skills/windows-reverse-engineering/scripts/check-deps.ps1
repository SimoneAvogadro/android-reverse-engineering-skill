# check-deps.ps1 — Verify dependencies for Windows reverse engineering
# Output includes machine-readable INSTALL_REQUIRED:<dep> and INSTALL_OPTIONAL:<dep> lines.
# Exit code 0 = all required OK, 1 = missing required deps.

$ErrorActionPreference = 'SilentlyContinue'

$RequiredJavaMajor = 17
$Errors = 0
$MissingRequired = @()
$MissingOptional = @()

Write-Host "=== Windows Reverse Engineering: Dependency Check ==="
Write-Host ""

# --- Java ---
$javaOk = $false
$javaCmdExists = Get-Command java -ErrorAction SilentlyContinue
if ($javaCmdExists) {
    $javaVersionOutput = & java -version 2>&1 | Select-Object -First 1
    $javaVersionStr = [string]$javaVersionOutput
    if ($javaVersionStr -match '"(\d+)') {
        $javaVersion = [int]$Matches[1]
        if ($javaVersion -ge $RequiredJavaMajor) {
            Write-Host "[OK] Java $javaVersion detected"
            $javaOk = $true
        } else {
            Write-Host "[WARN] Java detected but version $javaVersion is below $RequiredJavaMajor"
            $Errors++
            $MissingRequired += 'java'
        }
    } else {
        Write-Host "[WARN] Java detected but could not parse version from: $javaVersionStr"
        $Errors++
        $MissingRequired += 'java'
    }
} else {
    Write-Host "[MISSING] Java is not installed or not in PATH"
    $Errors++
    $MissingRequired += 'java'
}

# --- Ghidra ---
$ghidraOk = $false
$ghidraDir = $env:GHIDRA_INSTALL_DIR
if ($ghidraDir -and (Test-Path "$ghidraDir\support\analyzeHeadless.bat")) {
    Write-Host "[OK] Ghidra detected at $ghidraDir"
    $ghidraOk = $true
} elseif (Get-Command ghidra -ErrorAction SilentlyContinue) {
    Write-Host "[OK] Ghidra detected in PATH"
    $ghidraOk = $true
} else {
    # Check common installation locations
    $ghidraLocations = @(
        "$env:ProgramFiles\Ghidra",
        "$env:ProgramFiles(x86)\Ghidra",
        "$env:USERPROFILE\ghidra",
        "C:\Tools\Ghidra",
        "C:\ghidra"
    )
    foreach ($loc in $ghidraLocations) {
        $candidates = Get-ChildItem -Path $loc -Directory -Filter "ghidra_*" -ErrorAction SilentlyContinue
        if ($candidates) {
            $ghidraDir = $candidates | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
            if (Test-Path "$ghidraDir\support\analyzeHeadless.bat") {
                Write-Host "[OK] Ghidra detected at $ghidraDir"
                Write-Host "     Hint: Set GHIDRA_INSTALL_DIR=$ghidraDir for faster detection"
                $ghidraOk = $true
                break
            }
        }
    }
    if (-not $ghidraOk) {
        Write-Host "[MISSING] Ghidra is not installed or GHIDRA_INSTALL_DIR is not set"
        $MissingRequired += 'ghidra'
        $Errors++
    }
}

# --- ilspycmd ---
$ilspyOk = $false
if (Get-Command ilspycmd -ErrorAction SilentlyContinue) {
    $ilspyVersion = & ilspycmd --version 2>&1 | Select-Object -First 1
    Write-Host "[OK] ilspycmd detected ($ilspyVersion)"
    $ilspyOk = $true
} else {
    Write-Host "[MISSING] ilspycmd is not installed (for .NET assembly decompilation)"
    # ilspycmd is required if the user wants .NET support, but we only consider
    # at least one decompiler (ghidra OR ilspycmd) as strictly required
    if (-not $ghidraOk) {
        $MissingRequired += 'ilspycmd'
        $Errors++
    } else {
        $MissingOptional += 'ilspycmd'
    }
}

# If neither decompiler is available, both are required
if (-not $ghidraOk -and -not $ilspyOk) {
    Write-Host ""
    Write-Host "[ERROR] No decompiler available. At least one of Ghidra or ilspycmd is required."
}

# --- strings / strings2 ---
$stringsOk = $false
if (Get-Command strings2 -ErrorAction SilentlyContinue) {
    Write-Host "[OK] strings2 detected"
    $stringsOk = $true
} elseif (Get-Command strings -ErrorAction SilentlyContinue) {
    Write-Host "[OK] strings (SysInternals) detected"
    $stringsOk = $true
} else {
    Write-Host "[MISSING] strings/strings2 not found (optional - extracts embedded strings from binaries)"
    $MissingOptional += 'strings'
}

# --- dumpbin ---
$dumpbinOk = $false
if (Get-Command dumpbin -ErrorAction SilentlyContinue) {
    Write-Host "[OK] dumpbin detected"
    $dumpbinOk = $true
} else {
    # Try to find via VS Developer environment
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsInstallPath = & $vswhere -latest -property installationPath 2>$null
        if ($vsInstallPath) {
            $dumpbinCandidates = Get-ChildItem -Path "$vsInstallPath\VC\Tools\MSVC" -Recurse -Filter "dumpbin.exe" -ErrorAction SilentlyContinue
            if ($dumpbinCandidates) {
                Write-Host "[OK] dumpbin detected at $($dumpbinCandidates[0].FullName)"
                Write-Host "     Note: Use Developer Command Prompt for automatic PATH setup"
                $dumpbinOk = $true
            }
        }
    }
    if (-not $dumpbinOk) {
        Write-Host "[MISSING] dumpbin not found (optional - requires Visual Studio C++ Build Tools)"
        Write-Host "         Install from: https://visualstudio.microsoft.com/visual-cpp-build-tools/"
        $MissingOptional += 'dumpbin'
    }
}

# --- .NET SDK (for ilspycmd) ---
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    $dotnetVersion = & dotnet --version 2>$null
    Write-Host "[OK] .NET SDK $dotnetVersion detected"
} else {
    Write-Host "[MISSING] .NET SDK not found (needed to install ilspycmd)"
    if (-not $ilspyOk) {
        $MissingOptional += 'dotnet-sdk'
    }
}

# --- Optional: de4dot ---
if (Get-Command de4dot -ErrorAction SilentlyContinue) {
    Write-Host "[OK] de4dot detected (optional - .NET deobfuscation)"
} else {
    Write-Host "[MISSING] de4dot not found (optional - .NET deobfuscator for obfuscated assemblies)"
    $MissingOptional += 'de4dot'
}

# --- Optional: x64dbg ---
if (Get-Command x64dbg -ErrorAction SilentlyContinue) {
    Write-Host "[OK] x64dbg detected (optional)"
} elseif (Test-Path "$env:ProgramFiles\x64dbg\release\x64\x64dbg.exe") {
    Write-Host "[OK] x64dbg detected (optional)"
} else {
    Write-Host "[MISSING] x64dbg not found (optional - dynamic debugging)"
    $MissingOptional += 'x64dbg'
}

# --- Machine-readable summary ---
Write-Host ""
foreach ($dep in $MissingRequired) {
    Write-Host "INSTALL_REQUIRED:$dep"
}
foreach ($dep in $MissingOptional) {
    Write-Host "INSTALL_OPTIONAL:$dep"
}

Write-Host ""
if ($Errors -gt 0) {
    Write-Host "*** $($MissingRequired.Count) required dependency/ies missing. ***"
    Write-Host "Run install-dep.ps1 <name> to install, or see references/setup-guide.md."
    exit 1
} else {
    if ($MissingOptional.Count -gt 0) {
        Write-Host "Required dependencies OK. $($MissingOptional.Count) optional dependency/ies missing."
        Write-Host "Run install-dep.ps1 <name> to install optional tools."
    } else {
        Write-Host "All dependencies are installed. Ready to decompile."
    }
    exit 0
}
