# find-api-calls.ps1: Search decompiled source for API calls and HTTP endpoints
param(
    [Parameter(Position = 0)]
    [string]$SourceDir,
    [switch]$Retrofit,
    [switch]$OkHttp,
    [switch]$Ktor,
    [switch]$Apollo,
    [switch]$Volley,
    [switch]$Urls,
    [switch]$Paths,
    [switch]$Auth,
    [switch]$All,
    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    Write-Host @"
Usage: find-api-calls.ps1 <source-dir> [OPTIONS]

Search decompiled Java/Kotlin source for HTTP API calls and endpoints.

Arguments:
  <source-dir>    Path to the decompiled sources directory

Options:
  -Retrofit       Search only for Retrofit annotations
  -OkHttp         Search only for OkHttp patterns
  -Ktor           Search only for Ktor client patterns
  -Apollo         Search only for Apollo (GraphQL) patterns
  -Volley         Search only for Volley patterns
  -Urls           Search only for hardcoded URLs
  -Paths          Extract unique endpoint-shaped path string literals
  -Auth           Search only for auth-related patterns
  -All            Search all patterns (default)
  -Help           Show this help message

Output:
  Results are printed as file:line:match for easy navigation.
"@
    exit 0
}

if ($Help) { Show-Usage }
if (-not $SourceDir) { Show-Usage }
if (-not (Test-Path $SourceDir -PathType Container)) {
    Write-Host "Error: Directory not found: $SourceDir" -ForegroundColor Red
    exit 1
}

$searchAll = (-not $Retrofit -and -not $OkHttp -and -not $Ktor -and -not $Apollo -and -not $Volley -and -not $Urls -and -not $Paths -and -not $Auth) -or $All

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "==== $Title ===="
    Write-Host ""
}

function Search-Sources {
    param([string]$Pattern)
    Get-ChildItem -Path $SourceDir -Recurse -Include '*.java', '*.kt' -File |
        Select-String -Pattern $Pattern -ErrorAction SilentlyContinue |
        ForEach-Object { "$($_.Path):$($_.LineNumber):$($_.Line.Trim())" }
}

function Get-AllSourceLines {
    Get-ChildItem -Path $SourceDir -Recurse -Include '*.java', '*.kt' -File |
        Select-String -Pattern '.' -ErrorAction SilentlyContinue
}

if ($searchAll) {
    Write-Section "Summary (counted in a single pass)"
    $h = @{
        retrofit = 0; okhttp = 0; ktor = 0; apollo = 0; volley = 0
        hilt = 0; koin = 0; bearer = 0; hmac = 0
    }
    $summaryPattern = '@(GET|POST|PUT|DELETE|PATCH|HTTP)\(|Request\.Builder|HttpUrl|\.newCall\(|BearerTokens|defaultRequest \{|client\.(get|post)\(|httpClient\.(get|post)\(|ApolloClient|\.serverUrl\(|StringRequest|JsonObjectRequest|RequestQueue|@HiltAndroidApp|@AndroidEntryPoint|@HiltViewModel|@Provides|@Binds|org\.koin\.|module \{|single<|factory<|"[Bb]earer |HmacSHA|Mac\.getInstance'
    foreach ($hit in (Get-ChildItem -Path $SourceDir -Recurse -Include '*.java', '*.kt' -File | Select-String -Pattern $summaryPattern -ErrorAction SilentlyContinue)) {
        $line = $hit.Line
        if ($line -match '@(GET|POST|PUT|DELETE|PATCH|HTTP)\(') { $h.retrofit++ }
        if ($line -match 'Request\.Builder|HttpUrl|\.newCall\(') { $h.okhttp++ }
        if ($line -match 'BearerTokens|defaultRequest \{|client\.(get|post)\(|httpClient\.(get|post)\(|HttpClient\.get\(') { $h.ktor++ }
        if ($line -match 'ApolloClient|\.serverUrl\(') { $h.apollo++ }
        if ($line -match 'StringRequest|JsonObjectRequest|RequestQueue') { $h.volley++ }
        if ($line -match '@HiltAndroidApp|@AndroidEntryPoint|@HiltViewModel|@Provides|@Binds') { $h.hilt++ }
        if ($line -match 'org\.koin\.|module \{|single<|factory<|singleOf\(|factoryOf\(') { $h.koin++ }
        if ($line -match '"Bearer |"bearer |BearerTokens') { $h.bearer++ }
        if ($line -match 'HmacSHA|Mac\.getInstance\("Hmac') { $h.hmac++ }
    }
    Write-Host ("  HTTP framework:   Retrofit={0,-5} OkHttp={1,-5} Ktor={2,-5} Apollo={3,-5} Volley={4,-5}" -f $h.retrofit, $h.okhttp, $h.ktor, $h.apollo, $h.volley)
    Write-Host ("  DI framework:     Hilt/Dagger={0,-5} Koin={1,-5}" -f $h.hilt, $h.koin)
    Write-Host ("  Auth signals:     Bearer={0,-5} HMAC/Sign={1,-5}" -f $h.bearer, $h.hmac)
    Write-Host ""
    Write-Host "  Run with one of -Retrofit / -OkHttp / -Ktor / -Apollo / -Volley /"
    Write-Host "  -Paths / -Urls / -Auth to inspect a single section."
}

