# install-dep.ps1 — Install a single dependency for Android reverse engineering
# Usage: install-dep.ps1 <dependency> [-AcceptAndroidSdkLicense]
# Dependencies: java, jadx, vineflower, dex2jar, apktool, apkeditor, build-tools, adb
# Compound: neutralize-all (java + apktool + apkeditor + build-tools)
#
# Exit codes:
#   0 — installed successfully
#   1 — installation failed
#   2 — requires manual action
param(
    [Parameter(Position=0)]
    [string]$Dep,
    [switch]$AcceptAndroidSdkLicense,
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

function Show-Usage {
    Write-Host @"
Usage: install-dep.ps1 <dependency> [-AcceptAndroidSdkLicense]

Install a dependency required for Android reverse engineering.

Available dependencies:
  java         Java JDK 17+
  jadx         jadx decompiler
  vineflower   Vineflower (Fernflower fork) decompiler
  dex2jar      DEX to JAR converter
  apktool      Android resource decoder
  apkeditor    APKEditor (merges XAPK/APKM/APKS split APKs into one APK)
  build-tools  Android SDK Build-Tools 36.0.0 (zipalign -P 16, apksigner, aapt2);
               needs -AcceptAndroidSdkLicense (or ACCEPT_ANDROID_SDK_LICENSE=1)
  adb          Android Debug Bridge

Compound targets:
  neutralize-all   java, apktool, apkeditor, build-tools

The script detects available package managers (winget, scoop, choco), then:
  - Installs using the first available manager
  - Falls back to direct download to %USERPROFILE%\.local\share\
  - Prints manual instructions if no option works
"@
    exit 0
}

if ($Help -or -not $Dep -or $Dep -eq '-h' -or $Dep -eq '--help') { Show-Usage }

# --- Detect environment ---
$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
$hasScoop  = [bool](Get-Command scoop -ErrorAction SilentlyContinue)
$hasChoco  = [bool](Get-Command choco -ErrorAction SilentlyContinue)

function Write-Info  { param($msg) Write-Host "[INFO] $msg" }
function Write-Ok    { param($msg) Write-Host "[OK] $msg" }
function Write-Fail  { param($msg) Write-Host "[FAIL] $msg" -ForegroundColor Red }
function Write-Manual {
    param($msg)
    Write-Host "[MANUAL] $msg" -ForegroundColor Yellow
    Write-Host "         Cannot install automatically. Please install manually and retry." -ForegroundColor Yellow
    exit 2
}

# --- Helper: download a file ---
function Invoke-Download {
    param([string]$Url, [string]$Dest)
    Write-Info "Downloading $Url..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
}

# --- Helper: get latest GitHub release tag ---
function Get-GHLatestTag {
    param([string]$Repo)
    $url = "https://api.github.com/repos/$Repo/releases/latest"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = Invoke-RestMethod -Uri $url -UseBasicParsing
    return $response.tag_name
}

# --- Helper: ensure directory on PATH ---
function Add-ToUserPath {
    param([string]$Dir)
    $currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($currentPath -notlike "*$Dir*") {
        [Environment]::SetEnvironmentVariable('PATH', "$Dir;$currentPath", 'User')
        Write-Info "Added $Dir to user PATH. Restart your terminal to apply."
    }
    if ($env:PATH -notlike "*$Dir*") {
        $env:PATH = "$Dir;$env:PATH"
    }
}

$SelfScript = $PSCommandPath   # used by neutralize-all to run each dependency as a child
$localBin   = Join-Path $env:USERPROFILE '.local\bin'
$localShare = Join-Path $env:USERPROFILE '.local\share'

# =====================================================================
# Dependency installers
# =====================================================================

function Install-Java {
    $javaBin = Get-Command java -ErrorAction SilentlyContinue
    if ($javaBin) {
        $verOutput = & java -version 2>&1 | Select-Object -First 1
        if ("$verOutput" -match '"(\d+)') {
            $ver = [int]$Matches[1]
            if ($ver -ge 17) {
                Write-Ok "Java $ver already installed"
                return
            }
        }
    }

    Write-Info "Installing Java JDK 17+..."
    if ($hasWinget) {
        Write-Info "Installing via winget..."
        winget install --id Microsoft.OpenJDK.17 --accept-source-agreements --accept-package-agreements
    } elseif ($hasScoop) {
        Write-Info "Installing via scoop..."
        scoop install openjdk17
    } elseif ($hasChoco) {
        Write-Info "Installing via choco..."
        choco install openjdk17 -y
    } else {
        Write-Manual "Install Java JDK 17+ from https://adoptium.net/"
    }

    # Verify
    $javaBin = Get-Command java -ErrorAction SilentlyContinue
    if ($javaBin) {
        Write-Ok "Java installed: $(& java -version 2>&1 | Select-Object -First 1)"
    } else {
        Write-Fail "Java installation may require a terminal restart for PATH update."
        exit 1
    }
}

function Install-Jadx {
    if (Get-Command jadx -ErrorAction SilentlyContinue) {
        Write-Ok "jadx already installed"
        return
    }

    # Try scoop first (cleanest on Windows)
    if ($hasScoop) {
        Write-Info "Installing jadx via scoop..."
        scoop install jadx
        if (Get-Command jadx -ErrorAction SilentlyContinue) {
            Write-Ok "jadx installed via scoop"
            return
        }
    }

    # Direct download from GitHub releases
    Write-Info "Installing jadx from GitHub releases..."
    $tag = Get-GHLatestTag "skylot/jadx"
    if (-not $tag) {
        Write-Fail "Could not determine latest jadx version."
        Write-Manual "Download from https://github.com/skylot/jadx/releases/latest"
    }

    $version = $tag -replace '^v', ''
    $url = "https://github.com/skylot/jadx/releases/download/$tag/jadx-$version.zip"
    $tmpZip = Join-Path $env:TEMP "jadx-$version.zip"

    Invoke-Download -Url $url -Dest $tmpZip

    $installDir = Join-Path $localShare 'jadx'
    if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $installDir -Force
    Remove-Item $tmpZip -Force

    # Add jadx\bin to PATH
    $jadxBin = Join-Path $installDir 'bin'
    Add-ToUserPath $jadxBin

    if (Get-Command jadx -ErrorAction SilentlyContinue) {
        Write-Ok "jadx $version installed to $installDir"
    } else {
        Write-Ok "jadx $version installed to $installDir"
        Write-Info "Restart your terminal or run: `$env:PATH = '$jadxBin;' + `$env:PATH"
    }
}

function Install-Vineflower {
    if (Get-Command vineflower -ErrorAction SilentlyContinue) {
        Write-Ok "Vineflower CLI already installed"
        return
    }
    if (Get-Command fernflower -ErrorAction SilentlyContinue) {
        Write-Ok "Fernflower CLI already installed"
        return
    }
    $ffCandidates = @(
        $env:FERNFLOWER_JAR_PATH,
        "$env:USERPROFILE\.local\share\vineflower\vineflower.jar",
        "$env:USERPROFILE\vineflower\vineflower.jar",
        "$env:USERPROFILE\fernflower\fernflower.jar"
    )
    foreach ($c in $ffCandidates) {
        if ($c -and (Test-Path $c -ErrorAction SilentlyContinue)) {
            Write-Ok "Vineflower/Fernflower JAR already exists: $c"
            return
        }
    }

    # Download JAR from GitHub releases
    Write-Info "Installing Vineflower from GitHub releases..."
    $tag = Get-GHLatestTag "Vineflower/vineflower"
    if (-not $tag) {
        Write-Fail "Could not determine latest Vineflower version."
        Write-Manual "Download from https://github.com/Vineflower/vineflower/releases/latest"
    }

    $version = $tag -replace '^v', ''
    $url = "https://github.com/Vineflower/vineflower/releases/download/$tag/vineflower-$version.jar"
    $installDir = Join-Path $localShare 'vineflower'
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null

    Invoke-Download -Url $url -Dest (Join-Path $installDir 'vineflower.jar')

    # Create wrapper batch file
    New-Item -ItemType Directory -Path $localBin -Force | Out-Null
    $wrapperPath = Join-Path $localBin 'vineflower.cmd'
    Set-Content -Path $wrapperPath -Value "@echo off`r`njava -jar `"$installDir\vineflower.jar`" %*"

    Add-ToUserPath $localBin
    [Environment]::SetEnvironmentVariable('FERNFLOWER_JAR_PATH', "$installDir\vineflower.jar", 'User')
    $env:FERNFLOWER_JAR_PATH = "$installDir\vineflower.jar"

    Write-Ok "Vineflower $version installed to $installDir\vineflower.jar"
    Write-Info "FERNFLOWER_JAR_PATH set to $installDir\vineflower.jar"
}

function Install-Dex2Jar {
    if ((Get-Command d2j-dex2jar -ErrorAction SilentlyContinue) -or
        (Get-Command d2j-dex2jar.bat -ErrorAction SilentlyContinue)) {
        Write-Ok "dex2jar already installed"
        return
    }

    Write-Info "Installing dex2jar from GitHub releases..."
    $tag = try { Get-GHLatestTag "ThexXTURBOXx/dex2jar" } catch { "2.4.35" }
    if (-not $tag) { $tag = "2.4.35" }

    $version = $tag -replace '^v', ''
    $url = "https://github.com/ThexXTURBOXx/dex2jar/releases/download/$tag/dex-tools-$version.zip"
    $tmpZip = Join-Path $env:TEMP "dex2jar-$version.zip"

    try {
        Invoke-Download -Url $url -Dest $tmpZip
    } catch {
        # Try alternate naming (pre-2.4.30 releases)
        $url = "https://github.com/ThexXTURBOXx/dex2jar/releases/download/$tag/dex-tools-v$version.zip"
        try {
            Invoke-Download -Url $url -Dest $tmpZip
        } catch {
            Write-Fail "Download failed."
            Write-Manual "Download from https://github.com/ThexXTURBOXx/dex2jar/releases/latest"
        }
    }

    $installDir = Join-Path $localShare 'dex2jar'
    if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $installDir -Force
    Remove-Item $tmpZip -Force

    # Find the actual bin directory (may be nested)
    $d2jBat = Get-ChildItem -Path $installDir -Recurse -Filter 'd2j-dex2jar.bat' | Select-Object -First 1
    if (-not $d2jBat) {
        $d2jBat = Get-ChildItem -Path $installDir -Recurse -Filter 'd2j-dex2jar.sh' | Select-Object -First 1
    }
    if (-not $d2jBat) {
        Write-Fail "Could not find d2j-dex2jar in extracted archive."
        Write-Manual "Download and extract manually from https://github.com/ThexXTURBOXx/dex2jar/releases"
    }

    $binDir = $d2jBat.DirectoryName
    Add-ToUserPath $binDir

    Write-Ok "dex2jar $version installed to $installDir"
}

function Install-Apktool {
    if (Get-Command apktool -ErrorAction SilentlyContinue) {
        Write-Ok "apktool already installed"
        return
    }

    if ($hasScoop) {
        Write-Info "Installing apktool via scoop..."
        scoop install apktool
    } elseif ($hasChoco) {
        Write-Info "Installing apktool via choco..."
        choco install apktool -y
    } else {
        Write-Manual "Install apktool from https://apktool.org/docs/install"
    }

    if (Get-Command apktool -ErrorAction SilentlyContinue) {
        Write-Ok "apktool installed"
    } else {
        Write-Fail "apktool installation may have failed."
        exit 1
    }
}

# APKEditor (REAndroid, Apache-2.0): pinned release, verified by SHA-256.
# Keep in sync with APKEDITOR_VERSION / APKEDITOR_SHA256 in install-dep.sh.
$ApkEditorVersion = '1.4.9'
$ApkEditorSha256  = 'a9cd40df818845456be6d696de6110c89edf4b0a0580cb83438ed6b25a366e67'

function Install-ApkEditor {
    if ($env:APKEDITOR_JAR) {
        if (Test-Path -LiteralPath $env:APKEDITOR_JAR) {
            Write-Ok "APKEditor JAR provided via APKEDITOR_JAR: $env:APKEDITOR_JAR"
            return
        }
        Write-Fail "APKEDITOR_JAR is set but the file does not exist: $env:APKEDITOR_JAR"
        exit 1
    }

    $installDir = Join-Path $localShare 'apkeditor'
    $jar = Join-Path $installDir 'APKEditor.jar'
    $url = "https://github.com/REAndroid/APKEditor/releases/download/V$ApkEditorVersion/APKEditor-$ApkEditorVersion.jar"

    $installed = $false
    if (Test-Path -LiteralPath $jar) {
        if ((Get-FileHash -LiteralPath $jar -Algorithm SHA256).Hash -eq $ApkEditorSha256) {
            Write-Ok "APKEditor $ApkEditorVersion already installed: $jar"
            $installed = $true
        }
    }

    if (-not $installed) {
        Write-Info "Installing APKEditor $ApkEditorVersion from GitHub releases..."
        New-Item -ItemType Directory -Path $installDir -Force | Out-Null
        $tmpJar = Join-Path $env:TEMP "apkeditor-$(Get-Random).jar"
        $oldProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'   # PS 5.1 download is very slow with the progress bar
        $verified = $false
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Invoke-Download -Url $url -Dest $tmpJar
                $actual = (Get-FileHash -LiteralPath $tmpJar -Algorithm SHA256).Hash
                if ($actual -eq $ApkEditorSha256) { $verified = $true; break }
                Write-Fail "SHA-256 mismatch for APKEditor-$ApkEditorVersion.jar (expected $ApkEditorSha256, got $actual)"
            } catch {
                Write-Fail "Download failed: $($_.Exception.Message)"
            }
            if ($attempt -lt 3) {
                Write-Info "Retrying download (attempt $($attempt + 1)/3)..."
                Start-Sleep -Seconds 2
            }
        }
        $ProgressPreference = $oldProgress
        if (-not $verified) {
            Remove-Item -LiteralPath $tmpJar -Force -ErrorAction SilentlyContinue
            Write-Fail "Could not download a verified APKEditor $ApkEditorVersion JAR."
            Write-Manual "Download $url, check its SHA-256 is $ApkEditorSha256, then save it as $jar (or set APKEDITOR_JAR)"
        }
        Move-Item -LiteralPath $tmpJar -Destination $jar -Force
        Write-Ok "APKEditor $ApkEditorVersion installed to $jar (SHA-256 verified)"
    }

    # Launcher (honours APKEDITOR_JAR at run time)
    New-Item -ItemType Directory -Path $localBin -Force | Out-Null
    $wrapperPath = Join-Path $localBin 'apkeditor.cmd'
    $wrapper = "@echo off`r`nif defined APKEDITOR_JAR (`r`n  java -jar `"%APKEDITOR_JAR%`" %*`r`n) else (`r`n  java -jar `"$jar`" %*`r`n)"
    Set-Content -Path $wrapperPath -Value $wrapper -Encoding ASCII

    Add-ToUserPath $localBin
}

# Android SDK Build-Tools - pinned official package from dl.google.com.
# SHA-256 computed from the archive whose SHA-1 (f16ccffd34de8790dede813a6c7d8e2c11a27b50)
# matches Google's repository XML (https://dl.google.com/android/repository/repository2-3.xml).
# Keep in sync with BUILD_TOOLS_* in install-dep.sh.
$BuildToolsVersion = '36.0.0'
$BuildToolsArchive = 'build-tools_r36_windows.zip'
$BuildToolsSha256  = 'aa1095cb14d83e483818a748a2c06faaeb8e601561b06a356a119a1b2ca280d3'
$AndroidSdkLicenseUrl = 'https://developer.android.com/studio/terms'

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

function Test-ZipalignHasP {
    param([string]$Exe)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = (& $Exe 2>&1 | ForEach-Object { "$_" }) -join "`n" } catch { $out = '' }
    finally { $ErrorActionPreference = $prev }
    return ($out -match '-P <pagesize')
}

