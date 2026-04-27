#!/usr/bin/env bash
# find-trackers.sh — Search decompiled source for tracker/analytics SDK usage
set -euo pipefail

usage() {
  cat <<EOF
Usage: find-trackers.sh <source-dir> [OPTIONS]

Search decompiled Java/Kotlin source for analytics and tracker SDK usage.

Arguments:
  <source-dir>    Path to the decompiled sources directory

Options:
  --firebase      Search only for Firebase Analytics
  --adjust        Search only for Adjust SDK
  --appsflyer     Search only for AppsFlyer SDK
  --mixpanel      Search only for Mixpanel SDK
  --amplitude     Search only for Amplitude SDK
  --segment       Search only for Segment SDK
  --braze         Search only for Braze/Appboy SDK
  --clevertap     Search only for CleverTap SDK
  --flurry        Search only for Flurry SDK
  --generic       Search only for generic cross-SDK patterns
  --endpoints     Search only for known tracker endpoints
  --manifest      Search only for AndroidManifest.xml markers
  --entrypoints   Search only for tracker SDK calls in app code (excludes library packages)
  --all           Search all patterns (default)
  --summary       Output a compact summary table with confidence scoring
  --json          Output results as machine-readable JSON
  -h, --help      Show this help message

Output:
  Default: Results are printed as file:line:match for easy navigation.
  --summary: Compact table with SDK | Sections | File Matches | Confidence | Status
  --json: JSON object with per-SDK detection results and confidence scores
EOF
  exit 0
}

SOURCE_DIR=""
SEARCH_FIREBASE=false
SEARCH_ADJUST=false
SEARCH_APPSFLYER=false
SEARCH_MIXPANEL=false
SEARCH_AMPLITUDE=false
SEARCH_SEGMENT=false
SEARCH_BRAZE=false
SEARCH_CLEVERTAP=false
SEARCH_FLURRY=false
SEARCH_GENERIC=false
SEARCH_ENDPOINTS=false
SEARCH_MANIFEST=false
SEARCH_ENTRYPOINTS=false
SEARCH_ALL=true
OUTPUT_SUMMARY=false
OUTPUT_JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --firebase)   SEARCH_FIREBASE=true;   SEARCH_ALL=false; shift ;;
    --adjust)     SEARCH_ADJUST=true;     SEARCH_ALL=false; shift ;;
    --appsflyer)  SEARCH_APPSFLYER=true;  SEARCH_ALL=false; shift ;;
    --mixpanel)   SEARCH_MIXPANEL=true;   SEARCH_ALL=false; shift ;;
    --amplitude)  SEARCH_AMPLITUDE=true;  SEARCH_ALL=false; shift ;;
    --segment)    SEARCH_SEGMENT=true;    SEARCH_ALL=false; shift ;;
    --braze)      SEARCH_BRAZE=true;      SEARCH_ALL=false; shift ;;
    --clevertap)  SEARCH_CLEVERTAP=true;  SEARCH_ALL=false; shift ;;
    --flurry)     SEARCH_FLURRY=true;     SEARCH_ALL=false; shift ;;
    --generic)    SEARCH_GENERIC=true;    SEARCH_ALL=false; shift ;;
    --endpoints)  SEARCH_ENDPOINTS=true;  SEARCH_ALL=false; shift ;;
    --manifest)     SEARCH_MANIFEST=true;     SEARCH_ALL=false; shift ;;
    --entrypoints)  SEARCH_ENTRYPOINTS=true;  SEARCH_ALL=false; shift ;;
    --all)          SEARCH_ALL=true; shift ;;
    --summary)      OUTPUT_SUMMARY=true; shift ;;
    --json)         OUTPUT_JSON=true; shift ;;
    -h|--help)    usage ;;
    -*)           echo "Error: Unknown option $1" >&2; usage ;;
    *)            SOURCE_DIR="$1"; shift ;;
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

