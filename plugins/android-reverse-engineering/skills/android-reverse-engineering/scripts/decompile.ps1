# decompile.ps1 — Decompile APK/XAPK/JAR/AAR using jadx, fernflower, or both
param(
    [Alias('o')]
    [string]$Output,
    [switch]$Deobf,
    [switch]$NoRes,
    [string]$Engine = 'jadx',
    [Parameter(Position=0)]
    [string]$InputFile,
    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# Refresh PATH from user environment so we pick up tools installed in the same session
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath) {
    foreach ($dir in $userPath -split ';') {
        if ($dir -and $env:PATH -notlike "*$dir*") {
            $env:PATH = "$dir;$env:PATH"
        }
    }
}

function Show-Usage {
    Write-Host @"
Usage: decompile.ps1 [OPTIONS] <file>

Decompile an Android APK, XAPK, JAR, or AAR file.

Arguments:
  <file>            Path to the .apk, .xapk, .jar, or .aar file

Options:
  -Output DIR       Output directory (default: <filename>-decompiled)
  -Deobf            Enable deobfuscation of names
  -NoRes            Skip resource decoding (faster, code-only)
  -Engine ENGINE    Decompiler engine: jadx, fernflower, or both (default: jadx)
  -Help             Show this help message

Engines:
  jadx        Use jadx (default). Handles APK/JAR/AAR natively, decodes resources.
  fernflower  Use Fernflower/Vineflower. Better on complex Java, lambdas, generics.
              For APK files, requires dex2jar as intermediate step.
  both        Run both decompilers side by side for comparison.
              jadx output  -> <output>/jadx/
              fernflower   -> <output>/fernflower/

Environment:
  FERNFLOWER_JAR_PATH   Path to fernflower.jar or vineflower.jar

Examples:
  .\decompile.ps1 app-release.apk
  .\decompile.ps1 app-bundle.xapk
  .\decompile.ps1 -Engine both -Deobf app-release.apk
  .\decompile.ps1 -Engine fernflower library.jar
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

$extLower = [IO.Path]::GetExtension($InputFile).TrimStart('.').ToLower()
if ($extLower -notin @('apk', 'xapk', 'jar', 'aar')) {
    Write-Host "Error: Unsupported file type '.$extLower'. Expected .apk, .xapk, .jar, or .aar" -ForegroundColor Red
    exit 1
}

if ($Engine -notin @('jadx', 'fernflower', 'both')) {
    Write-Host "Error: Unknown engine '$Engine'. Use jadx, fernflower, or both." -ForegroundColor Red
    exit 1
}

$baseName = [IO.Path]::GetFileNameWithoutExtension($InputFile)
$inputFileAbs = (Resolve-Path $InputFile).Path

if (-not $Output) {
    $Output = "$baseName-decompiled"
}

# --- XAPK handling ---
$xapkExtractedDir = $null
$xapkApkFiles = @()

if ($extLower -eq 'xapk') {
    $xapkExtractedDir = Join-Path $env:TEMP "xapk-extract-$(Get-Random)"
    Write-Host "=== Extracting XAPK archive ==="
    New-Item -ItemType Directory -Path $xapkExtractedDir -Force | Out-Null
    Expand-Archive -Path $inputFileAbs -DestinationPath $xapkExtractedDir -Force

    # Show manifest.json if present
    $manifestPath = Join-Path $xapkExtractedDir 'manifest.json'
    if (Test-Path $manifestPath) {
        Write-Host "XAPK manifest found:"
        Get-Content $manifestPath
        Write-Host ""
    }

    # Find all APK files inside
    $xapkApkFiles = Get-ChildItem -Path $xapkExtractedDir -Recurse -Filter '*.apk' | Sort-Object Name

    if ($xapkApkFiles.Count -eq 0) {
        Write-Host "Error: No APK files found inside XAPK archive." -ForegroundColor Red
        Remove-Item $xapkExtractedDir -Recurse -Force
        exit 1
    }

    Write-Host "Found $($xapkApkFiles.Count) APK(s) inside XAPK:"
    foreach ($f in $xapkApkFiles) {
        Write-Host "  - $($f.Name)"
    }
    Write-Host ""
}

# --- Locate fernflower JAR ---
function Find-FernflowerJar {
    if ($env:FERNFLOWER_JAR_PATH -and (Test-Path $env:FERNFLOWER_JAR_PATH -ErrorAction SilentlyContinue)) {
        return $env:FERNFLOWER_JAR_PATH
    }
    $candidates = @(
        "$env:USERPROFILE\.local\share\vineflower\vineflower.jar",
        "$env:USERPROFILE\fernflower\build\libs\fernflower.jar",
        "$env:USERPROFILE\vineflower\build\libs\vineflower.jar",
        "$env:USERPROFILE\fernflower\fernflower.jar",
        "$env:USERPROFILE\vineflower\vineflower.jar"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c -ErrorAction SilentlyContinue) { return $c }
    }
    return $null
}

