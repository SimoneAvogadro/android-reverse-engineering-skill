# fingerprint.ps1: Triage an APK/XAPK before decompiling (PowerShell port of fingerprint.sh)
param(
    [Parameter(Position = 0)]
    [string]$Input,
    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Show-Usage {
    Write-Host @"
Usage: fingerprint.ps1 <file.apk|file.xapk>

Prints a one-screen summary:
  * mobile framework (with rationale)
  * HTTP / DI / serialization stack hints
  * obfuscation indicator
  * native libraries (consolidated across split APKs)
  * notable third-party SDKs found in assets/
"@
    exit 0
}

if ($Help) { Show-Usage }
if (-not $Input) { Show-Usage }
if (-not (Test-Path $Input)) {
    Write-Host "File not found: $Input" -ForegroundColor Red
    exit 1
}

$ext = [IO.Path]::GetExtension($Input).ToLower()
if ($ext -notin @('.apk', '.xapk', '.apks', '.apkm')) {
    Write-Host "Unsupported input: $Input" -ForegroundColor Red
    exit 1
}

$tmp = Join-Path $env:TEMP "apkfp-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $apks = @()
    if ($ext -eq '.apk') {
        $apks = @((Resolve-Path $Input).Path)
    } else {
        $xapkDir = Join-Path $tmp 'xapk'
        New-Item -ItemType Directory -Path $xapkDir -Force | Out-Null
        [System.IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path $Input).Path, $xapkDir)
        $apks = Get-ChildItem -Path $xapkDir -Recurse -Filter '*.apk' -File |
            Where-Object {
                $rel = $_.FullName.Substring($xapkDir.Length).TrimStart('\', '/')
                ($rel -split '[\\/]').Count -le 2
            } |
            Select-Object -ExpandProperty FullName
    }

    if ($apks.Count -eq 0) {
        Write-Host "No APK files found in input." -ForegroundColor Red
        exit 1
    }

    $listing = [System.Collections.Generic.List[string]]::new()
    $dexStrings = [System.Collections.Generic.HashSet[string]]::new()

    function Get-ZipEntries {
        param([string]$ZipPath)
        try {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
            try {
                return $zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') }
            } finally {
                $zip.Dispose()
            }
        } catch {
            return @()
        }
    }

    function Get-DexTypeStrings {
        param([byte[]]$Bytes)
        $text = [System.Text.Encoding]::ASCII.GetString($Bytes)
        $matches = [regex]::Matches($text, 'L[a-z][a-zA-Z0-9_]*(/[a-zA-Z0-9_$]+)+;')
        $result = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($m in $matches) {
            $fqn = $m.Value.TrimStart('L').TrimEnd(';')
            if ($fqn.Length -ge 8) { [void]$result.Add($fqn) }
        }
        return $result
    }

    foreach ($apk in $apks) {
        $entries = Get-ZipEntries -ZipPath $apk
        foreach ($e in $entries) { $listing.Add($e) }

        $dexEntries = $entries | Where-Object { $_ -match '^classes[0-9]*\.dex$' }
        foreach ($dexName in $dexEntries) {
            try {
                $zip = [System.IO.Compression.ZipFile]::OpenRead($apk)
                try {
                    $entry = $zip.GetEntry($dexName)
                    if (-not $entry) { continue }
                    $ms = New-Object System.IO.MemoryStream
                    try {
                        $stream = $entry.Open()
                        try { $stream.CopyTo($ms) } finally { $stream.Dispose() }
                        foreach ($s in (Get-DexTypeStrings -Bytes $ms.ToArray())) {
                            [void]$dexStrings.Add($s)
                        }
                    } finally {
                        $ms.Dispose()
                    }
                } finally {
                    $zip.Dispose()
                }
            } catch { }
        }
    }

    $listingText = ($listing | Sort-Object -Unique) -join "`n"
    $dexText = ($dexStrings | Sort-Object) -join "`n"

    function Test-Has {
        param([string]$Pattern)
        if ($listingText -match $Pattern) { return $true }
        if ($dexText -match $Pattern) { return $true }
        return $false
    }

    $framework = 'unknown'
    $rationale = ''

    if (Test-Has '^lib/[^/]+/libflutter\.so$') {
        $framework = 'Flutter'
        $rationale = 'lib/<abi>/libflutter.so present'
        if (Test-Has '^lib/[^/]+/libapp\.so$') { $rationale += '; libapp.so contains AOT-compiled Dart' }
    } elseif ((Test-Has '^lib/[^/]+/libhermes\.so$') -or (Test-Has '^assets/index\.android\.bundle$') -or (Test-Has '^lib/[^/]+/libreactnativejni\.so$')) {
        $framework = 'React Native'
        $reasons = @()
        if (Test-Has '^lib/[^/]+/libhermes\.so$') { $reasons += 'libhermes.so' }
        if (Test-Has '^lib/[^/]+/libreactnativejni\.so$') { $reasons += 'libreactnativejni.so' }
        if (Test-Has '^assets/index\.android\.bundle$') { $reasons += 'assets/index.android.bundle' }
        $rationale = $reasons -join ' '
    } elseif ((Test-Has '^assets/www/index\.html$') -or (Test-Has '^assets/www/cordova\.js$') -or (Test-Has '^assets/public/index\.html$')) {
        $framework = 'Cordova / Capacitor (WebView hybrid)'
        $rationale = 'assets/www/ or assets/public/ shell present'
    } elseif ((Test-Has '^lib/[^/]+/libmonodroid\.so$') -or (Test-Has '^assemblies/')) {
        $framework = 'Xamarin / .NET MAUI'
        $rationale = 'libmonodroid.so or assemblies/ present; code is in .NET DLLs'
    } elseif (Test-Has '^lib/[^/]+/libmaui\.so$') {
        $framework = '.NET MAUI'
        $rationale = 'libmaui.so present'
    } elseif ((Test-Has '^assets/flutter_assets/') -and -not (Test-Has '^lib/[^/]+/libflutter\.so$')) {
        $framework = 'Flutter (code-only split?)'
        $rationale = 'flutter_assets/ but no libflutter.so in this APK; check splits'
    } else {
        if (Test-Has 'androidx\.compose') {
            $framework = 'Native Android (Kotlin + Jetpack Compose)'
            $rationale = 'androidx.compose.* libraries detected'
        } elseif (Test-Has '^META-INF/.*\.kotlin_module$') {
            $framework = 'Native Android (Kotlin)'
            $rationale = 'kotlin_module metadata present, no Compose markers'
        } else {
            $framework = 'Native Android (Java/Kotlin)'
            $rationale = 'no cross-platform framework markers found'
        }
    }

    $http = @()
    if (Test-Has 'retrofit2') { $http += 'Retrofit' }
    if (Test-Has 'okhttp3') { $http += 'OkHttp' }
    if (Test-Has 'io/ktor/') { $http += 'Ktor' }
    if (Test-Has 'com/apollographql/') { $http += 'Apollo (GraphQL)' }
    if (Test-Has 'com/android/volley') { $http += 'Volley' }

    $di = @()
    if (Test-Has 'dagger/hilt/') { $di += 'Hilt' }
    if (Test-Has '^META-INF/.*dagger.*') { $di += 'Dagger' }
    if (Test-Has 'org/koin/') { $di += 'Koin' }
    if ($di.Count -eq 0 -and (Test-Has 'javax/inject/')) { $di += 'javax.inject' }

    $ser = @()
    if (Test-Has 'kotlinx/serialization/') { $ser += 'kotlinx.serialization' }
    if (Test-Has 'com/google/gson/') { $ser += 'Gson' }
    if (Test-Has 'com/squareup/moshi/') { $ser += 'Moshi' }
    if (Test-Has 'com/fasterxml/jackson/') { $ser += 'Jackson' }

    $shortDirs = ([regex]::Matches($listingText, '(?m)^[a-z]{1,2}/') | ForEach-Object { $_.Value } | Sort-Object -Unique).Count
    if ($shortDirs -gt 30) {
        $obfuscation = "HIGH ($shortDirs single/double-letter dirs at root)"
    } elseif ($shortDirs -gt 10) {
        $obfuscation = "MODERATE ($shortDirs short root dirs)"
    } else {
        $obfuscation = 'LOW (no significant short-name namespace pollution)'
    }

    $native = [regex]::Matches($listingText, '(?m)^lib/[^/]+/[^/]+\.so$') |
        ForEach-Object { $_.Value } | Sort-Object -Unique

    $sdks = @()
    if (Test-Has '^assets/com/appsflyer/') { $sdks += 'AppsFlyer' }
    if ((Test-Has 'datadog\.buildId') -or (Test-Has 'com/datadog/')) { $sdks += 'Datadog' }
    if (Test-Has 'io/sentry/') { $sdks += 'Sentry' }
    if (Test-Has 'com/google/firebase/') { $sdks += 'Firebase' }
    if (Test-Has 'com/google/android/gms/') { $sdks += 'Google Play Services' }
    if (Test-Has 'com/facebook/') { $sdks += 'Facebook SDK' }
    if (Test-Has 'com/payu/') { $sdks += 'PayU' }
    if (Test-Has 'com/stripe/') { $sdks += 'Stripe' }
    if (Test-Has 'com/braintreepayments/') { $sdks += 'Braintree' }
    if (Test-Has 'com/storyteller/') { $sdks += 'Storyteller' }
    if (Test-Has 'zendesk/') { $sdks += 'Zendesk' }
    if (Test-Has 'com/intercom/') { $sdks += 'Intercom' }
    if (Test-Has 'com/segment/analytics') { $sdks += 'Segment' }
    if (Test-Has 'com/amplitude/') { $sdks += 'Amplitude' }
    if (Test-Has 'com/mixpanel/') { $sdks += 'Mixpanel' }
    if (Test-Has 'com/onesignal/') { $sdks += 'OneSignal' }
    if (Test-Has 'com/microsoft/clarity') { $sdks += 'Microsoft Clarity' }
    if (Test-Has 'com/hotjar/') { $sdks += 'Hotjar' }
    if (Test-Has 'com/instabug/') { $sdks += 'Instabug' }

    $buildConfig = if (Test-Has 'BuildConfig\.class$') {
        'present (grep BuildConfig.java after decompile for base URLs / flavor)'
    } else {
        'not detected in zip listing (still worth grepping after decompile)'
    }

    $baseName = [IO.Path]::GetFileName($Input)
    Write-Host "=== APK Fingerprint: $baseName ==="
    Write-Host ""
    Write-Host "Framework:        $framework"
    Write-Host "  Rationale:      $rationale"
    Write-Host "Obfuscation:      $obfuscation"
    Write-Host ""
    Write-Host "HTTP stack:       $(if ($http.Count) { $http -join ' ' } else { 'none detected' })"
    Write-Host "DI:               $(if ($di.Count) { $di -join ' ' } else { 'none detected' })"
    Write-Host "Serialization:    $(if ($ser.Count) { $ser -join ' ' } else { 'none detected' })"
    Write-Host "BuildConfig:      $buildConfig"
    Write-Host ""
    Write-Host "Third-party SDKs: $(if ($sdks.Count) { $sdks -join ' ' } else { 'none detected' })"
    Write-Host ""
    Write-Host "Native libraries (consolidated across splits):"
    if ($native.Count) {
        $native | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "  (none)"
    }
    Write-Host ""
    Write-Host "Recommended next step:"
    switch -Regex ($framework) {
        '^Flutter' {
            Write-Host "  Java decompilation will yield ~no app code. The Dart logic lives in"
            Write-Host "  libapp.so (AOT). Use tools designed for Flutter:"
            Write-Host "    - reFlutter / Doldrums / blutter (extract Dart class structure)"
            Write-Host "    - strings/rabin2 on libapp.so for endpoints & string constants"
        }
        '^React' {
            Write-Host "  Java code is just the RN host. Real app logic is in JS/Hermes:"
            Write-Host "    - if Hermes: hbctool disasm assets/index.android.bundle"
            Write-Host "    - if JSC:    js-beautify the bundle and grep for fetch/axios"
        }
        '^Cordova' {
            Write-Host "  All app code is in assets/www/ (or assets/public/). Just unzip and"
            Write-Host "  inspect the HTML/JS; no Java decompile needed."
        }
        '^(Xamarin|\.NET)' {
            Write-Host "  App logic is in .NET DLLs (assemblies/). Use ILSpy or dotPeek;"
            Write-Host "  jadx will only show the Mono host."
        }
        default {
            Write-Host "  Proceed with Phase 2: decompile.ps1 <file>"
        }
    }
} finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