# Summary/JSON mode: redirect output to temp file, count results per SDK
if [[ "$OUTPUT_SUMMARY" == true ]] || [[ "$OUTPUT_JSON" == true ]]; then
  SUMMARY_MODE=true
  # Force --all for summary mode to get complete picture
  SEARCH_ALL=true
else
  SUMMARY_MODE=false
fi

# Associative arrays for summary tracking (SDK -> match count, sections with hits)
declare -A SDK_CLASS_MATCHES   # SDK-specific class/import matches (HIGH confidence)
declare -A SDK_STRING_MATCHES  # SDK string/generic matches (MEDIUM confidence)
declare -A SDK_SECTIONS_HIT    # comma-separated list of sections with hits

section() {
  if [[ "$SUMMARY_MODE" == true ]]; then
    CURRENT_SECTION="$1"
  else
    echo
    echo "==== $1 ===="
    echo
  fi
}

run_grep() {
  local pattern="$1"
  # shellcheck disable=SC2086
  local result
  result=$(grep $GREP_OPTS -E "$pattern" "$SOURCE_DIR" 2>/dev/null || true)
  if [[ "$SUMMARY_MODE" == true ]]; then
    if [[ -n "$result" ]]; then
      local count
      count=$(echo "$result" | wc -l)
      # Determine which SDK this section belongs to and confidence level
      _tally_section_result "$count"
    fi
  else
    echo "$result"
  fi
}

run_grep_xml() {
  local pattern="$1"
  local result
  result=$(grep -rn --include="*.xml" -E "$pattern" "$SOURCE_DIR" 2>/dev/null || true)
  if [[ "$SUMMARY_MODE" == true ]]; then
    if [[ -n "$result" ]]; then
      local count
      count=$(echo "$result" | wc -l)
      _tally_section_result "$count"
    fi
  else
    echo "$result"
  fi
}

# Maps section name to SDK and tallies results
_tally_section_result() {
  local count="$1"
  local sdk=""
  local confidence="class"  # default to HIGH (class-level match)

  case "$CURRENT_SECTION" in
    "Firebase Analytics"*)          sdk="Firebase" ;;
    "Adjust"*)                      sdk="Adjust" ;;
    "AppsFlyer"*)                   sdk="AppsFlyer" ;;
    "Mixpanel"*)                    sdk="Mixpanel" ;;
    "Amplitude"*)                   sdk="Amplitude" ;;
    "Segment"*)                     sdk="Segment" ;;
    "Braze"*)                       sdk="Braze" ;;
    "CleverTap"*)                   sdk="CleverTap" ;;
    "Flurry"*)                      sdk="Flurry" ;;
    "Generic"*)                     sdk="Generic"; confidence="string" ;;
    "Known Tracker Endpoints"*)     sdk="Endpoints"; confidence="class" ;;
    "AndroidManifest"*)             sdk="Manifest"; confidence="class" ;;
    "Entry Points"*)                sdk="EntryPoints"; confidence="class" ;;
    *)                              sdk="Other"; confidence="string" ;;
  esac

  if [[ "$confidence" == "class" ]]; then
    SDK_CLASS_MATCHES["$sdk"]=$(( ${SDK_CLASS_MATCHES["$sdk"]:-0} + count ))
  else
    SDK_STRING_MATCHES["$sdk"]=$(( ${SDK_STRING_MATCHES["$sdk"]:-0} + count ))
  fi

  # Track which sections had hits
  local existing="${SDK_SECTIONS_HIT["$sdk"]:-}"
  if [[ -n "$existing" ]]; then
    SDK_SECTIONS_HIT["$sdk"]="${existing}, ${CURRENT_SECTION}"
  else
    SDK_SECTIONS_HIT["$sdk"]="${CURRENT_SECTION}"
  fi
}

CURRENT_SECTION=""

