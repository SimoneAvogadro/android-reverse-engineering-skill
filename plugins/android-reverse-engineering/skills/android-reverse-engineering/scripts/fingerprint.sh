#!/usr/bin/env bash
# fingerprint.sh — Triage an APK/XAPK before decompiling.
#
# Detects mobile framework (Flutter, React Native, Cordova/Capacitor,
# Xamarin, KMP/native), HTTP-stack hints, obfuscation level, native libs,
# and notable third-party SDKs.
#
# Decompiling Java is mostly useless for Flutter / RN / Xamarin / Cordova
# apps — different tools are needed. Run this BEFORE Phase 2 to choose
# the right path.

set -euo pipefail

usage() {
  cat <<EOF
Usage: fingerprint.sh <file.apk|file.xapk>

Prints a one-screen summary:
  * mobile framework (with rationale)
  * HTTP / DI / serialization stack hints
  * obfuscation indicator
  * native libraries (consolidated across split APKs)
  * notable third-party SDKs found in assets/
EOF
  exit 0
}

[[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]] && usage
INPUT="$1"
[[ ! -f "$INPUT" ]] && { echo "File not found: $INPUT" >&2; exit 1; }

TMP="$(mktemp -d -t apkfp.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Resolve to a list of APKs (handle XAPK = ZIP of APKs)
APKS=()
case "${INPUT,,}" in
  *.xapk|*.apks|*.apkm)
    unzip -q -o "$INPUT" -d "$TMP/xapk"
    while IFS= read -r p; do APKS+=("$p"); done < <(find "$TMP/xapk" -maxdepth 2 -type f -name '*.apk')
    ;;
  *.apk)
    APKS=("$INPUT")
    ;;
  *)
    echo "Unsupported input: $INPUT" >&2; exit 1 ;;
esac

# Aggregate ZIP listings from every APK in the bundle (split-aware view)
LISTING="$TMP/listing.txt"
: > "$LISTING"
for apk in "${APKS[@]}"; do
  unzip -l -- "$apk" 2>/dev/null | awk '{print $NF}' >> "$LISTING"
done

# Most class-level libs live inside classes*.dex, not as visible zip paths.
# Extract the type-name strings out of each dex with `strings` and append them
# to the listing so `has()` can match e.g. 'io/ktor/' or 'org/koin/'.
DEX_STRINGS="$TMP/dex_strings.txt"
: > "$DEX_STRINGS"
for apk in "${APKS[@]}"; do
  for dex in $(unzip -Z1 -- "$apk" 2>/dev/null | grep -E '^classes[0-9]*\.dex$' || true); do
    # DEX type descriptors look like "Lcom/foo/Bar;". Extract the inner
    # slash-separated FQN so callers can match e.g. 'io/ktor/' directly.
    unzip -p -- "$apk" "$dex" 2>/dev/null \
      | strings -n 8 \
      | grep -oE 'L[a-z][a-zA-Z0-9_]*(/[a-zA-Z0-9_$]+)+;' \
      | sed -E 's/^L//; s/;$//' \
      >> "$DEX_STRINGS" || true
  done
done
sort -u "$DEX_STRINGS" -o "$DEX_STRINGS"

has() { grep -qE "$1" "$LISTING" || grep -qE "$1" "$DEX_STRINGS"; }

# ----------------------------------------------------------------------
# Framework detection (priority order — first match wins)
# ----------------------------------------------------------------------
FRAMEWORK="unknown"
RATIONALE=""

if has '^lib/[^/]+/libflutter\.so$'; then
  FRAMEWORK="Flutter"
  RATIONALE="lib/<abi>/libflutter.so present"
  has '^lib/[^/]+/libapp\.so$' && RATIONALE+="; libapp.so contains AOT-compiled Dart"