if ($searchAll -or $Retrofit) {
    Write-Section "Retrofit Annotations"
    Search-Sources '@(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|HTTP)\s*\('
    Write-Section "Retrofit Headers & Parameters"
    Search-Sources '@(Headers|Header|Query|QueryMap|Path|Body|Field|FieldMap|Part|PartMap|Url)\s*\('
    Write-Section "Retrofit Base URL"
    Search-Sources '(baseUrl|base_url)\s*\('
}

if ($searchAll -or $OkHttp) {
    Write-Section "OkHttp Request Building"
    Search-Sources '(Request\.Builder|HttpUrl|\.newCall|\.enqueue|addInterceptor|addNetworkInterceptor)'
    Write-Section "OkHttp URL Construction"
    Search-Sources '(\.url\s*\(|\.addQueryParameter|\.addPathSegment|\.scheme\s*\(|\.host\s*\()'
}

if ($searchAll -or $Ktor) {
    Write-Section "Ktor: Client Calls"
    Search-Sources '\b(client|httpClient|HttpClient)\.(get|post|put|delete|patch|head|request)\s*[<(]'
    Write-Section "Ktor: Request Building / Default Request"
    Search-Sources '(HttpRequestBuilder|defaultRequest\s*\{|\burl\s*\(\s*"|URLBuilder|URLProtocol)'
    Write-Section "Ktor: Auth Plugin (Bearer / Refresh)"
    Search-Sources '(\bbearer\s*\{|BearerTokens\s*\(|loadTokens\s*\{|refreshTokens\s*\{|\bAuth\s*\)\s*\{)'
}

if ($searchAll -or $Apollo) {
    Write-Section "Apollo: GraphQL Client"
    Search-Sources '(ApolloClient|\.serverUrl\s*\(|\.subscriptionNetworkTransport|HttpNetworkTransport)'
    Write-Section "Apollo: Operations"
    Search-Sources '(\.query\s*\(\s*[A-Z]|\.mutation\s*\(\s*[A-Z]|\.subscription\s*\(\s*[A-Z])'
}

if ($searchAll -or $Volley) {
    Write-Section "Volley Requests"
    Search-Sources '(StringRequest|JsonObjectRequest|JsonArrayRequest|ImageRequest|RequestQueue|Volley\.newRequestQueue)'
}

