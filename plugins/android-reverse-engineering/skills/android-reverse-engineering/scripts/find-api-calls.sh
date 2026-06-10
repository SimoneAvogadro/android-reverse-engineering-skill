#!/usr/bin/env bash
# find-api-calls.sh — Search decompiled source for API calls and HTTP endpoints
set -euo pipefail

usage() {
  cat <<EOF
Usage: find-api-calls.sh <source-dir> [OPTIONS]

Search decompiled Java/Kotlin source for HTTP API calls and endpoints.

Arguments:
  <source-dir>    Path to the decompiled sources directory

Options:
  --retrofit      Search only for Retrofit annotations
  --okhttp        Search only for OkHttp patterns
  --ktor          Search only for Ktor client patterns
  --apollo        Search only for Apollo (GraphQL) patterns
  --volley        Search only for Volley patterns
  --urls          Search only for hardcoded URLs
  --paths         Extract unique endpoint-shaped path string literals
                  (works on heavily obfuscated apps where call sites are inlined)
  --auth          Search only for auth-related patterns
  --all           Search all patterns (default)
  -h, --help      Show this help message

Output:
  Results are printed as file:line:match for easy navigation.
EOF
  exit 0
}

SOURCE_DIR=""
SEARCH_RETROFIT=false
SEARCH_OKHTTP=false
SEARCH_KTOR=false
SEARCH_APOLLO=false
SEARCH_VOLLEY=false
SEARCH_URLS=false
SEARCH_PATHS=false
SEARCH_AUTH=false
SEARCH_ALL=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --retrofit) SEARCH_RETROFIT=true; SEARCH_ALL=false; shift ;;
    --okhttp)   SEARCH_OKHTTP=true;   SEARCH_ALL=false; shift ;;
    --ktor)     SEARCH_KTOR=true;     SEARCH_ALL=false; shift ;;
    --apollo)   SEARCH_APOLLO=true;   SEARCH_ALL=false; shift ;;
    --volley)   SEARCH_VOLLEY=true;    SEARCH_ALL=false; shift ;;
    --urls)     SEARCH_URLS=true;      SEARCH_ALL=false; shift ;;
    --paths)    SEARCH_PATHS=true;     SEARCH_ALL=false; shift ;;
    --auth)     SEARCH_AUTH=true;      SEARCH_ALL=false; shift ;;
    --all)      SEARCH_ALL=true; shift ;;
    -h|--help)  usage ;;
    -*)         echo "Error: Unknown option $1" >&2; usage ;;
    *)          SOURCE_DIR="$1"; shift ;;
  esac
done

if [[ -z "$SOURCE_DIR" ]]; then
  echo "Error: No source directory specified." >&2
  usage
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Error: Directory not found: $SOURCE_DIR" >&2
  exit 1
fi

GREP_OPTS="-rn --include=*.java --include=*.kt"

section() {
  echo
  echo "==== $1 ===="
  echo
}

run_grep() {
  local pattern="$1"
  # shellcheck disable=SC2086
  grep $GREP_OPTS -E "$pattern" "$SOURCE_DIR" 2>/dev/null || true
}