# --- Locate dex2jar ---
function Find-Dex2Jar {
    $cmd = Get-Command d2j-dex2jar -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command d2j-dex2jar.bat -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# --- jadx decompilation ---
function Invoke-Jadx {
    param([string]$OutDir, [string]$FileAbs, [string]$FileExt)

    if (-not (Get-Command jadx -ErrorAction SilentlyContinue)) {
        Write-Host "Error: jadx is not installed or not in PATH." -ForegroundColor Red
        return $false
    }

    $jadxArgs = @('-d', $OutDir)
    if ($Deobf) { $jadxArgs += '--deobf' }
    if ($NoRes) { $jadxArgs += '--no-res' }
    $jadxArgs += '--show-bad-code'
    $jadxArgs += $FileAbs

    Write-Host "Running: jadx $($jadxArgs -join ' ')"
    & jadx @jadxArgs

    $sourcesDir = Join-Path $OutDir 'sources'
    if (Test-Path $sourcesDir) {
        $count = (Get-ChildItem -Path $sourcesDir -Recurse -Filter '*.java').Count
        Write-Host "jadx output: $sourcesDir\"
        Write-Host "Java files decompiled by jadx: $count"
    }
    return $true
}

# --- Fernflower decompilation ---
function Invoke-Fernflower {
    param([string]$OutDir, [string]$FileAbs, [string]$FileExt)

    $ffJar = Find-FernflowerJar
    if (-not $ffJar) {
        Write-Host "Error: Fernflower/Vineflower JAR not found." -ForegroundColor Red
        Write-Host "Set FERNFLOWER_JAR_PATH or see references/setup-guide.md"
        return $false
    }

    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

    $jarToDecompile = $FileAbs
    $convertedJar = $null

    # For APK/AAR, we need dex2jar first
    if ($FileExt -in @('apk', 'aar')) {
        $d2j = Find-Dex2Jar
        if (-not $d2j) {
            Write-Host "Error: dex2jar is required to use Fernflower on .$FileExt files." -ForegroundColor Red
            Write-Host "Install dex2jar - see references/setup-guide.md"
            return $false
        }

        Write-Host "Converting $FileExt to JAR with dex2jar..."
        $convertedJar = Join-Path $OutDir "$baseName-dex2jar.jar"
        & $d2j -f -o $convertedJar $FileAbs 2>&1 | Write-Host
        if (-not (Test-Path $convertedJar)) {
            Write-Host "Error: dex2jar conversion failed." -ForegroundColor Red
            return $false
        }
        $jarToDecompile = $convertedJar
    }

    # Build fernflower args
    $ffArgs = @('-dgs=1', '-mpm=60')
    if ($Deobf) { $ffArgs += '-ren=1' }
    $ffArgs += $jarToDecompile
    $ffArgs += $OutDir

    Write-Host "Running: java -jar $ffJar $($ffArgs -join ' ')"
    & java -jar $ffJar @ffArgs

    # Fernflower outputs a JAR containing .java files — extract it
    $resultJar = Join-Path $OutDir ([IO.Path]::GetFileName($jarToDecompile))
    if (Test-Path $resultJar) {
        $sourcesDir = Join-Path $OutDir 'sources'
        New-Item -ItemType Directory -Path $sourcesDir -Force | Out-Null
        Expand-Archive -Path $resultJar -DestinationPath $sourcesDir -Force
        Remove-Item $resultJar -Force
        $count = (Get-ChildItem -Path $sourcesDir -Recurse -Filter '*.java').Count
        Write-Host "Fernflower output: $sourcesDir\"
        Write-Host "Java files decompiled by Fernflower: $count"
    }

    # Clean up intermediate dex2jar output
    if ($convertedJar -and (Test-Path $convertedJar -ErrorAction SilentlyContinue)) {
        Remove-Item $convertedJar -Force
    }
    return $true
}

# --- Summary helper ---
function Show-Structure {
    param([string]$SrcDir, [string]$Label)
    if (Test-Path $SrcDir) {
        Write-Host ""
        Write-Host "Top-level packages ($Label):"
        Get-ChildItem -Path $SrcDir -Directory -Recurse -Depth 2 |
            Select-Object -First 20 |
            ForEach-Object { $_.FullName.Replace("$SrcDir\", '') } |
            Sort-Object
    }
}

# --- Decompile a single file ---
function Invoke-DecompileSingle {
    param([string]$FileAbs, [string]$OutDir, [string]$Label)

    $fileExt = [IO.Path]::GetExtension($FileAbs).TrimStart('.').ToLower()

    if ($Label) {
        Write-Host "=== Decompiling $Label (engine: $Engine) ==="
    }

    switch ($Engine) {
        'jadx' {
            Invoke-Jadx -OutDir $OutDir -FileAbs $FileAbs -FileExt $fileExt
            Show-Structure (Join-Path $OutDir 'sources') 'jadx'
        }
        'fernflower' {
            Invoke-Fernflower -OutDir $OutDir -FileAbs $FileAbs -FileExt $fileExt
            Show-Structure (Join-Path $OutDir 'sources') 'fernflower'
        }
        'both' {
            Write-Host "--- Pass 1: jadx ---"
            Invoke-Jadx -OutDir (Join-Path $OutDir 'jadx') -FileAbs $FileAbs -FileExt $fileExt
            Write-Host ""
            Write-Host "--- Pass 2: Fernflower ---"
            Invoke-Fernflower -OutDir (Join-Path $OutDir 'fernflower') -FileAbs $FileAbs -FileExt $fileExt

            Show-Structure (Join-Path $OutDir 'jadx\sources') 'jadx'
            Show-Structure (Join-Path $OutDir 'fernflower\sources') 'fernflower'

            Write-Host ""
            Write-Host "=== Comparison ==="
            $jadxCount = 0; $ffCount = 0
            $jadxSources = Join-Path $OutDir 'jadx\sources'
            $ffSources   = Join-Path $OutDir 'fernflower\sources'
            if (Test-Path $jadxSources) {
                $jadxCount = (Get-ChildItem -Path $jadxSources -Recurse -Filter '*.java').Count
            }
            if (Test-Path $ffSources) {
                $ffCount = (Get-ChildItem -Path $ffSources -Recurse -Filter '*.java').Count
            }
            Write-Host "jadx:        $jadxCount Java files"
            Write-Host "Fernflower:  $ffCount Java files"

            if (Test-Path $jadxSources) {
                $jadxErrors = (Get-ChildItem -Path $jadxSources -Recurse -Filter '*.java' -File |
                    Select-String -Pattern 'JADX WARNING|JADX WARN|JADX ERROR|Code decompiled incorrectly' -SimpleMatch -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty Path -Unique).Count
                Write-Host "jadx files with warnings/errors: $jadxErrors"
            }
            Write-Host ""
            Write-Host "Tip: compare specific classes between jadx/ and fernflower/ to pick the better output."
        }
    }
}

# --- Run ---
Write-Host "=== Decompiling $InputFile (engine: $Engine) ==="
Write-Host "Output directory: $Output"
Write-Host ""

if ($extLower -eq 'xapk') {
    New-Item -ItemType Directory -Path $Output -Force | Out-Null

    # Copy XAPK manifest for reference
    $manifestSrc = Join-Path $xapkExtractedDir 'manifest.json'
    if (Test-Path $manifestSrc) {
        Copy-Item $manifestSrc (Join-Path $Output 'xapk-manifest.json')
    }

    # List OBB files
    $obbFiles = Get-ChildItem -Path $xapkExtractedDir -Recurse -Filter '*.obb' -ErrorAction SilentlyContinue
    if ($obbFiles) {
        Write-Host "OBB files found (not decompiled, data-only):"
        foreach ($obb in $obbFiles) {
            $size = '{0:N1} MB' -f ($obb.Length / 1MB)
            Write-Host "  - $($obb.Name) ($size)"
        }
        Write-Host ""
    }

    foreach ($apkFile in $xapkApkFiles) {
        $apkName = [IO.Path]::GetFileNameWithoutExtension($apkFile.Name)
        Write-Host ""
        Write-Host "======================================================"
        Invoke-DecompileSingle -FileAbs $apkFile.FullName -OutDir (Join-Path $Output $apkName) -Label "$($apkFile.Name)"
    }

    # Cleanup extracted XAPK
    Remove-Item $xapkExtractedDir -Recurse -Force

    Write-Host ""
    Write-Host "=== XAPK decompilation complete ==="
    Write-Host "Subdirectories in ${Output}\"
    Get-ChildItem -Path $Output -Directory | ForEach-Object { Write-Host $_.Name }
} else {
    Invoke-DecompileSingle -FileAbs $inputFileAbs -OutDir $Output -Label ''

    # --- Split/bundled APK detection ---
    # Some APKs are bundles: the outer APK contains
    # base.apk + split_config.*.apk inside the resources directory. jadx will
    # decompile the thin outer wrapper and produce very few Java files.
    # Detect this and automatically decompile the inner base.apk.
    $sourcesDir = Join-Path $Output 'sources'
    $resourcesDir = Join-Path $Output 'resources'
    if ((Test-Path $sourcesDir) -and (Test-Path $resourcesDir)) {
        $javaCount = (Get-ChildItem -Path $sourcesDir -Recurse -Filter '*.java' -File -ErrorAction SilentlyContinue).Count
        $innerApks = Get-ChildItem -Path $resourcesDir -Filter '*.apk' -File -ErrorAction SilentlyContinue
        $baseApk = $innerApks | Where-Object { $_.Name -eq 'base.apk' }

        if ($javaCount -le 10 -and $baseApk) {
            Write-Host ""
            Write-Host "=== Split/bundled APK detected ==="
            Write-Host "Outer APK produced only $javaCount Java file(s) but contains $($innerApks.Count) inner APK(s):"
            foreach ($inner in $innerApks) {
                Write-Host "  - $($inner.Name)"
            }
            Write-Host ""
            Write-Host "Decompiling base.apk (contains the actual app code)..."
            $baseOutput = Join-Path $Output 'base'
            Invoke-DecompileSingle -FileAbs $baseApk.FullName -OutDir $baseOutput -Label 'base.apk'

            # Decompile any split APKs that aren't just config splits
            $splitApks = $innerApks | Where-Object { $_.Name -ne 'base.apk' -and $_.Name -notmatch 'split_config\.' }
            foreach ($split in $splitApks) {
                $splitName = [IO.Path]::GetFileNameWithoutExtension($split.Name)
                Write-Host ""
                Write-Host "Decompiling $($split.Name)..."
                Invoke-DecompileSingle -FileAbs $split.FullName -OutDir (Join-Path $Output $splitName) -Label $split.Name
            }

            if ($innerApks | Where-Object { $_.Name -match 'split_config\.' }) {
                Write-Host ""
                Write-Host "Skipped config splits (resource/ABI only):"
                $innerApks | Where-Object { $_.Name -match 'split_config\.' } | ForEach-Object { Write-Host "  - $($_.Name)" }
            }

            Write-Host ""
            Write-Host "NOTE: The main decompiled source is in: $(Join-Path $Output 'base\sources')"
        }
    }

    Write-Host ""
    Write-Host "=== Decompilation complete ==="
}