if ($searchAll -or $Paths) {
    Write-Section "Endpoint-Shaped Path Literals (deduplicated)"
    $seg = '[A-Za-z0-9_{}.\-]+'
    $root = '(api|v[0-9]+|graphql|rest|mobile|auth|oauth|sso|users?|account|session|token|register|signup|signin|logout|password|verify|otp|sms|profile|customer|cart|basket|order|checkout|payment|invoice|product|catalog|inventory|search|category|favo[u]?rites?|wishlist|address|location|delivery|shipping|review|feedback|notification|push|message|chat|track|event|stat[a-z]*|metric|config|settings?|feature|flag|banner|content|media|upload|download|file|image|video|live|stream|webhook|callback)'
    $pathsRegex = "`"(/$seg(/$seg)+/?|$root(/$seg)+/?)`""
    $exclude = '^(image|video|audio|text|application|content|font|model|multipart|message)/|^/(proc|sys|dev|tmp|etc|usr|var|opt)/'
    $allPaths = [System.Collections.Generic.HashSet[string]]::new()
    Get-ChildItem -Path $SourceDir -Recurse -Include '*.java', '*.kt' -File | ForEach-Object {
        $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
        if ($content) {
            [regex]::Matches($content, $pathsRegex) | ForEach-Object {
                $val = $_.Value.Trim('"')
                if ($val -notmatch $exclude) { [void]$allPaths.Add($_.Value) }
            }
        }
    }
    $allPaths | Sort-Object | ForEach-Object { Write-Host $_ }
    Write-Host ""
    Write-Section "Endpoint-Shaped Path Literals: call sites"
    Search-Sources $pathsRegex
}

if ($searchAll -or $Urls) {
    $denylistPath = Join-Path $PSScriptRoot '..\references\third_party_hosts.txt'
    $strictUrl = 'https?://(([0-9]{1,3}(\.[0-9]{1,3}){3}|[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})(:[0-9]{1,5})?(/[^"<>[:space:]]*)?|[A-Za-z0-9-]+(:[0-9]{1,5}(/[^"<>[:space:]]*)?|/[^"<>[:space:]]*))'
    $validTlds = 'com|net|org|io|co|app|dev|me|ai|xyz|info|biz|gov|edu|mil|int|tech|cloud|uk|de|fr|it|es|nl|in|us|ca|au|jp|cn|br|ru|eu|ch|se|no|fi|dk|pl|pt|gr|ie|be|at|cz|sg|hk|kr|tw|mx|ar|cl|za|nz'

    $urlSet = [System.Collections.Generic.HashSet[string]]::new()
    Get-ChildItem -Path $SourceDir -Recurse -Include '*.java', '*.kt' -File | ForEach-Object {
        $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
        if ($content) {
            [regex]::Matches($content, $strictUrl) | ForEach-Object {
                $url = $_.Value
                $rest = $url -replace '^https?://', ''
                $host = ($rest -split '[/:]')[0]
                $hasPathPort = $rest -match '[/:]'
                $keep = $false
                if ($host -match '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$') { $keep = $true }
                elseif (($host -split '\.').Count -ge 3) { $keep = $true }
                elseif ($hasPathPort) { $keep = $true }
                else {
                    $parts = $host -split '\.'
                    if ($parts.Count -eq 2 -and $parts[1] -match "^($validTlds)$") { $keep = $true }
                }
                if ($keep) { [void]$urlSet.Add($url) }
            }
        }
    }
    $urls = $urlSet | Sort-Object
    $hosts = $urls | ForEach-Object { ($_ -replace '^https?://', '' -split '[/:]')[0] } | Sort-Object -Unique

    $denyRegex = $null
    if (Test-Path $denylistPath) {
        $denyLines = Get-Content $denylistPath | Where-Object { $_ -notmatch '^\s*(#|$)' }
        if ($denyLines) { $denyRegex = ($denyLines -join '|') }
    }

    $firstHosts = @()
    $thirdHosts = @()
    foreach ($h in $hosts) {
        if ($denyRegex -and $h -match $denyRegex) { $thirdHosts += $h }
        else { $firstHosts += $h }
    }

    Write-Section "Likely First-Party Hosts (frequency-sorted)"
    if ($firstHosts.Count) {
        $firstHosts | ForEach-Object {
            $host = $_
            $n = ($urls | Where-Object { $_ -match "://${([regex]::Escape($host))}([/:`"`]|$)" }).Count
            [PSCustomObject]@{ Count = $n; Host = $host }
        } | Sort-Object Count -Descending | ForEach-Object {
            Write-Host ("  {0,5}  {1}" -f $_.Count, $_.Host)
        }
    } else {
        Write-Host "  (none; every URL matched the third-party denylist)"
    }

    Write-Section "Third-Party Hosts (denylist matches, collapsed)"
    if ($thirdHosts.Count) { $thirdHosts | ForEach-Object { Write-Host "  $_" } }
    else { Write-Host "  (none)" }

    Write-Section "All First-Party URLs (full strings)"
    foreach ($h in $firstHosts) {
        $urls | Where-Object { $_ -match "://${([regex]::Escape($h))}([/:`"`]|$)" } | ForEach-Object { Write-Host "  $_" }
    }

    Write-Section "HttpURLConnection"
    Search-Sources '(openConnection|setRequestMethod|HttpURLConnection|HttpsURLConnection)'
    Write-Section "WebView URLs"
    Search-Sources '(loadUrl|loadData|evaluateJavascript|addJavascriptInterface|WebViewClient|WebChromeClient)'
}

if ($searchAll -or $Auth) {
    Write-Section "Authentication & API Keys"
    Search-Sources '(?i)(api[_\-]?key|auth[_\-]?token|bearer|authorization|x-api-key|client[_\-]?secret|access[_\-]?token|refresh[_\-]?token)'

    Write-Section "Request Signing (HMAC / signature schemes)"
    Search-Sources '(HmacSHA(1|256|512)|Mac\.getInstance\("Hmac|SecretKeySpec\(|Signature\.getInstance\()'
    Search-Sources '(?i)(x-signature|x-client-authorization|x-amz-signature|x-hmac|aws4-hmac|signRequest|signatureFor|computeSignature|signaturev[0-9])'

    Write-Section "Possible Hardcoded Secrets / Keys"
    Search-Sources '(?i)(app[_\-]?secret|client[_\-]?secret|signing[_\-]?key|hmac[_\-]?secret|consumer[_\-]?secret|private[_\-]?key)'

    Write-Section "Base URLs and Constants"
    Search-Sources '(?i)(BASE_URL|API_URL|SERVER_URL|ENDPOINT|API_BASE|HOST_NAME)'

    Write-Section "Ktor Auth (Bearer + Refresh)"
    Search-Sources '(BearerTokens|loadTokens\s*\{|refreshTokens\s*\{|\bbearer\s*\{)'
}

Write-Host ""
Write-Host "=== Search complete ==="