# Print a one-screen summary FIRST so a reader knows what to expect from
# the long output that follows. Skipped when a single section flag was
# requested (the user wants raw matches, not an overview). One pass over
# the tree, counts bucketed by tag — running 8 separate greps was too slow.
if [[ "$SEARCH_ALL" == true ]]; then
  section "Summary (counted in a single pass)"
  declare -A H=(
    [retrofit]=0 [okhttp]=0 [ktor]=0 [apollo]=0 [volley]=0
    [hilt]=0 [koin]=0 [bearer]=0 [hmac]=0
  )
  while IFS= read -r line; do
    case "$line" in
      *"@GET("*|*"@POST("*|*"@PUT("*|*"@DELETE("*|*"@PATCH("*|*"@HTTP("*) H[retrofit]=$((H[retrofit]+1));;
    esac
    case "$line" in
      *"Request.Builder"*|*"HttpUrl"*|*".newCall("*) H[okhttp]=$((H[okhttp]+1));;
    esac
    case "$line" in
      *"BearerTokens"*|*"defaultRequest {"*|*"client.get("*|*"client.post("*|*"httpClient.get("*|*"httpClient.post("*|*"HttpClient.get("*) H[ktor]=$((H[ktor]+1));;
    esac
    case "$line" in
      *"ApolloClient"*|*".serverUrl("*) H[apollo]=$((H[apollo]+1));;
    esac
    case "$line" in
      *"StringRequest"*|*"JsonObjectRequest"*|*"RequestQueue"*) H[volley]=$((H[volley]+1));;
    esac
    case "$line" in
      *"@HiltAndroidApp"*|*"@AndroidEntryPoint"*|*"@HiltViewModel"*|*"@Provides"*|*"@Binds"*) H[hilt]=$((H[hilt]+1));;
    esac
    case "$line" in
      *"org.koin."*|*"module {"*|*"single<"*|*"factory<"*|*"singleOf("*|*"factoryOf("*) H[koin]=$((H[koin]+1));;
    esac
    case "$line" in
      *'"Bearer '*|*'"bearer '*|*"BearerTokens"*) H[bearer]=$((H[bearer]+1));;
    esac
    case "$line" in
      *"HmacSHA"*|*'Mac.getInstance("Hmac'*) H[hmac]=$((H[hmac]+1));;
    esac
  done < <(grep -rEh --include='*.java' --include='*.kt' \
      '@(GET|POST|PUT|DELETE|PATCH|HTTP)\(|Request\.Builder|HttpUrl|\.newCall\(|BearerTokens|defaultRequest \{|client\.(get|post)\(|httpClient\.(get|post)\(|ApolloClient|\.serverUrl\(|StringRequest|JsonObjectRequest|RequestQueue|@HiltAndroidApp|@AndroidEntryPoint|@HiltViewModel|@Provides|@Binds|org\.koin\.|module \{|single<|factory<|"[Bb]earer |HmacSHA|Mac\.getInstance' \
      "$SOURCE_DIR" 2>/dev/null || true)
  printf '  HTTP framework:   Retrofit=%-5s OkHttp=%-5s Ktor=%-5s Apollo=%-5s Volley=%-5s\n' \
      "${H[retrofit]}" "${H[okhttp]}" "${H[ktor]}" "${H[apollo]}" "${H[volley]}"
  printf '  DI framework:     Hilt/Dagger=%-5s Koin=%-5s\n' \
      "${H[hilt]}" "${H[koin]}"
  printf '  Auth signals:     Bearer=%-5s HMAC/Sign=%-5s\n' \
      "${H[bearer]}" "${H[hmac]}"
  echo
  echo "  Run with one of --retrofit / --okhttp / --ktor / --apollo / --volley /"
  echo "  --paths / --urls / --auth to inspect a single section."
fi

# --- Retrofit ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_RETROFIT" == true ]]; then
  section "Retrofit Annotations"
  run_grep '@(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|HTTP)\s*\('
  section "Retrofit Headers & Parameters"
  run_grep '@(Headers|Header|Query|QueryMap|Path|Body|Field|FieldMap|Part|PartMap|Url)\s*\('
  section "Retrofit Base URL"
  run_grep '(baseUrl|base_url)\s*\('
fi

# --- OkHttp ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_OKHTTP" == true ]]; then
  section "OkHttp Request Building"
  run_grep '(Request\.Builder|HttpUrl|\.newCall|\.enqueue|addInterceptor|addNetworkInterceptor)'
  section "OkHttp URL Construction"
  run_grep '(\.url\s*\(|\.addQueryParameter|\.addPathSegment|\.scheme\s*\(|\.host\s*\()'
fi

