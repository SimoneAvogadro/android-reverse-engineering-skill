# decode-apk.ps1 - Decode an APK or a split bundle (XAPK/APKM/APKS) into smali using apktool
#
# .apk input is decoded directly. Split bundles (.xapk/.apkm/.apks, or a
# directory of split APKs) are first merged into ONE APK with APKEditor, then
# decoded, so resources that live only in config splits (density, locale, ABI)
# are kept instead of turning into @null references.
#
# Exit codes:
#   0 - success
#   1 - error (invalid input, unknown option, missing tools, merge/decode failed)
param(
    [Parameter(Position=0)]
    [string]$InputFile,
    [Alias('o')]
    [string]$Output,
    [switch]$Force,
    [switch]$NoForce,
    [switch]$KeepSplits,
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

# Resolve user-supplied environment paths up front: the tools later run from a
# temporary working directory, where relative paths would no longer resolve.
foreach ($envVar in @('APKEDITOR_JAR', 'ANDROID_HOME', 'ANDROID_SDK_ROOT')) {
    $envVal = [Environment]::GetEnvironmentVariable($envVar, 'Process')
    if ($envVal) {
        [Environment]::SetEnvironmentVariable($envVar, $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($envVal), 'Process')
    }
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

$installDep = Join-Path $PSScriptRoot '..\..\android-reverse-engineering\scripts\install-dep.ps1'
try { $installDep = (Resolve-Path -LiteralPath $installDep).Path } catch { }

function Show-Usage {
    Write-Host @"
Usage: decode-apk.ps1 <file|dir> [OPTIONS]

Decode an APK, or a split APK bundle, into smali and resources using apktool.

Split bundles (.xapk, .apkm, .apks, or a directory containing base.apk plus
split APKs) are merged into a single APK with APKEditor BEFORE decoding.
The rebuild (rebuild-apk.ps1) then produces one installable APK.
Merge details are written to <decoded-dir>\.merged-from-splits.json.

Arguments:
  <file|dir>        Path to .apk, .xapk, .apkm, .apks, or a split-APK directory

Options:
  -Output DIR       Output directory (default: <basename>-decoded)
  -Force            Overwrite output directory if it exists (default)
  -NoForce          Do not overwrite existing output directory
  -KeepSplits       DEPRECATED legacy mode (XAPK/APKM/APKS files only):
                    decode the base APK alone and keep the splits in
                    .xapk-origin\ so rebuild-apk.ps1 reassembles an XAPK.
                    Resources that exist only in splits become @null in the
                    decoded base (e.g. AppCompat drawables) and the app may
                    crash at inflation. Will be removed.
  -Help             Show this help message

Environment:
  APKEDITOR_JAR     Path to APKEditor.jar (default: %USERPROFILE%\.local\share\apkeditor\APKEditor.jar,
                    then an 'apkeditor' launcher on PATH)

Output:
  DECODED_DIR:<path>
  MERGED_FROM_SPLITS:<path>\.merged-from-splits.json   (split bundle input)
  OBB_WARNING:<name>                                    (OBB files are never merged)
  DEPRECATION_WARNING:keep-splits                       (-KeepSplits only)
  XAPK_ORIGIN:<path>                                    (-KeepSplits only)
  PROTECTION_DETECTED:... / PROTECTION_SUMMARY:<kind>   (detect-protection.ps1, run
                                                        after a successful decode)
  ADWRAPPER_DETECTED:... / ADWRAPPER_SUMMARY:<kind>     (detect-adwrapper.ps1, run
                                                        after a successful decode)
All paths are absolute. The output directory is replaced only after a successful
decode (the new tree is decoded next to it, then swapped in).
"@
    exit 0
}

if ($Help) { Show-Usage }

function Write-Err { param($msg) Write-Host $msg -ForegroundColor Red }

# Run a native tool, streaming its output (PS 5.1 turns redirected stderr into
# error records, which 'Stop' would make fatal). Returns the exit code.
function Invoke-Tool {
    param([string[]]$Command, [string[]]$Arguments)
    $exe = $Command[0]
    $pre = @()
    if ($Command.Count -gt 1) { $pre = $Command[1..($Command.Count - 1)] }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $exe @pre @Arguments 2>&1 | ForEach-Object { Write-Host "$_" }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
    return $code
}

function Get-ToolOutput {
    param([string[]]$Command, [string[]]$Arguments)
    $exe = $Command[0]
    $pre = @()
    if ($Command.Count -gt 1) { $pre = $Command[1..($Command.Count - 1)] }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $exe @pre @Arguments 2>&1 | ForEach-Object { "$_" }
    } finally {
        $ErrorActionPreference = $prev
    }
    return ($out -join "`n")
}

# Paths that cannot be handed to the tools as-is:
# - non-ASCII: Java on Windows receives its arguments in the ANSI code page;
# - & ^ % !: cmd.exe metacharacters, which break .cmd/.bat shims (scoop, choco).
# Such paths are staged under ASCII names (temp copies or junctions).
function Test-UnsafePath { param([string]$s) return ($s -match '[^\x00-\x7F]' -or $s -match '[&^%!]') }

# Delete a directory tree, including paths longer than MAX_PATH
function Remove-Tree {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $full = (Get-Item -LiteralPath $Path -Force).FullName
    try { Remove-Item -LiteralPath "\\?\$full" -Recurse -Force -ErrorAction Stop } catch { }
    if (Test-Path -LiteralPath $Path) {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { & cmd.exe /c "rd /s /q `"\\?\$full`"" 2>&1 | Out-Null } finally { $ErrorActionPreference = $prev }
    }
    if (Test-Path -LiteralPath $Path) { Write-Host "Warning: could not fully delete $full" -ForegroundColor Yellow }
}

# apktool: 'java -jar apktool.jar' when the JAR can be found (next to the
# command, install-dep, scoop, choco), else the apktool command on PATH
function Get-ApktoolCommand {
    $cmd = Get-Command apktool -ErrorAction SilentlyContinue
    $candidates = @()
    if ($cmd -and $cmd.Source) { $candidates += (Join-Path (Split-Path $cmd.Source -Parent) 'apktool.jar') }
    $candidates += (Join-Path $env:USERPROFILE '.local\share\apktool\apktool.jar')
    $candidates += (Join-Path $env:USERPROFILE 'scoop\apps\apktool\current\apktool.jar')
    if ($env:SCOOP) { $candidates += (Join-Path $env:SCOOP 'apps\apktool\current\apktool.jar') }
    if ($env:ChocolateyInstall) { $candidates += (Join-Path $env:ChocolateyInstall 'lib\apktool\tools\apktool.jar') }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return @('java', '-jar', $c) }
    }
    if ($cmd) { return @($cmd.Source) }
}

# Hardlink (same volume, instant) or copy a file into the work dir
function Copy-Staged {
    param([string]$Src, [string]$Dest)
    try {
        New-Item -ItemType HardLink -Path $Dest -Value $Src -ErrorAction Stop | Out-Null
    } catch {
        Copy-Item -LiteralPath $Src -Destination $Dest
    }
}

function ConvertTo-JsonString {
    param([string]$s)
    return '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"'
}

# =====================================================================
# Validate input
# =====================================================================

if (-not $InputFile) {
    Write-Err "Error: No input file specified."
    Show-Usage
}
if (-not (Test-Path -LiteralPath $InputFile)) {
    Write-Err "Error: File not found: $InputFile"
    exit 1
}

$apktool = @(Get-ApktoolCommand)
if ($apktool.Count -eq 0) {
    Write-Err "Error: apktool is not installed or not in PATH."
    Write-Host "Run: & `"$installDep`" apktool"
    exit 1
}

$inputItem = Get-Item -LiteralPath $InputFile
$inputAbs = $inputItem.FullName
$extLower = ''
if ($inputItem.PSIsContainer) {
    $inputKind = 'dir'
    $baseName = $inputItem.Name
} else {
    $extLower = $inputItem.Extension.TrimStart('.').ToLower()
    if ($extLower -eq 'apk') {
        $inputKind = 'apk'
    } elseif ($extLower -in @('xapk', 'apkm', 'apks')) {
        $inputKind = 'bundle'
    } else {
        Write-Err "Error: Unsupported file type '.$extLower'. Expected .apk, .xapk, .apkm, .apks or a directory of split APKs"
        exit 1
    }
    $baseName = [IO.Path]::GetFileNameWithoutExtension($inputItem.Name)
}

if ($KeepSplits -and $inputKind -ne 'bundle') {
    Write-Err "Error: -KeepSplits only applies to .xapk/.apkm/.apks files."
    exit 1
}

if (-not $Output) { $Output = "$baseName-decoded" }
$outputAbs = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output).TrimEnd('\')

if ($NoForce -and (Test-Path -LiteralPath $outputAbs)) {
    Write-Err "Error: Output directory already exists: $outputAbs (use -Force to overwrite)"
    exit 1
}
if ((Test-Path -LiteralPath $outputAbs) -and -not (Test-Path -LiteralPath $outputAbs -PathType Container)) {
    Write-Err "Error: Output path exists and is not a directory: $outputAbs"
    exit 1
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$outParent = Split-Path $outputAbs -Parent
New-Item -ItemType Directory -Path $outParent -Force | Out-Null
$workDir = Join-Path $env:TEMP "apk-decode-$(Get-Random)"
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$junctions = @()
$decodeTmp = $null

try {
    # Every path is absolute from here on: run the tools from the (safe) work dir
    Push-Location -LiteralPath $workDir
    $apkToDecode = $inputAbs
    $merged = $false
    $isXapk = $false
    $splitNames = @()
    $obbNames = @()
    $apkEditorVersion = ''

    if ($inputKind -eq 'apk' -and (Test-UnsafePath $inputAbs)) {
        $apkToDecode = Join-Path $workDir 'input.apk'
        Copy-Staged $inputAbs $apkToDecode
    }

    # =================================================================
    # Split bundle - merge all splits into one APK with APKEditor
    # =================================================================
    if (($inputKind -eq 'bundle' -or $inputKind -eq 'dir') -and -not $KeepSplits) {
        # APKEditor: $APKEDITOR_JAR, then the install-dep location, then a launcher on PATH
        $apkEditor = @()
        if ($env:APKEDITOR_JAR) {
            if (-not (Test-Path -LiteralPath $env:APKEDITOR_JAR)) {
                Write-Err "Error: APKEDITOR_JAR is set but the file does not exist: $env:APKEDITOR_JAR"
                exit 1
            }
            $apkEditor = @('java', "-Djava.io.tmpdir=$workDir", '-jar', $env:APKEDITOR_JAR)
        } else {
            $c = Join-Path $env:USERPROFILE '.local\share\apkeditor\APKEditor.jar'
            $launcher = Get-Command apkeditor -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $c) {
                $apkEditor = @('java', "-Djava.io.tmpdir=$workDir", '-jar', $c)
            } elseif ($launcher) {
                $apkEditor = @($launcher.Source)
            }
        }
        if ($apkEditor.Count -eq 0) {
            Write-Err "Error: APKEditor is required to merge split APKs (input: $InputFile)."
            Write-Host "Run: & `"$installDep`" apkeditor   (or set APKEDITOR_JAR to the path of APKEditor.jar)"
            exit 1
        }
        if ((Get-ToolOutput $apkEditor @('-version')) -match 'APKEditor version ([0-9.]+)') {
            $apkEditorVersion = $Matches[1]
        }

        Write-Host "=== Merging split APKs with APKEditor $apkEditorVersion ==="

        if ($inputKind -eq 'bundle') {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($inputAbs)
            try {
                foreach ($entry in $zip.Entries) {
                    if ($entry.Name -like '*.apk') { $splitNames += $entry.Name }
                    elseif ($entry.Name -like '*.obb') { $obbNames += $entry.Name }
                }
            } finally { $zip.Dispose() }
        } else {
            $splitNames = @(Get-ChildItem -LiteralPath $inputAbs -File -Filter '*.apk' | Sort-Object Name | ForEach-Object { $_.Name })
        }
        if ($splitNames.Count -eq 0) {
            Write-Err "Error: No APK files found in $InputFile"
            exit 1
        }
        Write-Host "Found $($splitNames.Count) APK(s):"
        foreach ($f in $splitNames) { Write-Host "  - $f" }

        # Always stage the input in the work dir (like the symlink on Linux): the
        # path is then safe (see Test-UnsafePath) and APKEditor's tmp_* extraction
        # folder, created next to its input, stays inside the work dir.
        if ($inputKind -eq 'bundle') {
            $mergeInput = Join-Path $workDir "input.$extLower"
            Copy-Staged $inputAbs $mergeInput
        } else {
            $mergeInput = Join-Path $workDir 'input-dir'
            New-Item -ItemType Directory -Path $mergeInput -Force | Out-Null
            foreach ($apk in Get-ChildItem -LiteralPath $inputAbs -File -Filter '*.apk') {
                Copy-Staged $apk.FullName (Join-Path $mergeInput $apk.Name)
            }
        }

        $mergedApk = Join-Path $workDir 'merged.apk'
        Write-Host ""
        $rc = Invoke-Tool $apkEditor @('m', '-i', $mergeInput, '-o', $mergedApk, '-f')
        if ($rc -ne 0 -or -not (Test-Path -LiteralPath $mergedApk)) {
            Write-Err "Error: APKEditor merge failed."
            exit 1
        }
        Write-Host "Merged $($splitNames.Count) APK(s) into one APK."
        foreach ($f in $obbNames) {
            Write-Host "Warning: OBB file not merged (copy it to the device manually): $f" -ForegroundColor Yellow
            Write-Host "OBB_WARNING:$f"
        }
        Write-Host ""
        $apkToDecode = $mergedApk
        $merged = $true
    }

    # =================================================================
    # DEPRECATED -KeepSplits: extract base APK, preserve splits for XAPK rebuild
    # =================================================================
    $xapkExtract = $null
    if ($KeepSplits) {
        $isXapk = $true
        Write-Host "DEPRECATION_WARNING:keep-splits"
        Write-Host "Warning: -KeepSplits is deprecated and will be removed." -ForegroundColor Yellow
        Write-Host "         Only the base APK is decoded: resources that exist only in the splits" -ForegroundColor Yellow
        Write-Host "         become @null (e.g. AppCompat selector drawables) and the rebuilt app may" -ForegroundColor Yellow
        Write-Host "         crash at inflation. Omit -KeepSplits to merge the splits with APKEditor." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "=== Extracting XAPK archive ==="
        $xapkExtract = Join-Path $workDir 'xapk'
        [System.IO.Compression.ZipFile]::ExtractToDirectory($inputAbs, $xapkExtract)

        $allApks = @(Get-ChildItem -LiteralPath $xapkExtract -Recurse -File -Filter '*.apk' | Sort-Object Name)
        if ($allApks.Count -eq 0) {
            Write-Err "Error: No APK files found inside XAPK archive."
            exit 1
        }
        Write-Host "Found $($allApks.Count) APK(s) inside XAPK:"
        foreach ($f in $allApks) { Write-Host "  - $($f.Name)" }

        # Select base APK: prefer "base.apk", else the largest non-config APK
        $baseApk = $allApks | Where-Object { $_.Name -eq 'base.apk' } | Select-Object -First 1
        if (-not $baseApk) {
            $baseApk = $allApks | Where-Object { $_.Name -notlike 'config.*' } | Sort-Object Length -Descending | Select-Object -First 1
        }
        if (-not $baseApk) {
            Write-Err "Error: Could not identify a base APK inside the XAPK."
            exit 1
        }
        Write-Host ""
        Write-Host "Selected base APK: $($baseApk.Name)"
        $splitApks = @($allApks | Where-Object { $_.FullName -ne $baseApk.FullName })
        foreach ($f in $splitApks) { Write-Host "  [split] $($f.Name)" }
        if ($splitApks.Count -gt 0) {
            Write-Host "$($splitApks.Count) split APK(s) preserved in .xapk-origin\splits\ for rebuild."
        }
        Write-Host ""
        $apkToDecode = $baseApk.FullName
        if (Test-UnsafePath $apkToDecode) {
            $apkToDecode = Join-Path $workDir 'base-input.apk'
            Copy-Item -LiteralPath $baseApk.FullName -Destination $apkToDecode
        }
    }

    # =================================================================
    # Decode with apktool into a sibling temp dir (swapped in on success)
    # =================================================================
    Write-Host "=== Decoding APK with apktool ==="

    $tmpName = ".decode-tmp-$(Get-Random)"
    $decodeTmp = Join-Path $outParent $tmpName
    $parentForTools = $outParent
    if (Test-UnsafePath $outParent) {
        $parentForTools = Join-Path $workDir 'outparent'
        New-Item -ItemType Junction -Path $parentForTools -Target $outParent | Out-Null
        $junctions += $parentForTools
    }
    $rc = Invoke-Tool $apktool @('d', '-f', '-o', (Join-Path $parentForTools $tmpName), $apkToDecode)
    if ($rc -ne 0) {
        Write-Err "Error: apktool decode failed."
        Write-Host "Tip: If this is a framework error, delete %LOCALAPPDATA%\apktool\framework\1.apk and retry."
        exit 1
    }

    # =================================================================
    # Verify output
    # =================================================================
    $smaliDirs = @(Get-ChildItem -LiteralPath $decodeTmp -Directory -Filter 'smali*')
    if ($smaliDirs.Count -eq 0) {
        Write-Err "Error: No smali/ directory found in decoded output."
        exit 1
    }
    $manifestPath = Join-Path $decodeTmp 'AndroidManifest.xml'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-Host "Warning: AndroidManifest.xml not found in decoded output." -ForegroundColor Yellow
    }

    # =================================================================
    # Record merge metadata (split bundle input)
    # =================================================================
    if ($merged) {
        $pkgName = ''; $verCode = ''; $verName = ''
        if (Test-Path -LiteralPath $manifestPath) {
            $m = Select-String -LiteralPath $manifestPath -Pattern '<manifest[^>]* package="([^"]*)"' | Select-Object -First 1
            if ($m) { $pkgName = $m.Matches[0].Groups[1].Value }
        }
        $ymlPath = Join-Path $decodeTmp 'apktool.yml'
        if (Test-Path -LiteralPath $ymlPath) {
            $m = Select-String -LiteralPath $ymlPath -Pattern "^\s*versionCode:\s*'?([0-9]*)" | Select-Object -First 1
            if ($m) { $verCode = $m.Matches[0].Groups[1].Value }
            $m = Select-String -LiteralPath $ymlPath -Pattern "^\s*versionName:\s*'?([^']*?)'?\s*$" | Select-Object -First 1
            if ($m) { $verName = $m.Matches[0].Groups[1].Value }
        }
        $format = $extLower
        if (-not $format) { $format = 'directory' }
        $splitsJson = ($splitNames | ForEach-Object { ConvertTo-JsonString $_ }) -join ', '
        $obbJson = ($obbNames | ForEach-Object { ConvertTo-JsonString $_ }) -join ', '
        $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $json = @(
            '{',
            "  `"format`": $(ConvertTo-JsonString $format),",
            "  `"source_file`": $(ConvertTo-JsonString $inputAbs),",
            "  `"package_name`": $(ConvertTo-JsonString $pkgName),",
            "  `"version_code`": $(ConvertTo-JsonString $verCode),",
            "  `"version_name`": $(ConvertTo-JsonString $verName),",
            "  `"split_apks`": [$splitsJson],",
            "  `"obb_files_not_merged`": [$obbJson],",
            "  `"merged_with`": `"APKEditor`",",
            "  `"apkeditor_version`": $(ConvertTo-JsonString $apkEditorVersion),",
            "  `"decoded_timestamp`": `"$ts`"",
            '}'
        ) -join "`n"
        [IO.File]::WriteAllText((Join-Path $decodeTmp '.merged-from-splits.json'), $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
    }

    # =================================================================
    # Preserve XAPK structure for rebuild (deprecated -KeepSplits)
    # =================================================================
    if ($isXapk) {
        Write-Host ""
        Write-Host "=== Preserving XAPK structure ==="
        $originDir = Join-Path $decodeTmp '.xapk-origin'
        $originSplits = Join-Path $originDir 'splits'
        New-Item -ItemType Directory -Path $originSplits -Force | Out-Null

        $xapkManifest = Join-Path $xapkExtract 'manifest.json'
        if (Test-Path -LiteralPath $xapkManifest) {
            Copy-Item -LiteralPath $xapkManifest -Destination (Join-Path $originDir 'manifest.json')
            Write-Host "  Copied manifest.json"
        }
        foreach ($icon in @('icon.png', 'icon.jpg')) {
            $iconPath = Join-Path $xapkExtract $icon
            if (Test-Path -LiteralPath $iconPath) {
                Copy-Item -LiteralPath $iconPath -Destination $originDir
                Write-Host "  Copied $icon"
                break
            }
        }
        foreach ($f in $splitApks) {
            Copy-Item -LiteralPath $f.FullName -Destination $originSplits
            Write-Host "  Copied split: $($f.Name)"
        }

        $pkgName = ''; $verCode = ''; $verName = ''
        if (Test-Path -LiteralPath $xapkManifest) {
            $mj = Get-Content -LiteralPath $xapkManifest -Raw
            if ($mj -match '"package_name"\s*:\s*"([^"]*)"') { $pkgName = $Matches[1] }
            if ($mj -match '"version_code"\s*:\s*"?([0-9]*)') { $verCode = $Matches[1] }
            if ($mj -match '"version_name"\s*:\s*"([^"]*)"') { $verName = $Matches[1] }
        }
        $obbEntries = @(Get-ChildItem -LiteralPath $xapkExtract -Recurse -File -Filter '*.obb' | ForEach-Object {
            "{`"name`": $(ConvertTo-JsonString $_.Name), `"size_bytes`": $($_.Length)}"
        })
        foreach ($o in $obbEntries) { Write-Host "  OBB file detected (not copied - registered in metadata only): $o" }
        $splitsJson = ($splitApks | ForEach-Object { ConvertTo-JsonString $_.Name }) -join ', '
        $ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $json = @(
            '{',
            '  "format": "xapk",',
            "  `"original_file`": $(ConvertTo-JsonString $inputAbs),",
            "  `"package_name`": $(ConvertTo-JsonString $pkgName),",
            "  `"version_code`": $(ConvertTo-JsonString $verCode),",
            "  `"version_name`": $(ConvertTo-JsonString $verName),",
            "  `"base_apk`": $(ConvertTo-JsonString $baseApk.Name),",
            "  `"split_apks`": [$splitsJson],",
            "  `"obb_files`": [$($obbEntries -join ', ')],",
            "  `"decoded_timestamp`": `"$ts`"",
            '}'
        ) -join "`n"
        [IO.File]::WriteAllText((Join-Path $originDir 'metadata.json'), $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "  Wrote metadata.json"
    }

    # =================================================================
    # Swap the new tree into place (the old one is deleted only now)
    # =================================================================
    if (Test-Path -LiteralPath $outputAbs) {
        $oldName = ".decode-old-$(Get-Random)"
        Rename-Item -LiteralPath $outputAbs -NewName $oldName
        Rename-Item -LiteralPath $decodeTmp -NewName (Split-Path $outputAbs -Leaf)
        $decodeTmp = $null
        Remove-Tree (Join-Path $outParent $oldName)
    } else {
        Rename-Item -LiteralPath $decodeTmp -NewName (Split-Path $outputAbs -Leaf)
        $decodeTmp = $null
    }

    if ($merged) {
        $mergeMeta = Join-Path $outputAbs '.merged-from-splits.json'
        Write-Host ""
        Write-Host "Merge metadata written: $mergeMeta"
        Write-Host "MERGED_FROM_SPLITS:$mergeMeta"
    }
    if ($isXapk) {
        $originFinal = Join-Path $outputAbs '.xapk-origin'
        Write-Host ""
        Write-Host "XAPK structure preserved in: $originFinal"
        Write-Host "XAPK_ORIGIN:$originFinal"
    }

    Write-Host ""
    Write-Host "Decoded successfully: $outputAbs"
    Write-Host "DECODED_DIR:$outputAbs"
} finally {
    Pop-Location
    # Junctions first (deleting them never touches their targets), then temp trees
    foreach ($j in $junctions) {
        if (Test-Path -LiteralPath $j) { [System.IO.Directory]::Delete($j) }
    }
    if ($decodeTmp) { Remove-Tree $decodeTmp }
    Remove-Tree $workDir
}

# Protection check (detection only, informational): warn now, before any time
# is spent on a rebuild, when a re-signed APK of this app will not run. It never
# changes the decode result or exit code.
$detectProtection = Join-Path $PSScriptRoot 'detect-protection.ps1'
if (Test-Path -LiteralPath $detectProtection -PathType Leaf) {
    Write-Host ""
    try {
        & $detectProtection -DecodedDir $outputAbs
        if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
    } catch {
        Write-Host "[WARN] Protection check failed ($_); run detect-protection.ps1 manually." -ForegroundColor Yellow
    }
}

# In-house ad/analytics wrapper check (detection only, informational): a
# publisher's own wrapper can serve house/WebView ads that survive neutralizing
# the third-party network SDKs. Never changes the decode result or exit code.
$detectAdwrapper = Join-Path $PSScriptRoot 'detect-adwrapper.ps1'
if (Test-Path -LiteralPath $detectAdwrapper -PathType Leaf) {
    Write-Host ""
    try {
        & $detectAdwrapper -DecodedDir $outputAbs
        if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
    } catch {
        Write-Host "[WARN] Ad-wrapper check failed ($_); run detect-adwrapper.ps1 manually." -ForegroundColor Yellow
    }
}
exit 0

} finally {
    if ($script:CallerOutputEncoding) {
        try { [Console]::OutputEncoding = $script:CallerOutputEncoding } catch { }
    }
}
