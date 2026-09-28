# check-neutralize-deps.ps1 - Verify dependencies for SDK neutralization
# Usage: check-neutralize-deps.ps1 [<input-file>]
#   When <input-file> is a split bundle (.xapk/.apkm/.apks or a directory of
#   split APKs), APKEditor is reported as required; otherwise it is optional.
# Output includes machine-readable INSTALL_REQUIRED: and INSTALL_OPTIONAL: lines,
# plus ZIPALIGN_PAGE_ALIGN:16k|4k|none.
#
# Windows: dependency check, decode-apk.ps1 and rebuild-apk.ps1 are available;
# neutralize.sh and registry-scan.py still need bash (WSL / Git Bash) for now.
param(
    [Parameter(Position=0)]
    [string]$InputFile,
    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
# UTF-8 output so captured paths keep non-ASCII characters
$script:CallerOutputEncoding = $null
try {
    $script:CallerOutputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch { }
# The whole script runs inside this try: the caller's console encoding is
# restored in the matching finally at the end, including on every 'exit'.
try {

if ($Help) {
    Write-Host @"
Usage: check-neutralize-deps.ps1 [<input-file>]

Check the SDK neutralizer dependencies (Java 17+, apktool 2.9.0+, apksigner,
zipalign, keytool, APKEditor).

When <input-file> is a split bundle (.xapk, .apkm, .apks, or a directory of
split APKs), APKEditor is required; otherwise it is optional.

Environment:
  APKEDITOR_JAR   Path to APKEditor.jar (default: %USERPROFILE%\.local\share\apkeditor\APKEditor.jar)
"@
    exit 0
}

# Refresh PATH from user environment so we pick up tools installed in the same session
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath) {
    foreach ($dir in $userPath -split ';') {
        if ($dir -and $env:PATH -notlike "*$dir*") {
            $env:PATH = "$dir;$env:PATH"
        }
    }
}
$localBin = Join-Path $env:USERPROFILE '.local\bin'
if ((Test-Path $localBin) -and ($env:PATH -notlike "*$localBin*")) {
    $env:PATH = "$localBin;$env:PATH"
}

$installDep = Join-Path $PSScriptRoot '..\..\android-reverse-engineering\scripts\install-dep.ps1'
try { $installDep = (Resolve-Path -LiteralPath $installDep).Path } catch { }

# Run a native tool and capture stdout+stderr as text (PS 5.1 turns redirected
# stderr into error records, which 'Stop' would make fatal)
function Get-ToolOutput {
    param([string]$Exe, [string[]]$Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $Exe @Arguments 2>&1 | ForEach-Object { "$_" }
    } catch {
        $out = @("$_")
    } finally {
        $ErrorActionPreference = $prev
    }
    return ($out -join "`n")
}

# Android SDK build-tools lookup (same order as rebuild-apk.ps1)
function Get-LatestBuildToolsDir {
    param([string]$SdkRoot)
    if (-not $SdkRoot) { return }
    $bt = Join-Path $SdkRoot 'build-tools'
    if (-not (Test-Path -LiteralPath $bt)) { return }
    $latest = Get-ChildItem -LiteralPath $bt -Directory |
        Sort-Object { try { [version]($_.Name -replace '-.*$', '') } catch { [version]'0.0' } } |
        Select-Object -Last 1
    if ($latest) { return $latest.FullName }
}
$sdkRoots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'), (Join-Path $env:USERPROFILE '.local\share\android-sdk'))

$splitInput = $false
if ($InputFile) {
    if (Test-Path -LiteralPath $InputFile -PathType Container) {
        $splitInput = $true
    } elseif ([IO.Path]::GetExtension($InputFile).TrimStart('.').ToLower() -in @('xapk', 'apkm', 'apks')) {
        $splitInput = $true
    }
}

$REQUIRED_JAVA_MAJOR = 17
$missingRequired = New-Object System.Collections.ArrayList
$missingOptional = New-Object System.Collections.ArrayList
function Add-Required { param($d) if (-not $missingRequired.Contains($d)) { [void]$missingRequired.Add($d) } }
function Add-Optional { param($d) if (-not $missingOptional.Contains($d)) { [void]$missingOptional.Add($d) } }

Write-Host "=== SDK Neutralizer: Dependency Check ==="
Write-Host ""

# --- Java 17+ (required) ---
if (Get-Command java -ErrorAction SilentlyContinue) {
    $javaVersionStr = (Get-ToolOutput 'java' @('-version')) -split "`n" | Select-Object -First 1
    $javaVersion = 0
    if ($javaVersionStr -match '"(\d+)') {
        $javaVersion = [int]$Matches[1]
        if ($javaVersion -eq 1 -and $javaVersionStr -match '"1\.(\d+)') {
            $javaVersion = [int]$Matches[1]
        }
    }
    if ($javaVersion -ge $REQUIRED_JAVA_MAJOR) {
        Write-Host "[OK] Java $javaVersion detected"
    } else {
        Write-Host "[WARN] Java detected but version $javaVersion is below $REQUIRED_JAVA_MAJOR"
        Add-Required 'java'
    }
} else {
    Write-Host "[MISSING] Java is not installed or not in PATH"
    Add-Required 'java'
}

# --- apktool (required, minimum 2.9.0) ---
$apktoolJar = $null
$apktoolCmd = Get-Command apktool -ErrorAction SilentlyContinue
$apktoolCandidates = @()
if ($apktoolCmd -and $apktoolCmd.Source) { $apktoolCandidates += (Join-Path (Split-Path $apktoolCmd.Source -Parent) 'apktool.jar') }
$apktoolCandidates += (Join-Path $env:USERPROFILE '.local\share\apktool\apktool.jar')
$apktoolCandidates += (Join-Path $env:USERPROFILE 'scoop\apps\apktool\current\apktool.jar')
if ($env:SCOOP) { $apktoolCandidates += (Join-Path $env:SCOOP 'apps\apktool\current\apktool.jar') }
if ($env:ChocolateyInstall) { $apktoolCandidates += (Join-Path $env:ChocolateyInstall 'lib\apktool\tools\apktool.jar') }
foreach ($c in $apktoolCandidates) {
    if (Test-Path -LiteralPath $c) { $apktoolJar = $c; break }
}
if ($apktoolJar -or $apktoolCmd) {
    if ($apktoolJar) {
        $apktoolOut = Get-ToolOutput 'java' @('-jar', $apktoolJar, '--version')
    } else {
        $apktoolOut = Get-ToolOutput $apktoolCmd.Source @('--version')
    }
    if ($apktoolOut -match '(\d+)\.(\d+)\.(\d+)') {
        $v = [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
        if ($v -ge [version]'2.9.0') {
            Write-Host "[OK] apktool $v detected"
        } else {
            Write-Host "[WARN] apktool $v detected but version >= 2.9.0 is required"
            Write-Host "       Older versions fail on modern APKs (new resource types, targetSdk 34+)."
            Add-Required 'apktool'
        }
    } else {
        Write-Host "[OK] apktool detected (could not parse version - assuming compatible)"
    }
} else {
    Write-Host "[MISSING] apktool is not installed or not in PATH (required for decode/rebuild)"
    Add-Required 'apktool'
}

# --- keytool (required for debug key generation) ---
if (Get-Command keytool -ErrorAction SilentlyContinue) {
    Write-Host "[OK] keytool detected (part of JDK)"
} else {
    Write-Host "[MISSING] keytool not found (required for debug key generation, part of JDK)"
    Add-Required 'java'
}

# --- apksigner (required; Android SDK build-tools first, then PATH) ---
$apksignerPath = $null
foreach ($sdk in $sdkRoots) {
    $bt = Get-LatestBuildToolsDir $sdk
    if ($bt -and (Test-Path -LiteralPath (Join-Path $bt 'apksigner.bat'))) { $apksignerPath = Join-Path $bt 'apksigner.bat'; break }
}
if (-not $apksignerPath) {
    $c = Get-Command apksigner -ErrorAction SilentlyContinue
    if ($c) { $apksignerPath = $c.Source }
}
if ($apksignerPath) {
    Write-Host "[OK] apksigner detected: $apksignerPath"
} elseif (Get-Command jarsigner -ErrorAction SilentlyContinue) {
    Write-Host "[WARN] only jarsigner found: v1 signatures only - APKs targeting SDK 30+ are refused by"
    Write-Host "       rebuild-apk.ps1. Install Android build-tools (apksigner + zipalign)."
    Add-Required 'build-tools'
} else {
    Write-Host "[MISSING] apksigner not found (required for signing - part of Android build-tools)"
    Add-Required 'build-tools'
}

# --- APKEditor (required for split bundles: merges splits before decoding) ---
$apkEditorDesc = $null
$apkEditorVer = ''
if ($env:APKEDITOR_JAR) {
    if (Test-Path -LiteralPath $env:APKEDITOR_JAR) {
        $apkEditorDesc = $env:APKEDITOR_JAR
        if ((Get-ToolOutput 'java' @('-jar', $env:APKEDITOR_JAR, '-version')) -match 'APKEditor version ([0-9.]+)') { $apkEditorVer = $Matches[1] }
    } else {
        Write-Host "[WARN] APKEDITOR_JAR is set but the file does not exist: $env:APKEDITOR_JAR"
    }
} else {
    $c = Join-Path $env:USERPROFILE '.local\share\apkeditor\APKEditor.jar'
    $cmd = Get-Command apkeditor -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $c) {
        $apkEditorDesc = $c
        if ((Get-ToolOutput 'java' @('-jar', $c, '-version')) -match 'APKEditor version ([0-9.]+)') { $apkEditorVer = $Matches[1] }
    } elseif ($cmd) {
        $apkEditorDesc = $cmd.Source
        if ((Get-ToolOutput $cmd.Source @('-version')) -match 'APKEditor version ([0-9.]+)') { $apkEditorVer = $Matches[1] }
    }
}
if ($apkEditorDesc -and $apkEditorVer) {
    Write-Host "[OK] APKEditor $apkEditorVer detected ($apkEditorDesc)"
} else {
    if ($apkEditorDesc) { Write-Host "[WARN] APKEditor at $apkEditorDesc does not run (corrupt JAR or no Java?)" }
    if ($splitInput) {
        Write-Host "[MISSING] APKEditor not usable (required: the input is a split bundle, merged into one APK before decoding)"
        Add-Required 'apkeditor'
    } else {
        Write-Host "[MISSING] APKEditor not usable (optional for .apk input; required for XAPK/APKM/APKS input)"
        Add-Optional 'apkeditor'
    }
}

# --- zipalign (required: page-aligns stored native libraries) ---
# build-tools 35+ zipalign supports -P 16 (16 KB pages); older ones only -p (4 KB).
$zaCandidates = @()
$zaCmd = Get-Command zipalign -ErrorAction SilentlyContinue
if ($zaCmd) { $zaCandidates += $zaCmd.Source }
foreach ($sdk in $sdkRoots) {
    $bt = Get-LatestBuildToolsDir $sdk
    if ($bt) {
        $za = Join-Path $bt 'zipalign.exe'
        if (Test-Path -LiteralPath $za) { $zaCandidates += $za }
    }
}
$zaPath = $null
$zaPage = 'none'
foreach ($za in $zaCandidates) {
    if ((Get-ToolOutput $za @()) -match '-P <pagesize') {
        $zaPath = $za; $zaPage = '16k'; break
    }
    if (-not $zaPath) { $zaPath = $za; $zaPage = '4k' }
}
if ($zaPage -eq '16k') {
    Write-Host "[OK] zipalign detected: $zaPath (supports -P 16 - 16 KB page alignment)"
} elseif ($zaPage -eq '4k') {
    Write-Host "[WARN] zipalign detected: $zaPath (only -p - 4 KB page alignment)"
    Write-Host "       Devices with 16 KB pages refuse 4 KB-aligned native libraries;"
    Write-Host "       Android build-tools 35+ zipalign adds -P 16."
    Add-Optional 'build-tools'
} else {
    Write-Host "[MISSING] zipalign not found (required - stored native libraries must be page-aligned)"
    Add-Required 'build-tools'
}
Write-Host "ZIPALIGN_PAGE_ALIGN:$zaPage"

Write-Host ""
Write-Host "Note: on Windows, neutralize.sh and registry-scan.py need bash + python3"
Write-Host "      (WSL or Git Bash) for now; decode-apk.ps1 and rebuild-apk.ps1 are native."

# --- Machine-readable summary ---
Write-Host ""
foreach ($dep in $missingRequired) {
    Write-Host "INSTALL_REQUIRED:$dep"
}
foreach ($dep in $missingOptional) {
    Write-Host "INSTALL_OPTIONAL:$dep"
}

Write-Host ""
if ($missingRequired.Count -gt 0) {
    Write-Host "*** $($missingRequired.Count) required dependency/ies missing. ***"
    Write-Host ""
    Write-Host "Install all neutralizer dependencies at once. 'build-tools' is Google's Android SDK"
    Write-Host "Build-Tools, licensed under https://developer.android.com/studio/terms - the user must"
    Write-Host "accept that license before -AcceptAndroidSdkLicense is passed:"
    Write-Host "  & `"$installDep`" neutralize-all -AcceptAndroidSdkLicense"
    Write-Host ""
    Write-Host "Or install individually: & `"$installDep`" <name>"
    exit 1
} else {
    if ($missingOptional.Count -gt 0) {
        Write-Host "Required dependencies OK. $($missingOptional.Count) optional dependency/ies missing."
    } else {
        Write-Host "All dependencies are installed. Ready to neutralize."
    }
    exit 0
}

} finally {
    if ($script:CallerOutputEncoding) {
        try { [Console]::OutputEncoding = $script:CallerOutputEncoding } catch { }
    }
}
