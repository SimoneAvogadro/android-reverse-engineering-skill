# rebuild-apk.ps1 - Rebuild and sign a decoded APK directory
#
# Pipeline: apktool b -> zipalign (page-aligns stored .so) -> sign -> verify
#           (signature + ZIP alignment) -> move into place
#
# The output is always a single APK. Only directories decoded with the
# deprecated 'decode-apk.ps1 -KeepSplits' (.xapk-origin\) are reassembled
# into an XAPK.
#
# Exit codes:
#   0 - success
#   1 - error (unknown option, missing tool, build/sign failure, misaligned output)
param(
    [Parameter(Position=0)]
    [string]$DecodedDir,
    [Alias('o')]
    [string]$Output,
    [switch]$AutoKeystore,
    [switch]$DebugKey,
    [string]$Keystore,
    [string]$KeyAlias = 'key0',
    [string]$KeyPass = 'android',
    [string]$StorePass = 'android',
    [switch]$NoSign,
    [switch]$Zipalign,
    [switch]$NoZipalign,
    [switch]$SingleApk,
    [switch]$NoRes,
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

# Stable, user-level debug key: every build signed with it can be installed
# over the previous one (a per-directory key could not).
$UserKsDir = Join-Path $env:APPDATA 'android-re'
$UserKs = Join-Path $UserKsDir 'neutralizer-debug.keystore'

function Show-Usage {
    Write-Host @"
Usage: rebuild-apk.ps1 <decoded-dir> [OPTIONS]

Rebuild an apktool-decoded APK directory into a signed, installable APK.
Split bundles are merged by decode-apk.ps1 (APKEditor) before decoding, so the
result is always one APK. Stored native libraries (.so) are page-aligned
(zipalign -P 16 when supported, otherwise -p) and all stored entries are
checked after signing.

Directories decoded with the deprecated 'decode-apk.ps1 -KeepSplits'
(.xapk-origin\) are reassembled into an XAPK instead (deprecated, will be removed).

Arguments:
  <decoded-dir>       Path to the apktool-decoded APK directory

Options:
  -Output FILE        Output path (default: <decoded-dir>-neutralized.apk)
  -AutoKeystore       Sign with the stable user-level neutralizer debug key,
                      created once and then reused:
                      $UserKs
  -DebugKey           Same as -AutoKeystore (the default)
  -Keystore FILE      Custom keystore, e.g. %USERPROFILE%\.android\debug.keystore with
                      -KeyAlias androiddebugkey (takes precedence)
  -KeyAlias ALIAS     Key alias within the keystore (default: key0)
  -KeyPass PASS       Key password (default: android)
  -StorePass PASS     Keystore password (default: android)
  -NoSign             Skip signing (output unsigned APK)
  -Zipalign           Run zipalign (default)
  -NoZipalign         Skip zipalign
  -Help               Show this help message

Tools: zipalign and apksigner are taken from Android SDK build-tools
(%ANDROID_HOME%, %ANDROID_SDK_ROOT%, %LOCALAPPDATA%\Android\Sdk,
%USERPROFILE%\.local\share\android-sdk) or PATH. Install: install-dep.ps1 build-tools.

Output:
  BUILD_OK:<apk>
  ZIPALIGN_OK:16k|4k
  KEYSTORE_USED:<path>
  KEYSTORE_SOURCE:debug-user|debug-generated|custom
  KEYSTORE_ALIAS:<alias>
  SIGN_OK:<output-apk>
  VERIFY_OK:<output-apk>
  ALIGN_OK:<n>:16k|4k|none|n/a  (n = stored .so files; the stored .so page alignment)
  ALIGN_WARNING:not-16k         (stored .so only 4 KB aligned: 16 KB-page devices refuse it)
  ALIGN_WARNING:so-not-page-aligned (stored .so not page-aligned; accepted only because
                                 extractNativeLibs is not "false" - the installer extracts them)
  ALIGN_FAIL:<entry>            (misaligned stored entry, max 20 lines - exit 1; the
                                 APK is left as <output>.misaligned, never at <output>)
  ABI_WARNING:32bit-only:<abis> (no arm64-v8a/x86_64 native code)
  DEPRECATION_WARNING:xapk-output, SPLIT_SIGNED:<file>, XAPK_ASSEMBLED:<xapk>
                                (-KeepSplits directories only)
"@
    exit 0
}

if ($Help) { Show-Usage }

function Write-Info  { param($msg) Write-Host "[INFO] $msg" }
function Write-Ok    { param($msg) Write-Host "[OK] $msg" }
function Write-Warn  { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Fail  { param($msg) Write-Host "[FAIL] $msg" -ForegroundColor Red }

# Run a native tool, streaming its output (PS 5.1 turns redirected stderr into
# error records, which 'Stop' would make fatal). Returns the exit code.
function Invoke-Tool {
    param([string[]]$Command, [string[]]$Arguments, [switch]$Quiet)
    $exe = $Command[0]
    $pre = @()
    if ($Command.Count -gt 1) { $pre = $Command[1..($Command.Count - 1)] }
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($Quiet) {
            & $exe @pre @Arguments 2>&1 | Out-Null
        } else {
            & $exe @pre @Arguments 2>&1 | ForEach-Object { Write-Host "$_" }
        }
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
}

# Prefer 'java -jar <tool>.jar' over .bat/.cmd wrappers (cmd.exe quoting)
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

# apksigner: SDK build-tools first (current versions), then PATH; run its JAR directly
function Get-ApksignerCommand {
    $bat = $null
    foreach ($sdk in $sdkRoots) {
        $bt = Get-LatestBuildToolsDir $sdk
        if ($bt -and (Test-Path -LiteralPath (Join-Path $bt 'apksigner.bat'))) { $bat = Join-Path $bt 'apksigner.bat'; break }
    }
    if (-not $bat) {
        $cmd = Get-Command apksigner -ErrorAction SilentlyContinue
        if ($cmd) { $bat = $cmd.Source }
    }
    if (-not $bat) { return }
    $jar = Join-Path (Split-Path $bat -Parent) 'lib\apksigner.jar'
    if (Test-Path -LiteralPath $jar) { return @('java', '-jar', $jar) }
    return @($bat)
}

# Data offsets of all stored (uncompressed) entries, read from the ZIP central
# directory + local headers (no external tool needed). Supports ZIP64 (the
# end-of-central-directory-64 record and the 0x0001 extra field).
function Get-StoredEntryOffsets {
    param([string]$Apk)
    $fs = [System.IO.File]::OpenRead($Apk)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $len = $fs.Length
        $scan = [Math]::Min($len, 65557)
        [void]$fs.Seek($len - $scan, [System.IO.SeekOrigin]::Begin)
        $buf = $br.ReadBytes([int]$scan)
        $eocd = -1
        for ($i = $buf.Length - 22; $i -ge 0; $i--) {
            if ($buf[$i] -eq 0x50 -and $buf[$i + 1] -eq 0x4b -and $buf[$i + 2] -eq 0x05 -and $buf[$i + 3] -eq 0x06) { $eocd = $i; break }
        }
        if ($eocd -lt 0) { throw "ZIP end of central directory not found in $Apk" }
        # NB: in PowerShell 0xFFFFFFFF is the Int32 -1, so the 32-bit sentinel is spelled out
        $u32Max = [long]4294967295
        [long]$count = [BitConverter]::ToUInt16($buf, $eocd + 10)
        [long]$cdOffset = [BitConverter]::ToUInt32($buf, $eocd + 16)
        if ($count -eq 0xFFFF -or $cdOffset -eq $u32Max) {
            # ZIP64: the locator (20 bytes) precedes the EOCD and points to the EOCD64 record
            $loc = $eocd - 20
            if ($loc -lt 0 -or [BitConverter]::ToUInt32($buf, $loc) -ne 0x07064b50) { throw "ZIP64 locator not found in $Apk" }
            $eocd64 = [BitConverter]::ToInt64($buf, $loc + 8)
            [void]$fs.Seek($eocd64, [System.IO.SeekOrigin]::Begin)
            if ($br.ReadUInt32() -ne 0x06064b50) { throw "ZIP64 end of central directory not found in $Apk" }
            [void]$fs.Seek($eocd64 + 32, [System.IO.SeekOrigin]::Begin)
            $count = $br.ReadInt64()
            [void]$fs.Seek($eocd64 + 48, [System.IO.SeekOrigin]::Begin)
            $cdOffset = $br.ReadInt64()
        }
        [void]$fs.Seek($cdOffset, [System.IO.SeekOrigin]::Begin)
        $entries = New-Object 'System.Collections.Generic.List[object]'
        for ($e = 0; $e -lt $count; $e++) {
            if ($br.ReadUInt32() -ne 0x02014b50) { throw "Corrupt ZIP central directory in $Apk (entry $e)" }
            [void]$fs.Seek(6, [System.IO.SeekOrigin]::Current)       # versions, flags
            $method = $br.ReadUInt16()
            [void]$fs.Seek(8, [System.IO.SeekOrigin]::Current)       # time, date, crc
            [long]$csize = $br.ReadUInt32()
            [long]$usize = $br.ReadUInt32()
            $nameLen = $br.ReadUInt16()
            $extraLen = $br.ReadUInt16()
            $commentLen = $br.ReadUInt16()
            [void]$fs.Seek(8, [System.IO.SeekOrigin]::Current)       # disk, attributes
            [long]$lho = $br.ReadUInt32()
            $name = [System.Text.Encoding]::UTF8.GetString($br.ReadBytes($nameLen))
            $extra = $br.ReadBytes($extraLen)
            [void]$fs.Seek($commentLen, [System.IO.SeekOrigin]::Current)
            if ($lho -eq $u32Max) {
                # ZIP64 extra field (0x0001): 8-byte values, in order, for each field set to 0xFFFFFFFF
                $p = 0
                while ($p + 4 -le $extra.Length) {
                    $id = [BitConverter]::ToUInt16($extra, $p)
                    $size = [BitConverter]::ToUInt16($extra, $p + 2)
                    if ($id -eq 1) {
                        $q = $p + 4
                        if ($usize -eq $u32Max) { $q += 8 }
                        if ($csize -eq $u32Max) { $q += 8 }
                        $lho = [BitConverter]::ToInt64($extra, $q)
                        break
                    }
                    $p += 4 + $size
                }
            }
            if ($method -eq 0) {
                $isSo = $name.StartsWith('lib/') -and $name.EndsWith('.so')
                $entries.Add((New-Object PSObject -Property @{ Name = $name; Lho = $lho; Offset = [long]0; IsSo = $isSo }))
            }
        }
        foreach ($en in $entries) {
            [void]$fs.Seek($en.Lho + 26, [System.IO.SeekOrigin]::Begin)
            $n = $br.ReadUInt16()
            $x = $br.ReadUInt16()
            $en.Offset = $en.Lho + 30 + $n + $x
        }
        return $entries
    } finally {
        $fs.Close()
    }
}

# Every stored entry 4-byte aligned, stored lib/*.so page-aligned. Prints
# ALIGN_OK / ALIGN_WARNING / ALIGN_FAIL; returns $false on failure. A misaligned
# .so is fatal only when extractNativeLibs="false" ($needPageAlign).
function Test-Alignment {
    param([string]$Apk)
    $stored = @(Get-StoredEntryOffsets $Apk)
    $bad4 = @($stored | Where-Object { -not $_.IsSo -and ($_.Offset % 4 -ne 0) })
    $sos = @($stored | Where-Object { $_.IsSo })
    $badSo = @($sos | Where-Object { $_.Offset % 4096 -ne 0 })
    $not16 = @($sos | Where-Object { $_.Offset % 16384 -ne 0 })
    $fatal = ($bad4.Count -gt 0) -or (($badSo.Count -gt 0) -and $needPageAlign)
    $bad = @($badSo) + @($bad4)   # native libraries first
    if ($bad.Count -gt 0) {
        if ($fatal) {
            Write-Fail "Misaligned stored entries ($($badSo.Count) native libraries, $($bad4.Count) other) - the installer will reject this APK:"
        } else {
            Write-Warn "$($badSo.Count) stored native librar(y/ies) not page-aligned (extractNativeLibs is not `"false`", so the installer extracts them)."
        }
        foreach ($b in ($bad | Select-Object -First 20)) {
            Write-Host "  $($b.Name)" -ForegroundColor Red
            if ($fatal) { Write-Host "ALIGN_FAIL:$($b.Name)" }
        }
        if ($bad.Count -gt 20) { Write-Host "  ... and $($bad.Count - 20) more" -ForegroundColor Red }
        if ($fatal) { return $false }
    }
    if ($sos.Count -eq 0) {
        Write-Ok "All stored entries aligned (no stored native libraries)"
        Write-Host "ALIGN_OK:0:n/a"
    } elseif ($badSo.Count -gt 0) {
        # Not fatal (extractNativeLibs is not "false"), but not page-aligned either
        Write-Host "ALIGN_OK:$($sos.Count):none"
        Write-Host "ALIGN_WARNING:so-not-page-aligned"
    } elseif ($not16.Count -eq 0) {
        Write-Ok "All stored entries aligned; $($sos.Count) native librar(y/ies) 16 KB page-aligned"
        Write-Host "ALIGN_OK:$($sos.Count):16k"
    } else {
        Write-Ok "All stored entries aligned; $($sos.Count) native librar(y/ies) 4 KB page-aligned"
        Write-Host "ALIGN_OK:$($sos.Count):4k"
        Write-Warn "Native libraries are not 16 KB aligned: devices with 16 KB pages will refuse the APK."
        Write-Host "ALIGN_WARNING:not-16k"
    }
    return $true
}

# 64-bit-only phones (e.g. Galaxy S25, Pixel 7 and later) refuse APKs whose
# native code is 32-bit only.
function Test-Abis {
    param([string]$Apk)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Apk)
    try {
        $abis = @($zip.Entries | ForEach-Object {
            if ($_.FullName -match '^lib/([^/]+)/') { $Matches[1] }
        } | Sort-Object -Unique)
    } finally { $zip.Dispose() }
    if ($abis.Count -eq 0) { return }
    $list = $abis -join ','
    Write-Info "Native ABIs: $list"
    if (($abis -notcontains 'arm64-v8a') -and ($abis -notcontains 'x86_64')) {
        Write-Warn "The APK contains only 32-bit native code ($list)."
        Write-Host "       Many recent phones (e.g. Galaxy S25, Pixel 7 and later) are 64-bit only and" -ForegroundColor Yellow
        Write-Host "       will refuse to install it. Use an arm64-v8a build of the app if one exists." -ForegroundColor Yellow
        Write-Host "ABI_WARNING:32bit-only:$list"
    }
}

# Move a finished file into place (with its .idsig, or drop a stale one)
function Move-Output {
    param([string]$Src, [string]$Dest)
    Move-Item -LiteralPath $Src -Destination $Dest -Force
    if (Test-Path -LiteralPath "$Src.idsig") {
        Move-Item -LiteralPath "$Src.idsig" -Destination "$Dest.idsig" -Force
    } elseif (Test-Path -LiteralPath "$Dest.idsig") {
        Remove-Item -LiteralPath "$Dest.idsig" -Force
    }
}

# =====================================================================
# Argument checks
# =====================================================================

if ($NoRes) {
    Write-Fail "-NoRes was removed."
    Write-Host "  apktool 2.10 'b' has no such option (it is a decode flag), so it silently"
    Write-Host "  rebuilt everything again. A real resource-less rebuild would ship the original"
    Write-Host "  binary manifest and drop the disabled manifest components. Fix the reported"
    Write-Host "  resource error instead (split bundles: decode without -KeepSplits)."
    exit 1
}

if (-not $DecodedDir) {
    Write-Host "Error: No decoded directory specified." -ForegroundColor Red
    Show-Usage
}
if (-not (Test-Path -LiteralPath $DecodedDir -PathType Container)) {
    Write-Host "Error: Directory not found: $DecodedDir" -ForegroundColor Red
    exit 1
}
$decodedAbs = (Get-Item -LiteralPath $DecodedDir).FullName.TrimEnd('\')

# Keystore: -Keystore (custom) wins; -AutoKeystore / -DebugKey (default) both use
# the stable user-level neutralizer key, so every build installs over the previous one.
$keystoreMode = 'debug'
if ($Keystore) { $keystoreMode = 'custom' }
$doSign = -not $NoSign
$doZipalign = -not $NoZipalign

# Legacy XAPK origin (decode-apk.ps1 -KeepSplits)
$originDir = Join-Path $decodedAbs '.xapk-origin'
$isXapk = Test-Path -LiteralPath (Join-Path $originDir 'metadata.json')
if ($isXapk) {
    if ($SingleApk) {
        Write-Fail "-SingleApk cannot turn a -KeepSplits directory into one APK (the splits were never merged)."
        Write-Host "  Decode the bundle again without -KeepSplits: decode-apk.ps1 merges the splits with APKEditor."
        exit 1
    }
    Write-Host "DEPRECATION_WARNING:xapk-output"
    Write-Warn "XAPK output (from decode-apk -KeepSplits) is deprecated and will be removed."
    Write-Warn "The decoded base lacks split-only resources (@null references) and may crash."
    Write-Warn "Decode the bundle again without -KeepSplits to get a single merged APK."
} elseif ($SingleApk) {
    Write-Info "-SingleApk is the default now (flag ignored)."
}
$mergeMeta = Join-Path $decodedAbs '.merged-from-splits.json'

if (-not $Output) {
    if ($isXapk) { $Output = "$decodedAbs-neutralized.xapk" } else { $Output = "$decodedAbs-neutralized.apk" }
}
$outputAbs = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
New-Item -ItemType Directory -Path (Split-Path $outputAbs -Parent) -Force | Out-Null

# =====================================================================
# Tool checks
# =====================================================================

$apktool = @(Get-ApktoolCommand)
if ($apktool.Count -eq 0) {
    Write-Fail "apktool is not installed. Run: & `"$installDep`" apktool"
    exit 1
}
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Write-Fail "java is not installed. Run: & `"$installDep`" java"
    exit 1
}

$targetSdk = 0
$yml = Join-Path $decodedAbs 'apktool.yml'
if (Test-Path -LiteralPath $yml) {
    $m = Select-String -LiteralPath $yml -Pattern "^\s*targetSdkVersion:\s*'?([0-9]+)" | Select-Object -First 1
    if ($m) { $targetSdk = [int]$m.Matches[0].Groups[1].Value }
}

$signer = ''
$apksigner = @()
if ($doSign) {
    $apksigner = @(Get-ApksignerCommand)
    if ($apksigner.Count -gt 0) {
        $signer = 'apksigner'
    } elseif (Get-Command jarsigner -ErrorAction SilentlyContinue) {
        if ($targetSdk -ge 30) {
            Write-Fail "apksigner not found and this app targets SDK ${targetSdk}: Android 11+ refuses v1-only (jarsigner) signatures."
            Write-Host "  Install Android build-tools: & `"$installDep`" build-tools -AcceptAndroidSdkLicense"
            exit 1
        }
        $signer = 'jarsigner'
        $shownSdk = 'unknown'
        if ($targetSdk -gt 0) { $shownSdk = "$targetSdk" }
        Write-Warn "**************************************************************************"
        Write-Warn "apksigner not found - signing with jarsigner (v1 signature ONLY)."
        Write-Warn "targetSdk: $shownSdk. Installs fail if it is 30 or higher."
        Write-Warn "Install Android build-tools: & `"$installDep`" build-tools -AcceptAndroidSdkLicense"
        Write-Warn "**************************************************************************"
    } else {
        Write-Fail "Neither apksigner nor jarsigner found."
        Write-Host "  Install Android build-tools: & `"$installDep`" build-tools -AcceptAndroidSdkLicense (or use -NoSign)"
        exit 1
    }
}
if ($isXapk -and $doSign -and $signer -ne 'apksigner') {
    Write-Fail "XAPK rebuild requires apksigner for APK Signature Scheme v2/v3."
    exit 1
}