# --- Firebase Analytics ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_FIREBASE" == true ]]; then
  section "Firebase Analytics — Initialization"
  run_grep '(FirebaseAnalytics\.getInstance|FirebaseAnalytics\.newInstance|FirebaseApp\.initializeApp)'
  section "Firebase Analytics — Event Logging"
  run_grep '(\.logEvent\s*\(|\.setDefaultEventParameters|FirebaseAnalytics\.Event\.|FirebaseAnalytics\.Param\.)'
  section "Firebase Analytics — User Identity"
  run_grep '(\.setUserId\s*\(|\.setUserProperty\s*\(|\.setAnalyticsCollectionEnabled)'
  section "Firebase Analytics — Consent"
  run_grep '(\.setConsent\s*\(|ConsentType\.|ConsentStatus\.|setAnalyticsCollectionEnabled\s*\(\s*false)'
fi

# --- Adjust ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_ADJUST" == true ]]; then
  section "Adjust — Initialization"
  run_grep '(AdjustConfig\s*\(|Adjust\.onCreate\s*\(|Adjust\.create\s*\(|AdjustConfig\.ENVIRONMENT_)'
  section "Adjust — Event Tracking"
  run_grep '(AdjustEvent\s*\(|Adjust\.trackEvent\s*\(|\.setRevenue\s*\(|\.setCallbackId\s*\()'
  section "Adjust — Attribution & User"
  run_grep '(\.setOnAttributionChangedListener|AdjustAttribution|Adjust\.addSessionCallbackParameter|Adjust\.getAdid\s*\()'
fi

# --- AppsFlyer ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_APPSFLYER" == true ]]; then
  section "AppsFlyer — Initialization"
  run_grep '(AppsFlyerLib\.getInstance|AppsFlyerConversionListener|\.init\s*\(.*AF_DEV_KEY|\.start\s*\()'
  section "AppsFlyer — Event Tracking"
  run_grep '(\.logEvent\s*\(.*AppsFlyerLib|AFInAppEventType\.|AFInAppEventParameterName\.|\.trackEvent\s*\()'
  section "AppsFlyer — User Identity"
  run_grep '(\.setCustomerUserId\s*\(|\.setCustomerIdAndLogSession|\.getAppsFlyerUID\s*\(|\.setAdditionalData\s*\()'
fi

# --- Mixpanel ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_MIXPANEL" == true ]]; then
  section "Mixpanel — Initialization"
  run_grep '(MixpanelAPI\.getInstance\s*\(|MixpanelAPI\.init\s*\()'
  section "Mixpanel — Event Tracking"
  run_grep '(\.track\s*\(|\.trackMap\s*\(|\.timeEvent\s*\(|\.registerSuperProperties\s*\()'
  section "Mixpanel — User Identity & Profile"
  run_grep '(\.identify\s*\(|\.alias\s*\(|\.getPeople\s*\(|\.getDistinctId\s*\(|\.set\s*\(|\.increment\s*\()'
fi

# --- Amplitude ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_AMPLITUDE" == true ]]; then
  section "Amplitude — Initialization"
  run_grep '(Amplitude\.getInstance\s*\(|AmplitudeClient|\.initialize\s*\(.*amplitude|amplitude\.init\s*\()'
  section "Amplitude — Event Tracking"
  run_grep '(\.logEvent\s*\(|\.logRevenue\s*\(|\.setEventProperties|EventOptions\s*\()'
  section "Amplitude — User Identity"
  run_grep '(\.setUserId\s*\(|\.setUserProperties\s*\(|\.setDeviceId\s*\(|\.setGroup\s*\(|Identify\s*\(\))'
fi

# --- Segment ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_SEGMENT" == true ]]; then
  section "Segment — Initialization"
  run_grep '(Analytics\.with\s*\(|Analytics\.Builder|Analytics\.setSingletonInstance|com\.segment\.analytics)'
  section "Segment — Event Tracking"
  run_grep '(\.track\s*\(|\.screen\s*\(|\.group\s*\(|TrackPayload|ScreenPayload)'
  section "Segment — User Identity"
  run_grep '(\.identify\s*\(|\.alias\s*\(|Traits\s*\(\)|IdentifyPayload)'