function Install-BuildTools {
    $sdkRoots = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'), (Join-Path $localShare 'android-sdk'))
    foreach ($sdk in $sdkRoots) {
        $bt = Get-LatestBuildToolsDir $sdk
        if ($bt -and (Test-Path -LiteralPath (Join-Path $bt 'zipalign.exe')) -and (Test-Path -LiteralPath (Join-Path $bt 'apksigner.bat')) -and (Test-ZipalignHasP (Join-Path $bt 'zipalign.exe'))) {
            Write-Ok "Android build-tools with zipalign -P and apksigner already installed: $bt"
            return
        }
    }

    Write-Host ""
    Write-Host "[LICENSE] Android SDK Build-Tools $BuildToolsVersion are distributed by Google under the" -ForegroundColor Yellow
    Write-Host "          Android Software Development Kit License Agreement:" -ForegroundColor Yellow
    Write-Host "            $AndroidSdkLicenseUrl" -ForegroundColor Yellow
    Write-Host "          Read it before installing. To accept it and install, re-run with" -ForegroundColor Yellow
    Write-Host "            install-dep.ps1 build-tools -AcceptAndroidSdkLicense" -ForegroundColor Yellow
    Write-Host "          (or set ACCEPT_ANDROID_SDK_LICENSE=1)." -ForegroundColor Yellow
    Write-Host ""
    if (-not ($AcceptAndroidSdkLicense -or $env:ACCEPT_ANDROID_SDK_LICENSE -eq '1')) {
        Write-Fail "Android SDK license not accepted - build-tools not installed."
        exit 2
    }
    Write-Info "Android SDK license accepted via -AcceptAndroidSdkLicense / ACCEPT_ANDROID_SDK_LICENSE=1"

    # Prefer sdkmanager when an SDK root is configured
    $sdkRoot = $env:ANDROID_HOME
    if (-not $sdkRoot) { $sdkRoot = $env:ANDROID_SDK_ROOT }
    if ($sdkRoot) {
        $sdkm = Join-Path $sdkRoot 'cmdline-tools\latest\bin\sdkmanager.bat'
        if (-not (Test-Path -LiteralPath $sdkm)) {
            $c = Get-Command sdkmanager -ErrorAction SilentlyContinue
            if ($c) { $sdkm = $c.Source } else { $sdkm = $null }
        }
        if ($sdkm) {
            Write-Info "Installing build-tools;$BuildToolsVersion with sdkmanager into $sdkRoot..."
            $prev = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try { (@('y') * 20) | & $sdkm "--sdk_root=$sdkRoot" --install "build-tools;$BuildToolsVersion" 2>&1 | ForEach-Object { Write-Host "$_" } }
            finally { $ErrorActionPreference = $prev }
            if (Test-Path -LiteralPath (Join-Path $sdkRoot "build-tools\$BuildToolsVersion\zipalign.exe")) {
                Write-Ok "build-tools $BuildToolsVersion installed with sdkmanager: $sdkRoot\build-tools\$BuildToolsVersion"
                return
            }
            Write-Info "sdkmanager did not install build-tools - falling back to direct download."
        }
    }

    $url = "https://dl.google.com/android/repository/$BuildToolsArchive"
    $tmpDir = Join-Path $env:TEMP "build-tools-$(Get-Random)"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $tmpZip = Join-Path $tmpDir 'bt.zip'
    $oldProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    $verified = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-Download -Url $url -Dest $tmpZip
            $actual = (Get-FileHash -LiteralPath $tmpZip -Algorithm SHA256).Hash
            if ($actual -eq $BuildToolsSha256) { $verified = $true; break }
            Write-Fail "SHA-256 mismatch for $BuildToolsArchive (expected $BuildToolsSha256, got $actual)"
        } catch {
            Write-Fail "Download failed: $($_.Exception.Message)"
        }
        if ($attempt -lt 3) { Write-Info "Retrying download (attempt $($attempt + 1)/3)..."; Start-Sleep -Seconds 2 }
    }
    $ProgressPreference = $oldProgress
    if (-not $verified) {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Fail "Could not download a verified build-tools $BuildToolsVersion archive."
        Write-Manual "Install it with Android Studio's SDK Manager, or download $url (SHA-256 $BuildToolsSha256) and extract it to $localShare\android-sdk\build-tools\$BuildToolsVersion"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $xDir = Join-Path $tmpDir 'x'
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tmpZip, $xDir)
    $top = Get-ChildItem -LiteralPath $xDir -Directory | Select-Object -First 1
    if (-not $top -or -not (Test-Path -LiteralPath (Join-Path $top.FullName 'zipalign.exe'))) {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Fail "Unexpected build-tools archive layout."
        exit 1
    }
    $dest = Join-Path $localShare "android-sdk\build-tools\$BuildToolsVersion"
    New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    Move-Item -LiteralPath $top.FullName -Destination $dest
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

    Add-ToUserPath $dest
    if (Test-ZipalignHasP (Join-Path $dest 'zipalign.exe')) {
        Write-Ok "Android build-tools $BuildToolsVersion installed to $dest (SHA-256 verified)"
    } else {
        Write-Fail "build-tools installed to $dest but its zipalign does not run on this system."
        exit 1
    }
}