# zipalign: PATH, then SDK build-tools; prefer one that supports -P (16 KB pages)
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
$zipalignExe = $null
$zipalignPage = ''
foreach ($za in $zaCandidates) {
    if ((Get-ToolOutput @($za) @()) -match '-P <pagesize') {
        $zipalignExe = $za; $zipalignPage = '16k'; break
    }
    if (-not $zipalignExe) { $zipalignExe = $za; $zipalignPage = '4k' }
}

function Invoke-Zipalign {
    param([string]$In, [string]$Out)
    if ($zipalignPage -eq '16k') {
        return (Invoke-Tool @($zipalignExe) @('-f', '-P', '16', '4', $In, $Out))
    }
    return (Invoke-Tool @($zipalignExe) @('-f', '-p', '4', $In, $Out))
}

if ($Keystore -and (Test-Path -LiteralPath $Keystore)) { $Keystore = (Get-Item -LiteralPath $Keystore).FullName }

# Work on safe paths (see Test-UnsafePath): junction for the source dir, temp files
$workDir = Join-Path $env:TEMP "apk-rebuild-$(Get-Random)"
New-Item -ItemType Directory -Path $workDir -Force | Out-Null
$srcDir = $decodedAbs
$junction = $null
$needPageAlign = $false

try {
    # Every path is absolute from here on: run the tools from the (safe) work dir
    Push-Location -LiteralPath $workDir
    if (Test-UnsafePath $decodedAbs) {
        $junction = Join-Path $workDir 'src'
        New-Item -ItemType Junction -Path $junction -Target $decodedAbs | Out-Null
        $srcDir = $junction
    }

    # =================================================================
    # Step 1: Build APK with apktool
    # =================================================================
    Write-Host "=== Rebuilding APK ==="
    Write-Host "Source: $decodedAbs"
    Write-Host "Output: $outputAbs"
    Write-Host ""
    Write-Info "Running apktool build..."

    Get-ChildItem -LiteralPath $decodedAbs -Recurse -File -Filter '*.smali.bak' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $builtApk = Join-Path $workDir 'built.apk'
    $rc = Invoke-Tool $apktool @('b', $srcDir, '-o', $builtApk)
    if ($rc -ne 0 -or -not (Test-Path -LiteralPath $builtApk)) {
        Write-Fail "apktool build failed."
        Write-Host "Tip: If this is a framework error, delete %LOCALAPPDATA%\apktool\framework\1.apk and retry."
        Write-Host "Tip: Resource errors on a split bundle decoded with -KeepSplits are expected (@null);"
        Write-Host "     decode it again without -KeepSplits."
        exit 1
    }
    Write-Ok "APK built: $builtApk"
    Write-Host "BUILD_OK:$builtApk"

    # Stored .so + extractNativeLibs="false": must be page-aligned
    $storedSo = @(Get-StoredEntryOffsets $builtApk | Where-Object { $_.IsSo }).Count
    $manifest = Join-Path $decodedAbs 'AndroidManifest.xml'
    if ($storedSo -gt 0 -and (Test-Path -LiteralPath $manifest) -and (Select-String -LiteralPath $manifest -SimpleMatch 'android:extractNativeLibs="false"' -Quiet)) {
        $needPageAlign = $true
    }
    if ($needPageAlign -and -not $zipalignExe) {
        Write-Fail "zipalign is required: $storedSo stored native librar(y/ies) with extractNativeLibs=`"false`" must be page-aligned."
        Write-Host "  Install Android build-tools: & `"$installDep`" build-tools -AcceptAndroidSdkLicense"
        exit 1
    }
    if ($doZipalign -and -not $zipalignExe) {
        Write-Warn "zipalign not found - skipping alignment (no stored native libraries need it)."
        $doZipalign = $false
    }
    if (-not $doZipalign -and $needPageAlign) {
        Write-Warn "-NoZipalign with $storedSo stored native librar(y/ies): the alignment check below decides."
    }

    # =================================================================
    # Step 2: Zipalign (before apksigner; jarsigner breaks alignment, so
    #         it is aligned after signing instead - see Step 3)
    # =================================================================
    $alignedApk = $builtApk
    if ($doZipalign -and $signer -ne 'jarsigner') {
        if ($zipalignPage -eq '16k') {
            Write-Info "Running zipalign -P 16 (16 KB page alignment for stored native libraries)..."
        } else {
            Write-Info "Running zipalign -p (4 KB page alignment; this zipalign has no -P 16)..."
        }
        $alignedApk = Join-Path $workDir 'aligned.apk'
        if ((Invoke-Zipalign $builtApk $alignedApk) -ne 0) {
            Write-Fail "zipalign failed."
            exit 1
        }
        Write-Ok "Zipaligned ($zipalignExe)"
        Write-Host "ZIPALIGN_OK:$zipalignPage"
    }

    # =================================================================
    # Step 3: Sign APK
    # =================================================================
    if (-not $doSign) {
        if (-not (Test-Alignment $alignedApk)) {
            Move-Output $alignedApk "$outputAbs.misaligned"
            Write-Host "  Output left for inspection only - do not install it: $outputAbs.misaligned" -ForegroundColor Red
            exit 1
        }
        Test-Abis $alignedApk
        Move-Output $alignedApk $outputAbs
        if ($isXapk) {
            Write-Ok "Unsigned base APK saved to: $outputAbs"
            Write-Host "BUILD_OK:$outputAbs"
            Write-Host ""
            Write-Host "WARNING: APK is unsigned and cannot be installed without signing."
            Write-Host "         XAPK assembly skipped (split APKs require signing for Android 7+)."
            Write-Host "         Split APKs are preserved in: $originDir\splits\"
        } else {
            Write-Ok "Unsigned APK saved to: $outputAbs"
            Write-Host "BUILD_OK:$outputAbs"
            Write-Host ""
            Write-Host "WARNING: APK is unsigned and cannot be installed without signing."
        }
        exit 0
    }

    $keystoreSource = ''
    $ks = $Keystore
    if ($keystoreMode -eq 'custom') {
        $keystoreSource = 'custom'
    } else {
        $ks = $UserKs
        $KeyAlias = 'key0'; $KeyPass = 'android'; $StorePass = 'android'
        if (Test-Path -LiteralPath $ks) {
            $keystoreSource = 'debug-user'
            Write-Info "Using the user-level neutralizer debug keystore: $ks"
        } else {
            New-Item -ItemType Directory -Path $UserKsDir -Force | Out-Null
            Write-Info "Generating the user-level neutralizer debug keystore (reused by later builds)..."
            $genKs = Join-Path $workDir 'new.keystore'
            $rc = Invoke-Tool @('keytool') @('-genkeypair', '-keystore', $genKs, '-alias', $KeyAlias,
                '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000',
                '-storepass', $StorePass, '-keypass', $KeyPass,
                '-dname', 'CN=SDK Neutralizer Debug Key, OU=Debug, O=Debug, L=Unknown, ST=Unknown, C=US') -Quiet
            if ($rc -ne 0 -or -not (Test-Path -LiteralPath $genKs)) {
                Write-Fail "keytool could not generate $ks"
                exit 1
            }
            # Atomic publish: File.Move fails if another build created the key first
            $tmpKs = Join-Path $UserKsDir ".neutralizer-debug.keystore.tmp.$PID"
            Copy-Item -LiteralPath $genKs -Destination $tmpKs -Force
            try {
                [System.IO.File]::Move($tmpKs, $ks)
                $keystoreSource = 'debug-generated'
                Write-Ok "Debug keystore generated: $ks"
            } catch {
                Remove-Item -LiteralPath $tmpKs -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path -LiteralPath $ks)) { throw }
                $keystoreSource = 'debug-user'
                Write-Info "Another build created the user-level keystore first - using it: $ks"
            }
        }
    }
    if (-not (Test-Path -LiteralPath $ks)) {
        Write-Fail "Keystore not found: $ks"
        exit 1
    }
    # The keystore path goes to Java too: stage it under a safe name if needed
    $ksForTools = $ks
    if (Test-UnsafePath $ks) {
        $ksForTools = Join-Path $workDir 'signing.keystore'
        Copy-Item -LiteralPath $ks -Destination $ksForTools
    }

    Write-Host "KEYSTORE_USED:$ks"
    Write-Host "KEYSTORE_SOURCE:$keystoreSource"
    Write-Host "KEYSTORE_ALIAS:$KeyAlias"
    Write-Info "Signing APK with $signer..."

    $finalTmp = Join-Path $workDir 'final.apk'
    if ($signer -eq 'apksigner') {
        $rc = Invoke-Tool $apksigner @('sign', '--ks', $ksForTools, '--ks-key-alias', $KeyAlias,
            '--ks-pass', "pass:$StorePass", '--key-pass', "pass:$KeyPass", '--out', $finalTmp, $alignedApk)
        if ($rc -ne 0) { Write-Fail "apksigner sign failed."; exit 1 }
    } else {
        $signedTmp = Join-Path $workDir 'signed.apk'
        $rc = Invoke-Tool @('jarsigner') @('-keystore', $ksForTools, '-storepass', $StorePass, '-keypass', $KeyPass,
            '-signedjar', $signedTmp, $alignedApk, $KeyAlias)
        if ($rc -ne 0) { Write-Fail "jarsigner failed."; exit 1 }
        if ($doZipalign) {
            Write-Info "Running zipalign after jarsigner..."
            if ((Invoke-Zipalign $signedTmp $finalTmp) -ne 0) { Write-Fail "zipalign failed."; exit 1 }
            Write-Host "ZIPALIGN_OK:$zipalignPage"
        } else {
            Move-Item -LiteralPath $signedTmp -Destination $finalTmp -Force
        }
    }
    if (-not (Test-Path -LiteralPath $finalTmp)) {
        Write-Fail "Signed APK not found."
        exit 1
    }

    # =================================================================
    # Step 4: Verify signature and alignment, then move into place
    # =================================================================
    Write-Info "Verifying signature..."
    $verified = $false
    if ($signer -eq 'apksigner') {
        if ((Invoke-Tool $apksigner @('verify', $finalTmp) -Quiet) -eq 0) {
            Write-Ok "Signature verified (apksigner)"
            $verified = $true
        } else {
            Write-Warn "Signature verification returned warnings (may still be installable)"
        }
    } else {
        if ((Invoke-Tool @('jarsigner') @('-verify', $finalTmp) -Quiet) -eq 0) {
            Write-Ok "Signature verified (jarsigner)"
            $verified = $true
        } else {
            Write-Warn "Signature verification returned warnings (may still be installable)"
        }
    }

    if (-not (Test-Alignment $finalTmp)) {
        Move-Output $finalTmp "$outputAbs.misaligned"
        Write-Host "  Output left for inspection only - do not install it: $outputAbs.misaligned" -ForegroundColor Red
        exit 1
    }
    Test-Abis $finalTmp

    Move-Output $finalTmp $outputAbs
    foreach ($stale in @("$outputAbs.misaligned", "$outputAbs.misaligned.idsig")) {
        if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Force }
    }
    Write-Ok "APK signed: $outputAbs"
    Write-Host "SIGN_OK:$outputAbs"
    if ($verified) { Write-Host "VERIFY_OK:$outputAbs" }

    # =================================================================
    # Step 5: XAPK assembly (deprecated -KeepSplits directories only)
    # =================================================================
    if ($isXapk) {
        Write-Host ""
        Write-Host "=== Assembling XAPK (deprecated) ==="
        $xapkWork = Join-Path $workDir 'xapk'
        New-Item -ItemType Directory -Path $xapkWork -Force | Out-Null
        $baseName = 'base.apk'
        $meta = Get-Content -LiteralPath (Join-Path $originDir 'metadata.json') -Raw
        if ($meta -match '"base_apk"\s*:\s*"([^"]*)"') { $baseName = $Matches[1] }
        # The signed base APK moves inside the XAPK
        Move-Item -LiteralPath $outputAbs -Destination (Join-Path $xapkWork $baseName) -Force
        if (Test-Path -LiteralPath "$outputAbs.idsig") { Remove-Item -LiteralPath "$outputAbs.idsig" -Force }
        Write-Info "Added signed base APK as $baseName"

        $splitsDir = Join-Path $originDir 'splits'
        if (Test-Path -LiteralPath $splitsDir) {
            foreach ($split in Get-ChildItem -LiteralPath $splitsDir -File -Filter '*.apk') {
                $splitSrc = Join-Path $workDir 'split-src.apk'
                Copy-Item -LiteralPath $split.FullName -Destination $splitSrc -Force
                $splitIn = $splitSrc
                if ($doZipalign) {
                    $splitIn = Join-Path $workDir 'split-in.apk'
                    if ((Invoke-Zipalign $splitSrc $splitIn) -ne 0) { Write-Fail "zipalign failed on split $($split.Name)"; exit 1 }
                }
                Write-Info "Signing split: $($split.Name)"
                $splitSigned = Join-Path $workDir 'split-signed.apk'
                $rc = Invoke-Tool $apksigner @('sign', '--ks', $ksForTools, '--ks-key-alias', $KeyAlias,
                    '--ks-pass', "pass:$StorePass", '--key-pass', "pass:$KeyPass",
                    '--out', $splitSigned, $splitIn)
                if ($rc -ne 0) { Write-Fail "apksigner failed on split $($split.Name)"; exit 1 }
                if (-not (Test-Alignment $splitSigned)) {
                    Write-Fail "Split $($split.Name) is misaligned after signing - XAPK not assembled."
                    exit 1
                }
                Move-Item -LiteralPath $splitSigned -Destination (Join-Path $xapkWork $split.Name) -Force
                foreach ($t in @("$splitSigned.idsig", $splitSrc, (Join-Path $workDir 'split-in.apk'))) {
                    if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Force }
                }
                Write-Host "SPLIT_SIGNED:$($split.Name)"
            }
        }
        $manifestJson = Join-Path $originDir 'manifest.json'
        if (Test-Path -LiteralPath $manifestJson) { Copy-Item -LiteralPath $manifestJson -Destination $xapkWork }
        foreach ($icon in @('icon.png', 'icon.jpg')) {
            $iconPath = Join-Path $originDir $icon
            if (Test-Path -LiteralPath $iconPath) { Copy-Item -LiteralPath $iconPath -Destination $xapkWork; break }
        }

        $xapkTmp = Join-Path $workDir 'out.xapk'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($xapkWork, $xapkTmp,
            [System.IO.Compression.CompressionLevel]::NoCompression, $false)
        Move-Item -LiteralPath $xapkTmp -Destination $outputAbs -Force
        if (Test-Path -LiteralPath "$outputAbs.idsig") { Remove-Item -LiteralPath "$outputAbs.idsig" -Force }
        Write-Ok "XAPK assembled: $outputAbs"
        Write-Host "XAPK_ASSEMBLED:$outputAbs"
    }

    # =================================================================
    # Summary
    # =================================================================
    Write-Host ""
    Write-Host "=== Rebuild Complete ==="
    if ($isXapk) {
        Write-Host "Output XAPK (deprecated format): $outputAbs"
    } elseif (Test-Path -LiteralPath $mergeMeta) {
        Write-Host "Output APK (split bundle merged with APKEditor): $outputAbs"
    } else {
        Write-Host "Output APK: $outputAbs"
    }
    switch ($keystoreSource) {
        'debug-user'      { $signDesc = "user-level neutralizer debug key ($ks)" }
        'debug-generated' { $signDesc = "new user-level neutralizer debug key ($ks)" }
        default           { $signDesc = "custom keystore ($ks)" }
    }
    Write-Host "Signed with: $signer ($signDesc)"
    Write-Host "Output size: $((Get-Item -LiteralPath $outputAbs).Length) bytes"
    Write-Host ""
    Write-Host "WARNING: Play Integrity / SafetyNet will FAIL - expected for enterprise sideloading."
    if ($isXapk) {
        Write-Host "Install via: adb install-multiple <base.apk> <split1.apk> <split2.apk> ..."
        Write-Host "         or: unzip the XAPK and run: adb install-multiple *.apk"
    } else {
        Write-Host "Install via: adb install `"$outputAbs`""
    }
} finally {
    Pop-Location
    if ($junction -and (Test-Path -LiteralPath $junction)) {
        # Remove only the junction, never the directory it points to
        [System.IO.Directory]::Delete($junction)
    }
    Remove-Tree $workDir
}
exit 0

} finally {
    if ($script:CallerOutputEncoding) {
        try { [Console]::OutputEncoding = $script:CallerOutputEncoding } catch { }
    }
}