fi

# --- Braze (formerly Appboy) ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_BRAZE" == true ]]; then
  section "Braze — Initialization"
  run_grep '(Braze\.configure\s*\(|BrazeConfig\.Builder|Appboy\.configure\s*\(|AppboyConfig\.Builder)'
  section "Braze — Event & Purchase Logging"
  run_grep '(\.logCustomEvent\s*\(|\.logPurchase\s*\(|BrazeProperties\s*\(|\.logClick\s*\()'
  section "Braze — User Identity"
  run_grep '(\.getCurrentUser\s*\(|\.changeUser\s*\(|BrazeUser|\.setEmail\s*\(|\.setCustomUserAttribute\s*\()'
fi

# --- CleverTap ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_CLEVERTAP" == true ]]; then
  section "CleverTap — Initialization"
  run_grep '(CleverTapAPI\.getDefaultInstance|CleverTapAPI\.changeCredentials|ActivityLifecycleCallback\.register)'
  section "CleverTap — Event Tracking"
  run_grep '(\.pushEvent\s*\(|\.recordEvent\s*\(|\.pushChargedEvent\s*\()'
  section "CleverTap — User Identity & Profile"
  run_grep '(\.pushProfile\s*\(|\.onUserLogin\s*\(|\.profilePush\s*\(|\.getCleverTapID\s*\()'
fi

# --- Flurry ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_FLURRY" == true ]]; then
  section "Flurry — Initialization"
  run_grep '(FlurryAgent\.Builder|FlurryAgent\.init\s*\(|FlurryAgent\.onStartSession\s*\(|\.withLogEnabled\s*\()'
  section "Flurry — Event Tracking"
  run_grep '(FlurryAgent\.logEvent\s*\(|FlurryAgent\.endTimedEvent|FlurryAgent\.logPayment\s*\()'
  section "Flurry — User Identity"
  run_grep '(FlurryAgent\.setUserId\s*\(|FlurryAgent\.setAge\s*\(|FlurryAgent\.setGender\s*\()'
fi

# --- Generic Cross-SDK Patterns ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_GENERIC" == true ]]; then
  section "Generic — Event Tracking Methods"
  run_grep '\.(trackEvent|logEvent|recordEvent|pushEvent|logCustomEvent)\s*\('
  section "Generic — User Identification"
  run_grep '\.(setUserId|setCustomerUserId|identify|setDistinctId|onUserLogin|changeUser)\s*\('
  section "Generic — Analytics Collection Toggle"
  run_grep '(setAnalyticsCollectionEnabled|setOptOut|setDataCollectionEnabled|setSendingEnabled|optOut|gdprForgetMe)\s*\('
fi

# --- Known Tracker Endpoints ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_ENDPOINTS" == true ]]; then
  section "Known Tracker Endpoints"
  run_grep '"https?://[^"]*(app-measurement\.com|firebase-settings\.crashlytics\.com|firebaselogging|google-analytics\.com/collect)'
  run_grep '"https?://[^"]*(app\.adjust\.(com|io|world)|cdn\.adjust\.com)'
  run_grep '"https?://[^"]*(appsflyer\.com|appsflyersdk\.com|onelink\.me)'
  run_grep '"https?://[^"]*(api\.mixpanel\.com|decide\.mixpanel\.com|api-js\.mixpanel\.com)'
  run_grep '"https?://[^"]*(api\.amplitude\.com|api2\.amplitude\.com|cdn\.amplitude\.com)'
  run_grep '"https?://[^"]*(api\.segment\.(io|com)|cdn-settings\.segment\.com)'
  run_grep '"https?://[^"]*(sdk\.iad-[0-9]+\.braze\.com|rest\.iad-[0-9]+\.braze\.com|appboy\.com)'
  run_grep '"https?://[^"]*(wzrkt\.com|clevertap-prod\.com|in\.clevertap\.com)'
  run_grep '"https?://[^"]*(data\.flurry\.com|flurry\.com/sdk)'