# --- Ktor (Kotlin) ---
# Ktor doesn't use annotations. Endpoints appear as string args to
# client.get/post/etc., or are built via HttpRequestBuilder.url(...). Auth
# is configured via the bearer { loadTokens / refreshTokens } DSL.
if [[ "$SEARCH_ALL" == true || "$SEARCH_KTOR" == true ]]; then
  section "Ktor — Client Calls"
  run_grep '\b(client|httpClient|HttpClient)\.(get|post|put|delete|patch|head|request)\s*[<(]'
  section "Ktor — Request Building / Default Request"
  run_grep '(HttpRequestBuilder|defaultRequest\s*\{|\burl\s*\(\s*"|URLBuilder|URLProtocol)'
  section "Ktor — Auth Plugin (Bearer / Refresh)"
  run_grep '(\bbearer\s*\{|BearerTokens\s*\(|loadTokens\s*\{|refreshTokens\s*\{|\bAuth\s*\)\s*\{)'
fi

# --- Apollo (GraphQL) ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_APOLLO" == true ]]; then
  section "Apollo — GraphQL Client"
  run_grep '(ApolloClient|\.serverUrl\s*\(|\.subscriptionNetworkTransport|HttpNetworkTransport)'
  section "Apollo — Operations"
  run_grep '(\.query\s*\(\s*[A-Z]|\.mutation\s*\(\s*[A-Z]|\.subscription\s*\(\s*[A-Z])'
fi

# --- Volley ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_VOLLEY" == true ]]; then
  section "Volley Requests"
  run_grep '(StringRequest|JsonObjectRequest|JsonArrayRequest|ImageRequest|RequestQueue|Volley\.newRequestQueue)'
fi

# --- Endpoint-shaped path literals ---
# Survives R8 obfuscation: even when call sites are inlined to a.b(c, "path"),
# the path strings themselves are not obfuscated. This produces a deduplicated
# inventory of likely API endpoints that other modes miss.
if [[ "$SEARCH_ALL" == true || "$SEARCH_PATHS" == true ]]; then
  section "Endpoint-Shaped Path Literals (deduplicated)"
  # Quoted strings that begin with /<segment> or <segment>/ where the leading
  # segment is a typical API root word. Cap segment count and length to keep
  # the regex grounded.
  # An endpoint-shaped string is one of:
  #   "/seg/seg..."                   — absolute path with >= 2 segments
  #   "api-root/seg/seg..."           — relative path starting with a known
  #                                     API root keyword and containing >= 1
  #                                     '/' followed by another segment
  # Segments are URL-safe chars plus {} for path-template placeholders.
  SEG='[A-Za-z0-9_{}.\-]+'
  ROOT='(api|v[0-9]+|graphql|rest|mobile|auth|oauth|sso|users?|account|session|token|register|signup|signin|logout|password|verify|otp|sms|profile|customer|cart|basket|order|checkout|payment|invoice|product|catalog|inventory|search|category|favo[u]?rites?|wishlist|address|location|delivery|shipping|review|feedback|notification|push|message|chat|track|event|stat[a-z]*|metric|config|settings?|feature|flag|banner|content|media|upload|download|file|image|video|live|stream|webhook|callback)'
  PATHS_REGEX="\"(/${SEG}(/${SEG})+/?|${ROOT}(/${SEG})+/?)\""
  # Filter out frequent false positives (MIME types, /proc, /sys, /dev).
  EXCLUDE='^"(image|video|audio|text|application|content|font|model|multipart|message)/|^"/(proc|sys|dev|tmp|etc|usr|var|opt)/'
  # Print a flat unique list rather than file:line — this is the inventory.
  grep -rhoE --include='*.java' --include='*.kt' "$PATHS_REGEX" "$SOURCE_DIR" 2>/dev/null \
      | grep -Ev "$EXCLUDE" \
      | sort -u || true
  echo
  section "Endpoint-Shaped Path Literals — call sites"
  grep $GREP_OPTS -E "$PATHS_REGEX" "$SOURCE_DIR" 2>/dev/null \
      | grep -Ev ":[0-9]+:.*${EXCLUDE#^}" || true
