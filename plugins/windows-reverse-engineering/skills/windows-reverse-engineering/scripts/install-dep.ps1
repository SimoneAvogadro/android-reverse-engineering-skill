# install-dep.ps1 — Install a single dependency for Windows reverse engineering
# Usage: install-dep.ps1 <dependency>
# Dependencies: java, ghidra, ilspycmd, strings, dumpbin, de4dot, dotnet-sdk
#
# Exit codes:
#   0 — installed successfully
#   1 — installation failed
#   2 — requires manual action (e.g. admin needed but not available)

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Dependency
)

$ErrorActionPreference = 'Stop'

# --- Detect environment ---
$HasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
$HasChoco = $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
$HasDotnet = $null -ne (Get-Command dotnet -ErrorAction SilentlyContinue)
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" }
function Write-Ok { param([string]$Message) Write-Host "[OK] $Message" }
function Write-Fail { param([string]$Message) Write-Host "[FAIL] $Message" -ForegroundColor Red }
function Write-Manual {
    param([string]$Message)
    Write-Host "[MANUAL] $Message" -ForegroundColor Yellow
    Write-Host "         Cannot install automatically. Please install manually and retry." -ForegroundColor Yellow
    exit 2
}

function Get-GithubLatestTag {
    param([string]$Repo)
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -UseBasicParsing
        return $release.tag_name
    } catch {
        return $null
    }
}

function Download-File {
    param([string]$Url, [string]$Dest)
    Write-Info "Downloading from $Url..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
    } catch {
        Write-Fail "Download failed: $_"
        return $false
    }
    return $true
}

function Add-ToUserPath {
    param([string]$Dir)
    $currentPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($currentPath -notlike "*$Dir*") {
        [System.Environment]::SetEnvironmentVariable('PATH', "$currentPath;$Dir", 'User')
        $env:PATH = "$env:PATH;$Dir"
        Write-Info "Added $Dir to user PATH. Restart your terminal for full effect."
    }
}

# =====================================================================
# Dependency installers
# =====================================================================

function Install-Java {
    $javaCmdExists = Get-Command java -ErrorAction SilentlyContinue
    if ($javaCmdExists) {
        $javaVersionOutput = & java -version 2>&1 | Select-Object -First 1
        if ([string]$javaVersionOutput -match '"(\d+)') {
            $ver = [int]$Matches[1]
            if ($ver -ge 17) {
                Write-Ok "Java $ver already installed"
                return
            }
        }
    }

    Write-Info "Installing Java JDK 17+..."

    if ($HasWinget) {
        Write-Info "Installing via winget..."
        & winget install Microsoft.OpenJDK.17 --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Java 17 installed via winget"
            return
        }
        Write-Info "winget failed, trying alternatives..."
    }

    if ($HasChoco) {
        Write-Info "Installing via Chocolatey..."
        & choco install openjdk17 -y
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Java 17 installed via Chocolatey"
            return
        }
    }

    Write-Manual "Install Java JDK 17+ from https://adoptium.net/temurin/releases/?version=17"
}