elif has '^lib/[^/]+/libhermes\.so$' || has '^assets/index\.android\.bundle$' || has '^lib/[^/]+/libreactnativejni\.so$'; then
  FRAMEWORK="React Native"
  reasons=()
  has '^lib/[^/]+/libhermes\.so$'             && reasons+=("libhermes.so")
  has '^lib/[^/]+/libreactnativejni\.so$'     && reasons+=("libreactnativejni.so")
  has '^assets/index\.android\.bundle$'       && reasons+=("assets/index.android.bundle")
  RATIONALE="${reasons[*]}"
elif has '^assets/www/index\.html$' || has '^assets/www/cordova\.js$' || has '^assets/public/index\.html$'; then
  FRAMEWORK="Cordova / Capacitor (WebView hybrid)"
  RATIONALE="assets/www/ or assets/public/ shell present"
elif has '^lib/[^/]+/libmonodroid\.so$' || has '^assemblies/'; then
  FRAMEWORK="Xamarin / .NET MAUI"
  RATIONALE="libmonodroid.so or assemblies/ present — code is in .NET DLLs"
elif has '^lib/[^/]+/libmaui\.so$'; then
  FRAMEWORK=".NET MAUI"
  RATIONALE="libmaui.so present"
elif has '^assets/flutter_assets/' && ! has '^lib/[^/]+/libflutter\.so$'; then
  FRAMEWORK="Flutter (code-only split?)"
  RATIONALE="flutter_assets/ but no libflutter.so in this APK — check splits"
else
  # Native: distinguish Compose vs classic Android by androidx.compose presence
  if has 'androidx\.compose'; then
    FRAMEWORK="Native Android (Kotlin + Jetpack Compose)"
    RATIONALE="androidx.compose.* libraries detected"
  elif has '^META-INF/.*\.kotlin_module$'; then
    FRAMEWORK="Native Android (Kotlin)"
    RATIONALE="kotlin_module metadata present, no Compose markers"
  else
    FRAMEWORK="Native Android (Java/Kotlin)"
    RATIONALE="no cross-platform framework markers found"
  fi
fi

# ----------------------------------------------------------------------
# HTTP / DI / serialization stack hints
# ----------------------------------------------------------------------
http=()
has 'retrofit2'                && http+=("Retrofit")
has 'okhttp3'                  && http+=("OkHttp")
has 'io/ktor/'                 && http+=("Ktor")
has 'com/apollographql/'       && http+=("Apollo (GraphQL)")
has 'com/android/volley'       && http+=("Volley")