fi

# --- AndroidManifest.xml Markers ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_MANIFEST" == true ]]; then
  section "AndroidManifest — Tracker Services & Receivers"
  run_grep_xml '(com\.google\.firebase\.analytics|com\.google\.android\.gms\.measurement|com\.google\.firebase\.iid)'
  run_grep_xml '(com\.adjust\.|com\.appsflyer\.|com\.mixpanel\.|com\.amplitude\.|com\.segment\.)'
  run_grep_xml '(com\.braze\.|com\.appboy\.|com\.clevertap\.|com\.flurry\.)'
  section "AndroidManifest — Tracker Permissions"
  run_grep_xml '(AD_ID|com\.google\.android\.gms\.permission\.AD_ID|ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION|GET_ACCOUNTS)'
  section "AndroidManifest — Tracker Meta-data"
  run_grep_xml '(com\.google\.firebase\.analytics|firebase_analytics_collection_enabled|google_analytics_adid_collection_enabled)'
  run_grep_xml '(ADJUST_|APPSFLYER_|MIXPANEL_|AMPLITUDE_|SEGMENT_|BRAZE_|CLEVERTAP_|FLURRY_)'
fi

# --- Entry Points: Tracker SDK calls from app code only ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_ENTRYPOINTS" == true ]]; then
  section "Entry Points — Tracker SDK calls from app code (library packages excluded)"

  # Build --exclude-dir arguments for known tracker/analytics library packages
  EXCLUDE_DIRS=(
    --exclude-dir="com/google"
    --exclude-dir="com/adjust"
    --exclude-dir="com/appsflyer"
    --exclude-dir="com/mixpanel"
    --exclude-dir="com/amplitude"
    --exclude-dir="com/segment"
    --exclude-dir="com/braze"
    --exclude-dir="com/appboy"
    --exclude-dir="com/clevertap"
    --exclude-dir="com/flurry"
    --exclude-dir="com/facebook"
    --exclude-dir="com/newrelic"
    --exclude-dir="com/crashlytics"
    --exclude-dir="io/sentry"
    --exclude-dir="com/bugsnag"
    --exclude-dir="com/datadog"
  )

  ENTRYPOINT_PATTERN='(FirebaseAnalytics\.getInstance|FirebaseAnalytics\.newInstance|FirebaseApp\.initializeApp|\.logEvent\s*\(|\.setUserId\s*\(|\.setUserProperty\s*\(|\.setAnalyticsCollectionEnabled|Adjust\.onCreate|Adjust\.trackEvent|AdjustConfig\s*\(|AppsFlyerLib\.getInstance|\.init\s*\(.*AF_DEV_KEY|\.start\s*\(.*AppsFlyerLib|MixpanelAPI\.getInstance|\.track\s*\(.*MixpanelAPI|\.identify\s*\(.*Mixpanel|Amplitude\.getInstance|\.logEvent\s*\(.*Amplitude|Analytics\.with\s*\(|\.track\s*\(.*Segment|\.identify\s*\(.*Segment|Braze\.configure|\.logCustomEvent\s*\(|\.changeUser\s*\(.*Braze|CleverTapAPI\.getDefaultInstance|\.pushEvent\s*\(|\.onUserLogin\s*\(|FlurryAgent\.logEvent|FlurryAgent\.setUserId|FlurryAgent\.Builder)'

  # shellcheck disable=SC2086
  local ep_result
  ep_result=$(grep -rn --include="*.java" --include="*.kt" "${EXCLUDE_DIRS[@]}" -E "$ENTRYPOINT_PATTERN" "$SOURCE_DIR" 2>/dev/null || true)
  if [[ "$SUMMARY_MODE" == true ]]; then
    if [[ -n "$ep_result" ]]; then
      local count
      count=$(echo "$ep_result" | wc -l)
      _tally_section_result "$count"
    fi
  else
    echo "$ep_result"
    echo
    echo "NOTE: Only calls from app code are shown above. Library-internal calls are excluded."
    echo "If no results appear, tracker SDKs may only be initialized internally (e.g., via ContentProvider)."
  fi