function Install-Ghidra {
    # Check if already available
    $ghidraDir = $env:GHIDRA_INSTALL_DIR
    if ($ghidraDir -and (Test-Path "$ghidraDir\support\analyzeHeadless.bat")) {
        Write-Ok "Ghidra already installed at $ghidraDir"
        return
    }

    if ($HasChoco) {
        Write-Info "Installing Ghidra via Chocolatey..."
        & choco install ghidra -y
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Ghidra installed via Chocolatey"
            Write-Info "Set GHIDRA_INSTALL_DIR to the Ghidra installation directory."
            return
        }
        Write-Info "Chocolatey install failed, trying direct download..."
    }

    # Direct download from GitHub
    Write-Info "Installing Ghidra from GitHub releases..."
    $tag = Get-GithubLatestTag "NationalSecurityAgency/ghidra"
    if (-not $tag) {
        Write-Manual "Could not determine latest Ghidra version. Download from https://github.com/NationalSecurityAgency/ghidra/releases/latest"
    }

    $version = $tag -replace '^Ghidra_', '' -replace '_build$', ''

    # Try to find the download URL from the release assets
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest" -UseBasicParsing
        $asset = $release.assets | Where-Object { $_.name -like "ghidra_*_PUBLIC_*.zip" } | Select-Object -First 1
        if (-not $asset) {
            Write-Manual "Could not find Ghidra download. Download from https://github.com/NationalSecurityAgency/ghidra/releases/latest"
        }
        $downloadUrl = $asset.browser_download_url
    } catch {
        Write-Manual "Could not access GitHub API. Download Ghidra from https://github.com/NationalSecurityAgency/ghidra/releases/latest"
    }

    $installDir = "$env:USERPROFILE\.local\share\ghidra"
    $tmpZip = "$env:TEMP\ghidra-download.zip"

    if (-not (Download-File -Url $downloadUrl -Dest $tmpZip)) {
        Write-Manual "Download failed. Download manually from $downloadUrl"
    }

    Write-Info "Extracting Ghidra..."
    if (Test-Path $installDir) { Remove-Item -Recurse -Force $installDir }
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $installDir -Force
    Remove-Item $tmpZip -Force

    # Find the actual Ghidra directory inside the extracted archive
    $ghidraSubDir = Get-ChildItem -Path $installDir -Directory -Filter "ghidra_*" | Select-Object -First 1
    if ($ghidraSubDir) {
        $ghidraPath = $ghidraSubDir.FullName
    } else {
        $ghidraPath = $installDir
    }

    # Set environment variable
    [System.Environment]::SetEnvironmentVariable('GHIDRA_INSTALL_DIR', $ghidraPath, 'User')
    $env:GHIDRA_INSTALL_DIR = $ghidraPath

    Write-Ok "Ghidra installed to $ghidraPath"
    Write-Info "GHIDRA_INSTALL_DIR set to $ghidraPath"
    Write-Info "Restart your terminal for the environment variable to take effect."
}

function Install-IlspyCmd {
    if (Get-Command ilspycmd -ErrorAction SilentlyContinue) {
        Write-Ok "ilspycmd already installed"
        return
    }

    if (-not $HasDotnet) {
        Write-Info ".NET SDK not found. Installing .NET SDK first..."
        Install-DotnetSdk
        # Re-check
        $HasDotnet = $null -ne (Get-Command dotnet -ErrorAction SilentlyContinue)
        if (-not $HasDotnet) {
            Write-Fail ".NET SDK installation failed. Cannot install ilspycmd."
            Write-Manual "Install .NET SDK from https://dotnet.microsoft.com/ then run: dotnet tool install -g ilspycmd"
        }
    }

    Write-Info "Installing ilspycmd via dotnet tool..."
    & dotnet tool install -g ilspycmd
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "ilspycmd installed"
    } else {
        # May already be installed but older version
        & dotnet tool update -g ilspycmd
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "ilspycmd updated"
        } else {
            Write-Fail "ilspycmd installation failed."
            exit 1
        }
    }
}

function Install-DotnetSdk {
    if ($HasDotnet) {
        $ver = & dotnet --version 2>$null
        Write-Ok ".NET SDK $ver already installed"
        return
    }

    Write-Info "Installing .NET SDK..."

    if ($HasWinget) {
        Write-Info "Installing via winget..."
        & winget install Microsoft.DotNet.SDK.8 --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Ok ".NET SDK installed via winget"
            return
        }
    }

    if ($HasChoco) {
        Write-Info "Installing via Chocolatey..."
        & choco install dotnet-sdk -y
        if ($LASTEXITCODE -eq 0) {
            Write-Ok ".NET SDK installed via Chocolatey"
            return
        }
    }

    Write-Manual "Install .NET SDK from https://dotnet.microsoft.com/download"
}

function Install-Strings {
    if (Get-Command strings2 -ErrorAction SilentlyContinue) {
        Write-Ok "strings2 already installed"
        return
    }
    if (Get-Command strings -ErrorAction SilentlyContinue) {
        Write-Ok "strings (SysInternals) already installed"
        return
    }

    # Try winget for SysInternals strings
    if ($HasWinget) {
        Write-Info "Installing SysInternals Strings via winget..."
        & winget install Microsoft.Sysinternals.Strings --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "SysInternals Strings installed via winget"
            return
        }
    }

    # Direct download strings2
    Write-Info "Installing strings2 from GitHub..."
    $tag = Get-GithubLatestTag "glmcdona/strings2"
    if (-not $tag) {
        $tag = "v2.0.0"
    }

    $installDir = "$env:USERPROFILE\.local\share\strings2"
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null

    $downloadUrl = "https://github.com/glmcdona/strings2/releases/download/$tag/strings2.exe"
    if (Download-File -Url $downloadUrl -Dest "$installDir\strings2.exe") {
        $binDir = "$env:USERPROFILE\.local\bin"
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        Copy-Item "$installDir\strings2.exe" "$binDir\strings2.exe" -Force
        Add-ToUserPath $binDir
        Write-Ok "strings2 installed to $binDir"
    } else {
        Write-Manual "Download strings2 from https://github.com/glmcdona/strings2/releases"
    }
}