function Install-NeutralizeAll {
    Write-Host "=== Installing all SDK Neutralizer dependencies ==="
    $failed = @()
    $needsLicense = $false
    foreach ($d in @('java', 'apktool', 'apkeditor', 'build-tools')) {
        Write-Info "--- $d ---"
        # A child invocation, so one dependency's 'exit' does not stop the others
        if ($AcceptAndroidSdkLicense) { & $SelfScript $d -AcceptAndroidSdkLicense } else { & $SelfScript $d }
        if ($LASTEXITCODE -ne 0) {
            $failed += "$d (exit $LASTEXITCODE)"
            if ($d -eq 'build-tools' -and $LASTEXITCODE -eq 2) { $needsLicense = $true }
        }
        Write-Host ""
    }
    if ($failed.Count -gt 0) {
        Write-Fail "Failed to install: $($failed -join ', ')"
        # Same as install-dep.sh: only the Android SDK license missing = manual action (2)
        if ($needsLicense -and $failed.Count -eq 1) { exit 2 }
        exit 1
    }
    Write-Ok "All SDK Neutralizer dependencies installed."
}

function Install-Adb {
    if (Get-Command adb -ErrorAction SilentlyContinue) {
        Write-Ok "adb already installed"
        return
    }

    if ($hasScoop) {
        Write-Info "Installing adb via scoop..."
        scoop install adb
    } elseif ($hasChoco) {
        Write-Info "Installing adb via choco..."
        choco install adb -y
    } elseif ($hasWinget) {
        Write-Info "Installing via winget..."
        winget install Google.PlatformTools --accept-source-agreements --accept-package-agreements
    } else {
        Write-Manual "Install Android SDK Platform Tools from https://developer.android.com/tools/releases/platform-tools"
    }

    if (Get-Command adb -ErrorAction SilentlyContinue) {
        Write-Ok "adb installed"
    } else {
        Write-Fail "adb installation may have failed."
        exit 1
    }
}

# =====================================================================
# Dispatch
# =====================================================================

switch ($Dep) {
    'java'        { Install-Java }
    'jadx'        { Install-Jadx }
    'vineflower'  { Install-Vineflower }
    'fernflower'  { Install-Vineflower }
    'dex2jar'     { Install-Dex2Jar }
    'apktool'     { Install-Apktool }
    'apkeditor'   { Install-ApkEditor }
    'build-tools' { Install-BuildTools }
    'buildtools'  { Install-BuildTools }
    'zipalign'    { Install-BuildTools }
    'neutralize-all' { Install-NeutralizeAll }
    'adb'         { Install-Adb }
    default {
        Write-Host "Error: Unknown dependency '$Dep'" -ForegroundColor Red
        Write-Host "Available: java, jadx, vineflower, dex2jar, apktool, apkeditor, build-tools, adb"
        Write-Host "Compound: neutralize-all"
        exit 1
    }
}

} finally {
    if ($script:CallerOutputEncoding) {
        try { [Console]::OutputEncoding = $script:CallerOutputEncoding } catch { }
    }
}
