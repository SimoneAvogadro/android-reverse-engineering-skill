# install-dep.ps1 — Install a single dependency for Android reverse engineering
# Usage: install-dep.ps1 <dependency>
# Dependencies: java, jadx, vineflower, dex2jar, apktool, adb
#
# Exit codes:
#   0 — installed successfully
#   1 — installation failed
#   2 — requires manual action
param(
    [Parameter(Position=0)]
    [string]$Dep
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    Write-Host @"
Usage: install-dep.ps1 <dependency>

Install a dependency required for Android reverse engineering.

Available dependencies:
  java         Java JDK 17+
  jadx         jadx decompiler
  vineflower   Vineflower (Fernflower fork) decompiler
  dex2jar      DEX to JAR converter
  apktool      Android resource decoder
  adb          Android Debug Bridge

The script detects available package managers (winget, scoop, choco), then:
  - Installs using the first available manager
  - Falls back to direct download to %USERPROFILE%\.local\share\
  - Prints manual instructions if no option works
"@
    exit 0
}

if (-not $Dep -or $Dep -eq '-h' -or $Dep -eq '--help') { Show-Usage }

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
    $tag = try { Get-GHLatestTag "pxb1988/dex2jar" } catch { "v2.4" }
    if (-not $tag) { $tag = "v2.4" }

    $version = $tag -replace '^v', ''
    $url = "https://github.com/pxb1988/dex2jar/releases/download/$tag/dex-tools-v$version.zip"
    $tmpZip = Join-Path $env:TEMP "dex2jar-$version.zip"

    try {
        Invoke-Download -Url $url -Dest $tmpZip
    } catch {
        $url = "https://github.com/pxb1988/dex2jar/releases/download/$tag/dex-tools-$version.zip"
        try {
            Invoke-Download -Url $url -Dest $tmpZip
        } catch {
            Write-Fail "Download failed."
            Write-Manual "Download from https://github.com/pxb1988/dex2jar/releases/latest"
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
        Write-Manual "Download and extract manually from https://github.com/pxb1988/dex2jar/releases"
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
    'adb'         { Install-Adb }
    default {
        Write-Host "Error: Unknown dependency '$Dep'" -ForegroundColor Red
        Write-Host "Available: java, jadx, vineflower, dex2jar, apktool, adb"
        exit 1
    }
}