function Install-Dumpbin {
    if (Get-Command dumpbin -ErrorAction SilentlyContinue) {
        Write-Ok "dumpbin already installed"
        return
    }

    Write-Host ""
    Write-Host "[INFO] dumpbin requires Visual Studio C++ Build Tools." -ForegroundColor Yellow
    Write-Host "[INFO] This is a large download (~2-4 GB) and requires admin privileges." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To install:" -ForegroundColor Cyan
    Write-Host "  1. Download from: https://visualstudio.microsoft.com/visual-cpp-build-tools/" -ForegroundColor Cyan
    Write-Host "  2. In the installer, select 'Desktop development with C++'" -ForegroundColor Cyan
    Write-Host "  3. After installation, use 'Developer Command Prompt' or 'Developer PowerShell' for dumpbin access" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Alternatively, Ghidra can extract the same PE information (imports, exports, headers)." -ForegroundColor Green
    Write-Host ""
    exit 2
}

function Install-De4dot {
    if (Get-Command de4dot -ErrorAction SilentlyContinue) {
        Write-Ok "de4dot already installed"
        return
    }

    Write-Info "Installing de4dot from GitHub..."
    $tag = Get-GithubLatestTag "de4dot/de4dot"

    if (-not $tag) {
        Write-Manual "Could not determine latest de4dot version. Download from https://github.com/de4dot/de4dot/releases"
    }

    $installDir = "$env:USERPROFILE\.local\share\de4dot"
    $tmpZip = "$env:TEMP\de4dot-download.zip"

    # Find the appropriate asset
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/de4dot/de4dot/releases/latest" -UseBasicParsing
        $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
        if (-not $asset) {
            Write-Manual "Could not find de4dot download. Download from https://github.com/de4dot/de4dot/releases"
        }
        $downloadUrl = $asset.browser_download_url
    } catch {
        Write-Manual "Could not access GitHub API. Download de4dot from https://github.com/de4dot/de4dot/releases"
    }

    if (-not (Download-File -Url $downloadUrl -Dest $tmpZip)) {
        Write-Manual "Download failed. Download manually from $downloadUrl"
    }

    if (Test-Path $installDir) { Remove-Item -Recurse -Force $installDir }
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Expand-Archive -Path $tmpZip -DestinationPath $installDir -Force
    Remove-Item $tmpZip -Force

    # Find de4dot.exe
    $de4dotExe = Get-ChildItem -Path $installDir -Recurse -Filter "de4dot.exe" | Select-Object -First 1
    if ($de4dotExe) {
        $binDir = "$env:USERPROFILE\.local\bin"
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        Copy-Item $de4dotExe.FullName "$binDir\de4dot.exe" -Force
        Add-ToUserPath $binDir
        Write-Ok "de4dot installed to $binDir"
    } else {
        Write-Fail "Could not find de4dot.exe in extracted archive."
        Write-Manual "Download and extract manually from https://github.com/de4dot/de4dot/releases"
    }
}

# =====================================================================
# Dispatch
# =====================================================================

switch ($Dependency.ToLower()) {
    'java'       { Install-Java }
    'ghidra'     { Install-Ghidra }
    'ilspycmd'   { Install-IlspyCmd }
    'dotnet-sdk' { Install-DotnetSdk }
    'strings'    { Install-Strings }
    'dumpbin'    { Install-Dumpbin }
    'de4dot'     { Install-De4dot }
    default {
        Write-Host "Error: Unknown dependency '$Dependency'" -ForegroundColor Red
        Write-Host "Available: java, ghidra, ilspycmd, dotnet-sdk, strings, dumpbin, de4dot"
        exit 1
    }
}