fi

# =====================================================================
# Summary / JSON output
# =====================================================================

if [[ "$SUMMARY_MODE" == true ]]; then
  # Known tracker SDKs to report on (exclude meta categories)
  TRACKER_SDKS=("Firebase" "Adjust" "AppsFlyer" "Mixpanel" "Amplitude" "Segment" "Braze" "CleverTap" "Flurry")

  if [[ "$OUTPUT_JSON" == true ]]; then
    # JSON output
    printf '{\n  "trackers": [\n'
    first=true
    for sdk in "${TRACKER_SDKS[@]}"; do
      class_count=${SDK_CLASS_MATCHES["$sdk"]:-0}
      string_count=${SDK_STRING_MATCHES["$sdk"]:-0}
      total=$((class_count + string_count))

      # Determine confidence
      if [[ $class_count -gt 0 ]]; then
        confidence="HIGH"
      elif [[ $string_count -gt 0 ]]; then
        confidence="MEDIUM"
      else
        confidence="NONE"
      fi

      [[ "$confidence" == "NONE" ]] && continue

      if [[ "$first" == true ]]; then
        first=false
      else
        printf ',\n'
      fi

      sections="${SDK_SECTIONS_HIT["$sdk"]:-}"
      printf '    {"sdk": "%s", "class_matches": %d, "string_matches": %d, "total_matches": %d, "confidence": "%s", "sections": "%s"}' \
        "$sdk" "$class_count" "$string_count" "$total" "$confidence" "$sections"
    done
    printf '\n  ]\n}\n'
  else
    # Summary table output
    echo
    echo "=== Tracker Detection Summary ==="
    echo
    printf "%-15s | %6s | %7s | %5s | %-10s | %s\n" "SDK" "Class" "String" "Total" "Confidence" "Status"
    printf "%-15s-|-%6s-|-%7s-|-%5s-|-%-10s-|-%s\n" "---------------" "------" "-------" "-----" "----------" "--------"

    for sdk in "${TRACKER_SDKS[@]}"; do
      class_count=${SDK_CLASS_MATCHES["$sdk"]:-0}
      string_count=${SDK_STRING_MATCHES["$sdk"]:-0}
      total=$((class_count + string_count))

      if [[ $class_count -gt 0 ]]; then
        confidence="HIGH"
        status="DETECTED"
      elif [[ $string_count -gt 0 ]]; then
        confidence="MEDIUM"
        status="LIKELY"
      else
        confidence="NONE"
        status="NOT FOUND"
      fi

      printf "%-15s | %6d | %7d | %5d | %-10s | %s\n" \
        "$sdk" "$class_count" "$string_count" "$total" "$confidence" "$status"
    done

    # Additional info
    ep_count=${SDK_CLASS_MATCHES["EntryPoints"]:-0}
    if [[ $ep_count -gt 0 ]]; then
      echo
      echo "Entry points in app code: $ep_count match(es)"
    fi
    manifest_count=${SDK_CLASS_MATCHES["Manifest"]:-0}
    if [[ $manifest_count -gt 0 ]]; then
      echo "Manifest markers: $manifest_count match(es)"
    fi
    echo
    echo "Confidence: HIGH = SDK-specific classes found, MEDIUM = only generic/string matches, NONE = not detected"
  fi
else
  echo
  echo "=== Search complete ==="
fi