di=()
has 'dagger/hilt/'              && di+=("Hilt")
has '^META-INF/.*dagger.*'      && di+=("Dagger")
has 'org/koin/'                 && di+=("Koin")
has 'javax/inject/'             && [[ ${#di[@]} -eq 0 ]] && di+=("javax.inject")

ser=()
has 'kotlinx/serialization/'    && ser+=("kotlinx.serialization")
has 'com/google/gson/'          && ser+=("Gson")
has 'com/squareup/moshi/'       && ser+=("Moshi")
has 'com/fasterxml/jackson/'    && ser+=("Jackson")

# ----------------------------------------------------------------------
# Obfuscation indicator (R8/ProGuard) — count single-letter dex packages
# ----------------------------------------------------------------------
# Note: pipefail is on, so guard greps that may legitimately return 0 matches.
short_dirs=$( { grep -oE '^[a-z]{1,2}/' "$LISTING" || true; } | sort -u | wc -l | tr -d ' ')
if [[ "$short_dirs" -gt 30 ]]; then
  OBFUSCATION="HIGH ($short_dirs single/double-letter dirs at root)"
elif [[ "$short_dirs" -gt 10 ]]; then
  OBFUSCATION="MODERATE ($short_dirs short root dirs)"
else
  OBFUSCATION="LOW (no significant short-name namespace pollution)"
fi

# ----------------------------------------------------------------------
# Native libraries (consolidated)
# ----------------------------------------------------------------------
NATIVE=$(grep -E '^lib/[^/]+/[^/]+\.so$' "$LISTING" | sort -u || true)

# ----------------------------------------------------------------------
# Notable third-party SDKs (assets-based markers)
# ----------------------------------------------------------------------
sdks=()
has '^assets/com/appsflyer/'        && sdks+=("AppsFlyer")
has 'datadog\.buildId|com/datadog/' && sdks+=("Datadog")
has 'io/sentry/'                    && sdks+=("Sentry")
has 'com/google/firebase/'          && sdks+=("Firebase")
has 'com/google/android/gms/'       && sdks+=("Google Play Services")
has 'com/facebook/'                 && sdks+=("Facebook SDK")
has 'com/payu/'                     && sdks+=("PayU")
has 'com/stripe/'                   && sdks+=("Stripe")
has 'com/braintreepayments/'        && sdks+=("Braintree")
has 'com/storyteller/'              && sdks+=("Storyteller")
has 'zendesk/'                      && sdks+=("Zendesk")
has 'com/intercom/'                 && sdks+=("Intercom")
has 'com/segment/analytics'         && sdks+=("Segment")
has 'com/amplitude/'                && sdks+=("Amplitude")
has 'com/mixpanel/'                 && sdks+=("Mixpanel")
has 'com/onesignal/'                && sdks+=("OneSignal")
has 'com/microsoft/clarity'         && sdks+=("Microsoft Clarity")
has 'com/hotjar/'                   && sdks+=("Hotjar")
has 'com/instabug/'                 && sdks+=("Instabug")

# BuildConfig.java is almost never obfuscated and often holds base URLs / flavor.
if has 'BuildConfig\.class$'; then
  BUILDCONFIG="present (grep BuildConfig.java after decompile for base URLs / flavor)"
else
  BUILDCONFIG="not detected in zip listing (still worth grepping after decompile)"
fi

# ----------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------
echo "=== APK Fingerprint: $(basename "$INPUT") ==="
echo
echo "Framework:        $FRAMEWORK"
echo "  Rationale:      $RATIONALE"
echo "Obfuscation:      $OBFUSCATION"
echo
echo "HTTP stack:       ${http[*]:-none detected}"
echo "DI:               ${di[*]:-none detected}"
echo "Serialization:    ${ser[*]:-none detected}"
echo "BuildConfig:      $BUILDCONFIG"
echo
echo "Third-party SDKs: ${sdks[*]:-none detected}"
echo
echo "Native libraries (consolidated across splits):"
if [[ -n "$NATIVE" ]]; then
  echo "$NATIVE" | sed 's/^/  /'
else
  echo "  (none)"
fi
echo

# ----------------------------------------------------------------------
# Recommendation
# ----------------------------------------------------------------------
echo "Recommended next step:"
case "$FRAMEWORK" in
  Flutter*)
    echo "  Java decompilation will yield ~no app code. The Dart logic lives in"
    echo "  libapp.so (AOT). Use tools designed for Flutter:"
    echo "    - reFlutter / Doldrums / blutter (extract Dart class structure)"
    echo "    - strings/rabin2 on libapp.so for endpoints & string constants"
    ;;
  React*)
    echo "  Java code is just the RN host. Real app logic is in JS/Hermes:"
    echo "    - if Hermes: hbctool disasm assets/index.android.bundle"
    echo "    - if JSC:    js-beautify the bundle and grep for 'fetch('/'axios'"
    ;;
  Cordova*)
    echo "  All app code is in assets/www/ (or assets/public/). Just unzip and"
    echo "  inspect the HTML/JS — no Java decompile needed."
    ;;
  Xamarin*|.NET*)
    echo "  App logic is in .NET DLLs (assemblies/). Use ILSpy or dotPeek;"
    echo "  jadx will only show the Mono host."
    ;;
  *)
    echo "  Proceed with Phase 2: bash scripts/decompile.sh <file>"
    ;;
esac
