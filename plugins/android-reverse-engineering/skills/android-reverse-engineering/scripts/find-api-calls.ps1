# find-api-calls.ps1 — Search decompiled source for API calls and HTTP endpoints
param(
    [Parameter(Position=0)]
    [string]$SourceDir,
    [switch]$Retrofit,
    [switch]$OkHttp,
    [switch]$Volley,
    [switch]$Urls,
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
  -Volley         Search only for Volley patterns
  -Urls           Search only for hardcoded URLs
  -Auth           Search only for auth-related patterns
  -All            Search all patterns (default)
  -Help           Show this help message

Output:
  Results are printed as file:line:match for easy navigation.
"@
    exit 0
}

if ($Help) { Show-Usage }

if (-not $SourceDir) {
    Write-Host "Error: No source directory specified." -ForegroundColor Red
    Show-Usage
}

if (-not (Test-Path $SourceDir)) {
    Write-Host "Error: Directory not found: $SourceDir" -ForegroundColor Red
    exit 1
}

# Default to all if no specific flag set
$searchAll = (-not $Retrofit -and -not $OkHttp -and -not $Volley -and -not $Urls -and -not $Auth) -or $All

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "==== $Title ===="
    Write-Host ""
}

function Search-Sources {
    param([string]$Pattern)
    Get-ChildItem -Path $SourceDir -Recurse -Include '*.java','*.kt' -File |
        Select-String -Pattern $Pattern -ErrorAction SilentlyContinue |
        ForEach-Object {
            "$($_.Path):$($_.LineNumber):$($_.Line.Trim())"
        }
}

# --- Retrofit ---
if ($searchAll -or $Retrofit) {
    Write-Section "Retrofit Annotations"
    Search-Sources '@(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|HTTP)\s*\('

    Write-Section "Retrofit Headers & Parameters"
    Search-Sources '@(Headers|Header|Query|QueryMap|Path|Body|Field|FieldMap|Part|PartMap|Url)\s*\('

    Write-Section "Retrofit Base URL"
    Search-Sources '(baseUrl|base_url)\s*\('
}

# --- OkHttp ---
if ($searchAll -or $OkHttp) {
    Write-Section "OkHttp Request Building"
    Search-Sources '(Request\.Builder|HttpUrl|\.newCall|\.enqueue|addInterceptor|addNetworkInterceptor)'

    Write-Section "OkHttp URL Construction"
    Search-Sources '(\.url\s*\(|\.addQueryParameter|\.addPathSegment|\.scheme\s*\(|\.host\s*\()'
}

# --- Volley ---
if ($searchAll -or $Volley) {
    Write-Section "Volley Requests"
    Search-Sources '(StringRequest|JsonObjectRequest|JsonArrayRequest|ImageRequest|RequestQueue|Volley\.newRequestQueue)'
}

# --- Hardcoded URLs ---
if ($searchAll -or $Urls) {
    Write-Section "Hardcoded URLs (http:// and https://)"
    Search-Sources '"https?://[^"]+'

    Write-Section "HttpURLConnection"
    Search-Sources '(openConnection|setRequestMethod|HttpURLConnection|HttpsURLConnection)'

    Write-Section "WebView URLs"
    Search-Sources '(loadUrl|loadData|evaluateJavascript|addJavascriptInterface|WebViewClient|WebChromeClient)'
}

# --- Auth patterns ---
if ($searchAll -or $Auth) {
    Write-Section "Authentication & API Keys"
    Search-Sources '(?i)(api[_\-]?key|auth[_\-]?token|bearer|authorization|x-api-key|client[_\-]?secret|access[_\-]?token)'

    Write-Section "Base URLs and Constants"
    Search-Sources '(?i)(BASE_URL|API_URL|SERVER_URL|ENDPOINT|API_BASE|HOST_NAME)'
}

Write-Host ""
Write-Host "=== Search complete ==="