fi

# --- Hardcoded URLs ---
# A loose grep for http(s)://... drowns in compression-dictionary garbage and
# in third-party SDK URLs (Google, Firebase, AppsFlyer, Datadog, ...). The
# strict regex requires a syntactically valid hostname and rejects strings
# containing whitespace, angle brackets, or non-printable bytes. Hosts are
# then bucketed into "first-party candidates" vs "third-party (denylist)".
if [[ "$SEARCH_ALL" == true || "$SEARCH_URLS" == true ]]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  DENYLIST="$HERE/../references/third_party_hosts.txt"
  # Accept three host shapes, all rejecting whitespace / angle brackets /
  # non-printables in the path:
  #   * IPv4 literal (dev/staging endpoints, high signal)            192.168.0.1
  #   * dotted host: >=2 labels ending in a 2+ letter TLD (incl apex) example.com
  #   * bare single-label host, BUT only when followed by ':port' or  localhost:3000
  #     '/path' — keeps internal hosts (localhost, internal-backend)  svc/health
  #     while still dropping Kotlin-stdlib dictionary fragments like
  #     "http://An Introduction..." (bare word, no port/path follows).
  STRICT_URL='https?://(([0-9]{1,3}(\.[0-9]{1,3}){3}|[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,})(:[0-9]{1,5})?(/[^"<>[:space:]]*)?|[A-Za-z0-9-]+(:[0-9]{1,5}(/[^"<>[:space:]]*)?|/[^"<>[:space:]]*))'

  TMP="$(mktemp)"
  trap 'rm -f "$TMP"' EXIT
  # Extraction (STRICT_URL) is deliberately permissive; this awk pass drops the
  # residual Kotlin-stdlib dictionary noise WITHOUT losing the high-signal
  # shapes a strict-only regex discards (IPs, apex domains, internal hosts).
  # Decision table, top-down, on the host (authority before any :port / /path):
  #   * IPv4 literal                    -> keep  (dict fragments are words,
  #                                              never dotted-quads)
  #   * >=3 labels (sub.domain.tld)     -> keep  (any TLD; same tolerance the
  #                                              original strict regex had)
  #   * any host WITH a :port or /path  -> keep  (structured = high signal:
  #                                              localhost:3000, svc/health)
  #   * bare 2-label apex, no port/path -> keep ONLY if the TLD is a real one,
  #                                              compared as a whole field (kills
  #                                              "www.this" / "this.introduction",
  #                                              keeps "mytrackera-api.com")
  # Trade-off: a first-party host referenced bare with an uncommon TLD (e.g.
  # https://foo.store with no path) is dropped — give it a path/port, or add the
  # TLD to the list below, if you hit that case.
  { grep -rhoE --include='*.java' --include='*.kt' "$STRICT_URL" "$SOURCE_DIR" 2>/dev/null || true; } \
      | sort -u \
      | awk '
          { rest=$0; sub(/^https?:\/\//,"",rest)
            host=rest; sub(/[/:].*/,"",host)
            haspathport = (rest ~ /[/:]/)
            if (host ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { print; next }   # IPv4
            n = split(host, a, ".")
            if (n >= 3)      { print; next }                                 # sub.domain.tld
            if (haspathport) { print; next }                                 # has :port or /path
            if (n == 2 && a[2] ~ /^(com|net|org|io|co|app|dev|me|ai|xyz|info|biz|gov|edu|mil|int|tech|cloud|uk|de|fr|it|es|nl|in|us|ca|au|jp|cn|br|ru|eu|ch|se|no|fi|dk|pl|pt|gr|ie|be|at|cz|sg|hk|kr|tw|mx|ar|cl|za|nz)$/) print  # real apex TLD
          }' > "$TMP"

  # Extract host: strip scheme, take part up to first ':' or '/'.
  HOSTS_TMP="$(mktemp)"
  sed -E 's#^https?://##; s#[/:].*$##' "$TMP" | sort -u > "$HOSTS_TMP"

  if [[ -f "$DENYLIST" ]]; then
    # Build a single combined regex from the denylist (one line each).
    DENY_REGEX="$(grep -vE '^\s*(#|$)' "$DENYLIST" | tr '\n' '|' | sed 's/|$//')"
    THIRD_HOSTS=$(grep -E "$DENY_REGEX" "$HOSTS_TMP" || true)
    FIRST_HOSTS=$(grep -vE "$DENY_REGEX" "$HOSTS_TMP" || true)
  else
    THIRD_HOSTS=""
    FIRST_HOSTS=$(cat "$HOSTS_TMP")
  fi

  section "Likely First-Party Hosts (frequency-sorted)"
  if [[ -n "$FIRST_HOSTS" ]]; then
    while IFS= read -r h; do
      [[ -z "$h" ]] && continue
      n=$(grep -cE "://${h//./\\.}([/:\"]|$)" "$TMP" || true)
      printf '  %5d  %s\n' "$n" "$h"
    done <<< "$FIRST_HOSTS" | sort -rn -k1
  else
    echo "  (none — every URL matched the third-party denylist)"
  fi

  section "Third-Party Hosts (denylist matches, collapsed)"
  if [[ -n "$THIRD_HOSTS" ]]; then
    echo "$THIRD_HOSTS" | sed 's/^/  /'
  else
    echo "  (none)"
  fi

  section "All First-Party URLs (full strings)"
  if [[ -n "$FIRST_HOSTS" ]]; then
    while IFS= read -r h; do
      [[ -z "$h" ]] && continue
      grep -E "://${h//./\\.}([/:\"]|$)" "$TMP" | sed 's/^/  /'
    done <<< "$FIRST_HOSTS"
  fi

  rm -f "$HOSTS_TMP" "$TMP"
  trap - EXIT

  section "HttpURLConnection"
  run_grep '(openConnection|setRequestMethod|HttpURLConnection|HttpsURLConnection)'
  section "WebView URLs"
  run_grep '(loadUrl|loadData|evaluateJavascript|addJavascriptInterface|WebViewClient|WebChromeClient)'
fi

# --- Auth patterns ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_AUTH" == true ]]; then
  section "Authentication & API Keys"
  run_grep -i '(api[_-]?key|auth[_-]?token|bearer|authorization|x-api-key|client[_-]?secret|access[_-]?token|refresh[_-]?token)'

  # Request-signing schemes: a hardcoded HMAC / RSA secret in an APK is a
  # security finding worth surfacing prominently. These patterns catch the
  # common shapes of homegrown / SDK-issued request signers.
  section "Request Signing (HMAC / signature schemes)"
  run_grep '(HmacSHA(1|256|512)|Mac\.getInstance\("Hmac|SecretKeySpec\(|Signature\.getInstance\()'
  run_grep -i '(x-signature|x-client-authorization|x-amz-signature|x-hmac|aws4-hmac|signRequest|signatureFor|computeSignature|signaturev[0-9])'

  # Hardcoded high-entropy strings adjacent to "secret"/"key" assignments
  # are the canonical leaked-credential pattern.
  section "Possible Hardcoded Secrets / Keys"
  run_grep -i '(app[_-]?secret|client[_-]?secret|signing[_-]?key|hmac[_-]?secret|consumer[_-]?secret|private[_-]?key)'

  section "Base URLs and Constants"
  run_grep -i '(BASE_URL|API_URL|SERVER_URL|ENDPOINT|API_BASE|HOST_NAME)'

  # Ktor BearerTokens / refresh DSL — common on Kotlin apps and lives on
  # Ktor's public API, so it survives R8 unchanged.
  section "Ktor Auth (Bearer + Refresh)"
  run_grep '(BearerTokens|loadTokens\s*\{|refreshTokens\s*\{|\bbearer\s*\{)'
fi

echo
echo "=== Search complete ==="
