#!/usr/bin/env bash
# neutralize.sh — Neutralize tracker/ad SDK entry points in decoded APK smali
#
# Replaces SDK method bodies with stubs (return-void, return 0, return-object null)
# and optionally disables manifest components.
#
# Exit codes:
#   0 — success (methods patched)
#   1 — error (invalid input, missing files)
#   2 — no targets found
set -euo pipefail

usage() {
  cat <<EOF
Usage: neutralize.sh <decoded-dir> [OPTIONS]

Neutralize tracker and ad SDK entry points in a decoded APK directory.

The decoded directory must be the output of 'apktool d' and contain
a smali/ directory and AndroidManifest.xml.

Arguments:
  <decoded-dir>   Path to the apktool-decoded APK directory

Options:
  --ads           Neutralize only ad SDK entry points
  --trackers      Neutralize only tracker/analytics SDK entry points
  --all           Neutralize both ads and trackers (default)
  --dry-run       Show what would be patched without modifying files
  --backup        Create .smali.bak backups before patching
  --no-backup     Do not create backup files (default)
  --cleanup-backups  Remove all .smali.bak files from the decoded directory
  --manifest      Patch AndroidManifest.xml to disable SDK components (default)
  --no-manifest   Skip manifest patching
  --targets-file <file>  Load additional targets from a file (one per line).
                         Format: <class-path>:<method-name>
                           com/example/MyClass:methodName   (searches all smali dirs)
                           com/example/pkg/**:*             (wildcard — all methods in package)
                           com/example/Class:*              (all methods in class)
                         L prefix and ; suffix are auto-stripped:
                           Lcom/example/MyClass;:init       (also valid)
                         Lines starting with # are ignored.
  --manifest-components-file <file>
                         Load additional manifest components from a file.
                         Format: one per line, class_substring|sdk_name
                         Components are appended to the builtin lists.
  --no-builtin-targets   Skip hardcoded patch_ad_targets() and patch_tracker_targets().
                         Use when relying entirely on --targets-file (e.g., from
                         registry-scan.py). Builtin manifest components are also
                         skipped; use --manifest-components-file for registry-driven
                         manifest patching.
  --package <path>       Neutralize ALL methods in a smali package recursively.
                         Stubs every non-abstract, non-native, non-constructor
                         method. Can be specified multiple times.
                         Example: --package guru/ads --package com/appsflyer
  --replay        Replay patches from a previous neutralize-manifest.json
  --save-manifest Save neutralize-manifest.json after patching (default)
  --no-save-manifest  Do not save neutralize-manifest.json
  -h, --help      Show this help message

Output:
  Machine-readable lines:
    PATCHED:<sdk>:<class>:<method>:<stub_type>:<file>
    MANIFEST_DISABLED:<type>:<name>:<sdk>
    DRY_RUN:WOULD_PATCH:<sdk>:<class>:<method>:<stub_type>:<file>
    DRY_RUN:WOULD_DISABLE:<type>:<name>:<sdk>
EOF
  exit 0
}

# =====================================================================
# Argument parsing
# =====================================================================

DECODED_DIR=""
NEUTRALIZE_ADS=false
NEUTRALIZE_TRACKERS=false
NEUTRALIZE_ALL=true
DRY_RUN=false
DO_BACKUP=false
DO_CLEANUP_BACKUPS=false
DO_MANIFEST=true
TARGETS_FILE=""
MANIFEST_COMPONENTS_FILE=""
NO_BUILTIN_TARGETS=false
PACKAGE_PATHS=()
DO_REPLAY=false
DO_SAVE_MANIFEST=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ads)          NEUTRALIZE_ADS=true;      NEUTRALIZE_ALL=false; shift ;;
    --trackers)     NEUTRALIZE_TRACKERS=true;  NEUTRALIZE_ALL=false; shift ;;
    --all)          NEUTRALIZE_ALL=true; shift ;;
    --dry-run)      DRY_RUN=true; shift ;;
    --backup)       DO_BACKUP=true; shift ;;
    --no-backup)    DO_BACKUP=false; shift ;;
    --cleanup-backups) DO_CLEANUP_BACKUPS=true; shift ;;
    --manifest)     DO_MANIFEST=true; shift ;;
    --no-manifest)  DO_MANIFEST=false; shift ;;
    --targets-file)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Error: --targets-file requires a file argument" >&2
        exit 1
      fi
      TARGETS_FILE="$1"; shift ;;
    --manifest-components-file)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Error: --manifest-components-file requires a file argument" >&2
        exit 1
      fi
      MANIFEST_COMPONENTS_FILE="$1"; shift ;;
    --no-builtin-targets) NO_BUILTIN_TARGETS=true; shift ;;
    --package)
      shift
      if [[ $# -eq 0 ]]; then
        echo "Error: --package requires a package path argument" >&2
        exit 1
      fi
      PACKAGE_PATHS+=("$1"); shift ;;
    --replay)       DO_REPLAY=true; shift ;;
    --save-manifest)    DO_SAVE_MANIFEST=true; shift ;;
    --no-save-manifest) DO_SAVE_MANIFEST=false; shift ;;
    -h|--help)      usage ;;
    -*)             echo "Error: Unknown option $1" >&2; usage ;;
    *)              DECODED_DIR="$1"; shift ;;
  esac
done

if [[ -z "$DECODED_DIR" ]]; then
  echo "Error: No decoded directory specified." >&2
  usage
fi

if [[ ! -d "$DECODED_DIR" ]]; then
  echo "Error: Directory not found: $DECODED_DIR" >&2
  exit 1
fi

# Find smali directories (multidex support: smali/, smali_classes2/, etc.)
SMALI_DIRS=()
for d in "$DECODED_DIR"/smali*; do
  if [[ -d "$d" ]]; then
    SMALI_DIRS+=("$d")
  fi
done

if [[ ${#SMALI_DIRS[@]} -eq 0 ]]; then
  echo "Error: No smali/ directory found in $DECODED_DIR" >&2
  echo "Make sure this is an apktool-decoded APK directory." >&2
  exit 1
fi

MANIFEST="$DECODED_DIR/AndroidManifest.xml"
if [[ ! -f "$MANIFEST" ]]; then
  echo "Warning: AndroidManifest.xml not found in $DECODED_DIR" >&2
  DO_MANIFEST=false
fi

# =====================================================================
# Counters & patch log
# =====================================================================

METHODS_PATCHED=0
METHODS_SKIPPED=0
COMPONENTS_DISABLED=0

# Patch log file — captures all PATCHED: and MANIFEST_DISABLED: lines
PATCH_LOG_FILE=$(mktemp "${TMPDIR:-/tmp}/neutralize-log-XXXXXX")
cleanup_patch_log() {
  rm -f "$PATCH_LOG_FILE"
}
trap cleanup_patch_log EXIT

# =====================================================================
# patch_method() — Replace a smali method body with a stub
#
# Arguments:
#   $1 — smali file path
#   $2 — method name (e.g., "initialize", "logEvent")
#   $3 — SDK name (for reporting, e.g., "AdMob", "Firebase")
#   $4 — smali class descriptor (e.g., "Lcom/google/android/gms/ads/MobileAds;")
#
# The function finds .method declarations matching the method name,
# determines the return type, and replaces the body with appropriate stubs.
# =====================================================================

patch_method() {
  local file="$1"
  local method_name="$2"
  local sdk_name="$3"
  local class_desc="$4"

  if [[ ! -f "$file" ]]; then
    return
  fi

  # Use awk to find and patch method bodies
  local tmp_file
  tmp_file=$(mktemp)
  local patched=false

  awk -v method="$method_name" -v sdk="$sdk_name" -v cls="$class_desc" \
      -v dry_run="$DRY_RUN" -v src_file="$file" '
  BEGIN {
    in_target = 0
    found = 0
  }

  # count_param_registers(descriptor_params, is_static)
  # Counts the number of registers required for method parameters.
  # Instance methods have an implicit "this" (p0) taking 1 register.
  # J (long) and D (double) each take 2 registers; all others take 1.
  function count_param_registers(params, is_static,    i, c, count) {
    count = 0
    if (!is_static) count = 1  # p0 = this
    i = 1
    while (i <= length(params)) {
      c = substr(params, i, 1)
      if (c == "J" || c == "D") {
        count += 2; i++
      } else if (c == "L") {
        count += 1
        # Skip to ";"
        while (i <= length(params) && substr(params, i, 1) != ";") i++
        i++  # skip the ";"
      } else if (c == "[") {
        # Array: skip all leading "[", then the base type
        while (i <= length(params) && substr(params, i, 1) == "[") i++
        c = substr(params, i, 1)
        if (c == "L") {
          count += 1
          while (i <= length(params) && substr(params, i, 1) != ";") i++
          i++
        } else {
          # Primitive array
          count += 1; i++
        }
      } else {
        # Primitive: Z, B, C, S, I, F
        count += 1; i++
      }
    }
    return count
  }

  # Match .method line containing our target method name (skip abstract/native)
  /^\.method / && !/ abstract / && !/ native / && $0 ~ "[ ;]" method "\\(" {
    in_target = 1
    found = 1

    # Determine if static
    is_static = ($0 ~ / static /) ? 1 : 0

    # Extract descriptor: everything between "(" and ")" is params,
    # everything after ")" is return type
    line = $0
    open_idx = index(line, "(")
    close_idx = index(line, ")")
    if (open_idx > 0 && close_idx > open_idx) {
      params = substr(line, open_idx + 1, close_idx - open_idx - 1)
      ret_type = substr(line, close_idx + 1)
      gsub(/[[:space:]]+$/, "", ret_type)
    } else {
      params = ""
      ret_type = "V"
    }

    # Count registers needed for parameters (including "this" for instance methods)
    param_regs = count_param_registers(params, is_static)

    # Determine stub type and registers needed for the stub itself
    if (ret_type == "V") {
      stub_type = "return-void"
      stub_regs = 0  # return-void needs no registers beyond params
    } else if (ret_type == "Z" || ret_type == "I" || ret_type == "S" || \
               ret_type == "B" || ret_type == "C" || ret_type == "F") {
      stub_type = "const/4+return"
      stub_regs = 1  # needs v0
    } else if (ret_type == "J" || ret_type == "D") {
      stub_type = "const-wide+return-wide"
      stub_regs = 2  # needs v0, v1
    } else {
      # Object or array return type (L...; or [...)
      stub_type = "const/4+return-object"
      stub_regs = 1  # needs v0
    }

    # Total registers = max(param_regs, stub_regs + param_regs)
    # In Dalvik, .registers = local_vars + param_registers
    # We need stub_regs local vars + param_regs for parameters
    total_regs = stub_regs + param_regs
    if (total_regs < 1) total_regs = 1  # minimum 1 register

    # Build stub body
    if (ret_type == "V") {
      stub_body = "    .registers " total_regs "\n\n    return-void"
    } else if (ret_type == "J" || ret_type == "D") {
      stub_body = "    .registers " total_regs "\n\n    const-wide/16 v0, 0x0\n\n    return-wide v0"
    } else if (ret_type == "Z" || ret_type == "I" || ret_type == "S" || \
               ret_type == "B" || ret_type == "C" || ret_type == "F") {
      stub_body = "    .registers " total_regs "\n\n    const/4 v0, 0x0\n\n    return v0"
    } else {
      stub_body = "    .registers " total_regs "\n\n    const/4 v0, 0x0\n\n    return-object v0"
    }

    if (dry_run == "true") {
      printf "DRY_RUN:WOULD_PATCH:%s:%s:%s:%s:%s\n", sdk, cls, method, stub_type, src_file > "/dev/stderr"
    } else {
      printf "PATCHED:%s:%s:%s:%s:%s\n", sdk, cls, method, stub_type, src_file > "/dev/stderr"
    }

    # Print the .method line unchanged
    print $0
    next
  }

  # Inside a target method — skip original body until .end method
  in_target && /^\.end method/ {
    # Print the stub body, then .end method
    printf "%s\n", stub_body
    print ""
    print $0
    in_target = 0
    next
  }

  # Inside target method — skip all lines (original body)
  in_target {
    next
  }

  # Outside target method — print line unchanged
  { print }
  ' "$file" > "$tmp_file" 2>"${tmp_file}.stderr"

  # Process stderr in the parent shell (not a subshell) so variables propagate
  if grep -q '^PATCHED:\|^DRY_RUN:WOULD_PATCH:' "${tmp_file}.stderr" 2>/dev/null; then
    patched=true
    local patch_count
    patch_count=$(grep -c '^PATCHED:\|^DRY_RUN:WOULD_PATCH:' "${tmp_file}.stderr")
    METHODS_PATCHED=$((METHODS_PATCHED + patch_count))
    # Append PATCHED lines to the patch log (not DRY_RUN lines)
    grep '^PATCHED:' "${tmp_file}.stderr" >> "$PATCH_LOG_FILE" 2>/dev/null || true
  fi
  # Emit stderr lines to stderr for user visibility
  cat "${tmp_file}.stderr" >&2
  rm -f "${tmp_file}.stderr"

  if [[ "$DRY_RUN" == false ]] && [[ "$patched" == true ]]; then
    if [[ "$DO_BACKUP" == true ]]; then
      [[ -f "${file}.bak" ]] || cp "$file" "${file}.bak"
    fi
    mv "$tmp_file" "$file"
  else
    rm -f "$tmp_file"
  fi
}

# =====================================================================
# find_and_patch() — Find smali files for a class and patch methods
#
# Arguments:
#   $1 — smali class path (e.g., "com/google/android/gms/ads/MobileAds")
#   $2 — comma-separated method names
#   $3 — SDK name
#   $4 — smali class descriptor
# =====================================================================

find_and_patch() {
  local class_path="$1"
  local methods_csv="$2"
  local sdk_name="$3"
  local class_desc="$4"

  IFS=',' read -ra methods <<< "$methods_csv"

  for smali_dir in "${SMALI_DIRS[@]}"; do
    local smali_file="$smali_dir/$class_path.smali"
    if [[ -f "$smali_file" ]]; then
      for method in "${methods[@]}"; do
        patch_method "$smali_file" "$method" "$sdk_name" "$class_desc"
      done
    fi
  done
}

# =====================================================================
# patch_all_methods() — Stub ALL non-abstract, non-native, non-constructor
#                        methods in a smali file
#
# Arguments:
#   $1 — smali file path
#   $2 — SDK name (for reporting)
# =====================================================================

patch_all_methods() {
  local file="$1"
  local sdk_name="$2"

  if [[ ! -f "$file" ]]; then
    return
  fi

  # Extract class descriptor from the .class line
  local class_desc
  class_desc=$(grep -m1 '^\.class ' "$file" | grep -oP 'L[^ ;]+;' | head -1)
  if [[ -z "$class_desc" ]]; then
    return
  fi

  # Extract all method names that are patchable:
  # - Not abstract, not native
  # - Not <init> or <clinit> (constructors)
  local methods
  methods=$(awk '
    /^\.method / {
      # Skip abstract and native methods
      if ($0 ~ / abstract / || $0 ~ / native /) next
      # Extract method name from descriptor
      # Format: .method [access] methodName(params)RetType
      match($0, /[ ]([^ (]+)\(/, arr)
      if (arr[1] != "" && arr[1] != "<init>" && arr[1] != "<clinit>") {
        print arr[1]
      }
    }
  ' "$file" | sort -u)

  if [[ -z "$methods" ]]; then
    return
  fi

  while IFS= read -r method_name; do
    [[ -z "$method_name" ]] && continue
    patch_method "$file" "$method_name" "$sdk_name" "$class_desc"
  done <<< "$methods"
}

# =====================================================================
# patch_packages() — Neutralize all methods in specified packages
# =====================================================================

patch_packages() {
  if [[ ${#PACKAGE_PATHS[@]} -eq 0 ]]; then
    return
  fi

  for pkg_path in "${PACKAGE_PATHS[@]}"; do
    # Normalize: remove trailing slashes
    pkg_path="${pkg_path%/}"
    local sdk_label="Package:${pkg_path}"

    echo "--- Neutralizing package: $pkg_path ---"
    local pkg_file_count=0

    for smali_dir in "${SMALI_DIRS[@]}"; do
      local pkg_dir="$smali_dir/$pkg_path"
      if [[ ! -d "$pkg_dir" ]]; then
        continue
      fi

      # Find all .smali files recursively
      while IFS= read -r -d '' smali_file; do
        patch_all_methods "$smali_file" "$sdk_label"
        pkg_file_count=$((pkg_file_count + 1))
      done < <(find "$pkg_dir" -name "*.smali" -print0 2>/dev/null)
    done

    echo "  Processed $pkg_file_count smali file(s) in $pkg_path"
  done
  echo
}

# =====================================================================
# SDK Target Lists
# =====================================================================

patch_ad_targets() {
  # AdMob / Google Mobile Ads
  find_and_patch "com/google/android/gms/ads/MobileAds" \
    "initialize,setRequestConfiguration" \
    "AdMob" "Lcom/google/android/gms/ads/MobileAds;"
  find_and_patch "com/google/android/gms/ads/interstitial/InterstitialAd" \
    "load" \
    "AdMob" "Lcom/google/android/gms/ads/interstitial/InterstitialAd;"
  find_and_patch "com/google/android/gms/ads/rewarded/RewardedAd" \
    "load" \
    "AdMob" "Lcom/google/android/gms/ads/rewarded/RewardedAd;"
  find_and_patch "com/google/android/gms/ads/rewarded/RewardedInterstitialAd" \
    "load" \
    "AdMob" "Lcom/google/android/gms/ads/rewarded/RewardedInterstitialAd;"
  find_and_patch "com/google/android/gms/ads/appopen/AppOpenAd" \
    "load" \
    "AdMob" "Lcom/google/android/gms/ads/appopen/AppOpenAd;"
  find_and_patch "com/google/android/gms/ads/AdView" \
    "loadAd" \
    "AdMob" "Lcom/google/android/gms/ads/AdView;"
  find_and_patch "com/google/android/gms/ads/AdLoader" \
    "loadAd,loadAds" \
    "AdMob" "Lcom/google/android/gms/ads/AdLoader;"

  # Unity Ads
  find_and_patch "com/unity3d/ads/UnityAds" \
    "initialize,load,show" \
    "UnityAds" "Lcom/unity3d/ads/UnityAds;"

  # IronSource / LevelPlay
  find_and_patch "com/ironsource/mediationsdk/IronSource" \
    "init,loadInterstitial,showInterstitial,showRewardedVideo,loadRewardedVideo,loadBanner,showISDemandOnlyInterstitial,showISDemandOnlyRewardedVideo" \
    "IronSource" "Lcom/ironsource/mediationsdk/IronSource;"

  # AppLovin / MAX
  find_and_patch "com/applovin/sdk/AppLovinSdk" \
    "getInstance,initialize,initializeSdk" \
    "AppLovin" "Lcom/applovin/sdk/AppLovinSdk;"

  # Meta Audience Network
  find_and_patch "com/facebook/ads/AudienceNetworkAds" \
    "initialize,buildInitSettings" \
    "MetaAN" "Lcom/facebook/ads/AudienceNetworkAds;"

  # Vungle / Liftoff
  find_and_patch "com/vungle/warren/Vungle" \
    "init,loadAd,playAd" \
    "Vungle" "Lcom/vungle/warren/Vungle;"
  find_and_patch "com/vungle/ads/VungleAds" \
    "init" \
    "Vungle" "Lcom/vungle/ads/VungleAds;"
  find_and_patch "com/vungle/ads/VungleInterstitial" \
    "load,show" \
    "Vungle" "Lcom/vungle/ads/VungleInterstitial;"
  find_and_patch "com/vungle/ads/VungleRewarded" \
    "load,show" \
    "Vungle" "Lcom/vungle/ads/VungleRewarded;"
  find_and_patch "com/vungle/ads/VungleBanner" \
    "load" \
    "Vungle" "Lcom/vungle/ads/VungleBanner;"

  # InMobi
  find_and_patch "com/inmobi/sdk/InMobiSdk" \
    "init" \
    "InMobi" "Lcom/inmobi/sdk/InMobiSdk;"
  find_and_patch "com/inmobi/ads/InMobiInterstitial" \
    "load,show" \
    "InMobi" "Lcom/inmobi/ads/InMobiInterstitial;"
  find_and_patch "com/inmobi/ads/InMobiBanner" \
    "load" \
    "InMobi" "Lcom/inmobi/ads/InMobiBanner;"

  # Chartboost (legacy API)
  find_and_patch "com/chartboost/sdk/Chartboost" \
    "startWithAppId,cacheInterstitial,showInterstitial,cacheRewardedVideo,showRewardedVideo" \
    "Chartboost" "Lcom/chartboost/sdk/Chartboost;"
  # Chartboost (new ads API)
  find_and_patch "com/chartboost/sdk/ads/Interstitial" \
    "cache,show" \
    "Chartboost" "Lcom/chartboost/sdk/ads/Interstitial;"
  find_and_patch "com/chartboost/sdk/ads/Rewarded" \
    "cache,show" \
    "Chartboost" "Lcom/chartboost/sdk/ads/Rewarded;"

  # Pangle / TikTok (legacy API)
  find_and_patch "com/bytedance/sdk/openadsdk/TTAdSdk" \
    "init" \
    "Pangle" "Lcom/bytedance/sdk/openadsdk/TTAdSdk;"
  # Pangle new API
  find_and_patch "com/bytedance/sdk/openadsdk/api/init/PAGSdk" \
    "init" \
    "Pangle" "Lcom/bytedance/sdk/openadsdk/api/init/PAGSdk;"

  # Mintegral
  find_and_patch "com/mbridge/msdk/MBridgeSDKFactory" \
    "getMBridgeSDK" \
    "Mintegral" "Lcom/mbridge/msdk/MBridgeSDKFactory;"
  find_and_patch "com/mbridge/msdk/MBridgeSDK" \
    "init,initAsync,preload" \
    "Mintegral" "Lcom/mbridge/msdk/MBridgeSDK;"

  # BidMachine
  find_and_patch "io/bidmachine/BidMachine" \
    "initialize" \
    "BidMachine" "Lio/bidmachine/BidMachine;"

  # Smaato
  find_and_patch "com/smaato/sdk/core/SmaatoSdk" \
    "init" \
    "Smaato" "Lcom/smaato/sdk/core/SmaatoSdk;"

  # Verve / HyBid (PubNative)
  find_and_patch "net/pubnative/lite/sdk/HyBid" \
    "initialize" \
    "Verve" "Lnet/pubnative/lite/sdk/HyBid;"

  # Ogury
  find_and_patch "com/ogury/sdk/Ogury" \
    "start" \
    "Ogury" "Lcom/ogury/sdk/Ogury;"

  # Fyber / DT Exchange (InnerActive)
  find_and_patch "com/fyber/inneractive/sdk/external/InneractiveAdManager" \
    "initialize" \
    "Fyber" "Lcom/fyber/inneractive/sdk/external/InneractiveAdManager;"

  # Amazon APS
  find_and_patch "com/amazon/device/ads/AdRegistration" \
    "setAppKey,enableTesting,enableLogging" \
    "AmazonAPS" "Lcom/amazon/device/ads/AdRegistration;"
}

patch_tracker_targets() {
  # Firebase Analytics
  find_and_patch "com/google/firebase/analytics/FirebaseAnalytics" \
    "getInstance,logEvent,setUserId,setUserProperty,setAnalyticsCollectionEnabled" \
    "Firebase" "Lcom/google/firebase/analytics/FirebaseAnalytics;"

  # Adjust
  find_and_patch "com/adjust/sdk/Adjust" \
    "onCreate,trackEvent,addSessionCallbackParameter,addSessionPartnerParameter,setEnabled" \
    "Adjust" "Lcom/adjust/sdk/Adjust;"

  # AppsFlyer
  find_and_patch "com/appsflyer/AppsFlyerLib" \
    "getInstance,init,start,logEvent,setCustomerUserId" \
    "AppsFlyer" "Lcom/appsflyer/AppsFlyerLib;"

  # Mixpanel
  find_and_patch "com/mixpanel/android/mpmetrics/MixpanelAPI" \
    "getInstance,track,trackMap,identify,timeEvent,registerSuperProperties" \
    "Mixpanel" "Lcom/mixpanel/android/mpmetrics/MixpanelAPI;"

  # Amplitude
  find_and_patch "com/amplitude/api/AmplitudeClient" \
    "getInstance,initialize,logEvent,setUserId,setUserProperties" \
    "Amplitude" "Lcom/amplitude/api/AmplitudeClient;"

  # Segment
  find_and_patch "com/segment/analytics/Analytics" \
    "with,track,identify,screen,group,alias" \
    "Segment" "Lcom/segment/analytics/Analytics;"

  # Braze (and legacy Appboy)
  find_and_patch "com/braze/Braze" \
    "configure,logCustomEvent,changeUser,logPurchase" \
    "Braze" "Lcom/braze/Braze;"
  find_and_patch "com/appboy/Appboy" \
    "configure,logCustomEvent,changeUser" \
    "Braze" "Lcom/appboy/Appboy;"

  # CleverTap
  find_and_patch "com/clevertap/android/sdk/CleverTapAPI" \
    "getDefaultInstance,pushEvent,onUserLogin,pushProfile,recordEvent" \
    "CleverTap" "Lcom/clevertap/android/sdk/CleverTapAPI;"

  # Flurry
  find_and_patch "com/flurry/android/FlurryAgent" \
    "logEvent,setUserId,onStartSession,onEndSession" \
    "Flurry" "Lcom/flurry/android/FlurryAgent;"

  # Facebook SDK core
  find_and_patch "com/facebook/FacebookSdk" \
    "sdkInitialize,fullyInitialize,setAutoInitEnabled,setAutoLogAppEventsEnabled" \
    "Facebook" "Lcom/facebook/FacebookSdk;"

  # Firebase Crashlytics
  find_and_patch "com/google/firebase/crashlytics/FirebaseCrashlytics" \
    "log,recordException,setUserId,setCustomKey,setCrashlyticsCollectionEnabled" \
    "Firebase" "Lcom/google/firebase/crashlytics/FirebaseCrashlytics;"
}

# =====================================================================
# patch_manifest() — Disable SDK components in AndroidManifest.xml
# =====================================================================

patch_manifest() {
  if [[ "$DO_MANIFEST" == false ]] || [[ ! -f "$MANIFEST" ]]; then
    return
  fi

  # Known SDK components to disable
  # Format: "component_substring|sdk_name"
  local -a AD_COMPONENTS=(
    "com.google.android.gms.ads.AdActivity|AdMob"
    "com.google.android.gms.ads.MobileAdsInitProvider|AdMob"
    "com.google.android.gms.ads.AdService|AdMob"
    "com.unity3d.ads.adunit.AdUnitActivity|UnityAds"
    "com.unity3d.ads.adunit.AdUnitTransparentActivity|UnityAds"
    "com.unity3d.services.ads.adunit.AdUnitActivity|UnityAds"
    "com.ironsource.sdk.controller.InterstitialActivity|IronSource"
    "com.ironsource.sdk.controller.ControllerActivity|IronSource"
    "com.applovin.adview.AppLovinFullscreenActivity|AppLovin"
    "com.applovin.sdk.AppLovinWebViewActivity|AppLovin"
    "com.facebook.ads.AudienceNetworkActivity|MetaAN"
    "com.facebook.ads.InterstitialAdActivity|MetaAN"
    "com.vungle.warren.ui.VungleActivity|Vungle"
    "com.chartboost.sdk.CBImpressionActivity|Chartboost"
    "com.bytedance.sdk.openadsdk.activity.TTFullScreenVideoActivity|Pangle"
    "com.bytedance.sdk.openadsdk.activity.TTRewardVideoActivity|Pangle"
    "com.vungle.ads.internal.ui.VungleActivity|Vungle"
    "com.facebook.ads.AudienceNetworkContentProvider|MetaAN"
    "com.applovin.sdk.AppLovinInitProvider|AppLovin"
    "io.bidmachine.BidMachineInitProvider|BidMachine"
    "com.ironsource.lifecycle.IronsourceLifecycleProvider|IronSource"
    "com.amazon.device.ads.DTBAdActivity|AmazonAPS"
    "com.bytedance.sdk.openadsdk.activity.TTInterstitialActivity|Pangle"
    "com.bytedance.sdk.openadsdk.activity.TTAdActivity|Pangle"
    "com.bytedance.sdk.openadsdk.activity.TTDelegateActivity|Pangle"
    "com.mbridge.msdk.activity.MBCommonActivity|Mintegral"
    "com.mbridge.msdk.reward.player.MBRewardVideoActivity|Mintegral"
    "com.smaato.sdk.core.SmaatoBroadcastReceiver|Smaato"
  )

  local -a TRACKER_COMPONENTS=(
    "com.google.android.gms.measurement.AppMeasurementService|Firebase"
    "com.google.android.gms.measurement.AppMeasurementReceiver|Firebase"
    "com.google.android.gms.measurement.AppMeasurementContentProvider|Firebase"
    "com.google.android.gms.measurement.AppMeasurementInstallReferrerReceiver|Firebase"
    "com.google.android.gms.measurement.AppMeasurementJobService|Firebase"
    "com.google.firebase.iid.FirebaseInstanceIdReceiver|Firebase"
    "com.adjust.sdk.AdjustReferrerReceiver|Adjust"
    "com.appsflyer.SingleInstallBroadcastReceiver|AppsFlyer"
    "com.appsflyer.MultipleInstallBroadcastReceiver|AppsFlyer"
    "com.mixpanel.android.mpmetrics.MixpanelFCMMessagingService|Mixpanel"
    "com.braze.push.BrazeFirebaseMessagingService|Braze"
    "com.clevertap.android.sdk.pushnotification.CTPushNotificationReceiver|CleverTap"
    "com.clevertap.android.sdk.pushnotification.CTNotificationIntentService|CleverTap"
    "com.appsflyer.internal.AFSingleInstallBroadcastReceiver|AppsFlyer"
  )

  local -a components_to_disable=()

  if [[ "$NO_BUILTIN_TARGETS" == false ]]; then
    if [[ "$NEUTRALIZE_ALL" == true ]] || [[ "$NEUTRALIZE_ADS" == true ]]; then
      components_to_disable+=("${AD_COMPONENTS[@]}")
    fi
    if [[ "$NEUTRALIZE_ALL" == true ]] || [[ "$NEUTRALIZE_TRACKERS" == true ]]; then
      components_to_disable+=("${TRACKER_COMPONENTS[@]}")
    fi
  fi

  # Load additional components from file (registry-scan.py output)
  if [[ -n "$MANIFEST_COMPONENTS_FILE" ]] && [[ -f "$MANIFEST_COMPONENTS_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      [[ "$line" == \#* ]] && continue
      components_to_disable+=("$line")
    done < "$MANIFEST_COMPONENTS_FILE"
  fi

  if [[ "$DO_BACKUP" == true ]] && [[ "$DRY_RUN" == false ]]; then
    cp "$MANIFEST" "${MANIFEST}.bak"
  fi

  for entry in "${components_to_disable[@]}"; do
    local component_name="${entry%%|*}"
    local sdk_name="${entry##*|}"

    # Check if the component exists in the manifest
    if grep -q "$component_name" "$MANIFEST"; then
      # Determine component type
      local comp_type="unknown"
      if grep -B1 "$component_name" "$MANIFEST" | grep -q "<activity"; then
        comp_type="activity"
      elif grep -B1 "$component_name" "$MANIFEST" | grep -q "<service"; then
        comp_type="service"
      elif grep -B1 "$component_name" "$MANIFEST" | grep -q "<receiver"; then
        comp_type="receiver"
      elif grep -B1 "$component_name" "$MANIFEST" | grep -q "<provider"; then
        comp_type="provider"
      fi

      # Check if already disabled
      if grep "$component_name" "$MANIFEST" | grep -q 'android:enabled="false"'; then
        continue
      fi

      if [[ "$DRY_RUN" == true ]]; then
        echo "DRY_RUN:WOULD_DISABLE:$comp_type:$component_name:$sdk_name"
      else
        if grep "$component_name" "$MANIFEST" | grep -q 'android:enabled='; then
          # Replace existing android:enabled value (avoids duplicate attribute)
          sed -i "/$component_name/s|android:enabled=\"[^\"]*\"|android:enabled=\"false\"|g" "$MANIFEST"
        else
          # Add android:enabled="false" after android:name
          sed -i "s|android:name=\"$component_name\"|android:name=\"$component_name\" android:enabled=\"false\"|g" "$MANIFEST"
        fi
        echo "MANIFEST_DISABLED:$comp_type:$component_name:$sdk_name"
        echo "MANIFEST_DISABLED:$comp_type:$component_name:$sdk_name" >> "$PATCH_LOG_FILE"
      fi
      COMPONENTS_DISABLED=$((COMPONENTS_DISABLED + 1))
    fi
  done
}

# =====================================================================
# Load custom targets from file
# =====================================================================

patch_custom_targets() {
  if [[ -z "$TARGETS_FILE" ]] || [[ ! -f "$TARGETS_FILE" ]]; then
    return
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    # Format: Lcom/example/Class;:methodName or com/example/Class:methodName
    # Wildcards: com/example/pkg/**:* (all methods in package)
    #            com/example/Class:* (all methods in class)
    local class_part="${line%%:*}"
    local method_part="${line##*:}"

    if [[ -z "$class_part" ]] || [[ -z "$method_part" ]]; then
      echo "Warning: Skipping malformed target line: $line" >&2
      continue
    fi

    # Normalize class path: remove L prefix and ; suffix if present
    class_part="${class_part#L}"
    class_part="${class_part%;}"

    # Handle package wildcard: com/example/pkg/** — treat as --package
    if [[ "$class_part" == *"/**" ]]; then
      local pkg_path="${class_part%/**}"
      echo "  Wildcard target: neutralizing package $pkg_path"
      for smali_dir in "${SMALI_DIRS[@]}"; do
        local pkg_dir="$smali_dir/$pkg_path"
        if [[ ! -d "$pkg_dir" ]]; then
          continue
        fi
        while IFS= read -r -d '' smali_file; do
          if [[ "$method_part" == "*" ]]; then
            patch_all_methods "$smali_file" "Custom"
          else
            local file_class_desc
            file_class_desc=$(grep -m1 '^\.class ' "$smali_file" | grep -oP 'L[^ ;]+;' | head -1)
            patch_method "$smali_file" "$method_part" "Custom" "${file_class_desc:-Lunknown;}"
          fi
        done < <(find "$pkg_dir" -name "*.smali" -print0 2>/dev/null)
      done
      continue
    fi

    # Handle class wildcard: com/example/Class:* — all methods in one class
    if [[ "$method_part" == "*" ]]; then
      local class_desc="L${class_part};"
      for smali_dir in "${SMALI_DIRS[@]}"; do
        local smali_file="$smali_dir/$class_part.smali"
        if [[ -f "$smali_file" ]]; then
          patch_all_methods "$smali_file" "Custom"
        fi
      done
      continue
    fi

    # Standard target: specific class + method
    local class_desc="L${class_part};"
    find_and_patch "$class_part" "$method_part" "Custom" "$class_desc"
  done < "$TARGETS_FILE"
}

# =====================================================================
# Replay from neutralize-manifest.json
# =====================================================================

if [[ "$DO_REPLAY" == true ]]; then
  MANIFEST_JSON="$DECODED_DIR/neutralize-manifest.json"
  if [[ ! -f "$MANIFEST_JSON" ]]; then
    echo "Error: neutralize-manifest.json not found in $DECODED_DIR" >&2
    echo "Cannot replay without a previous neutralization manifest." >&2
    exit 1
  fi

  echo "=== Replaying from neutralize-manifest.json ==="

  # Restore original scope from saved options
  saved_options=""
  if command -v jq &>/dev/null; then
    saved_options=$(jq -r '.options // ""' "$MANIFEST_JSON" 2>/dev/null)
  else
    saved_options=$(awk -F'"' '/"options"/ { print $4 }' "$MANIFEST_JSON")
  fi

  case "$saved_options" in
    *--all*)     NEUTRALIZE_ALL=true ;;
    *--ads*)     NEUTRALIZE_ADS=true; NEUTRALIZE_ALL=false ;;
    *--trackers*) NEUTRALIZE_TRACKERS=true; NEUTRALIZE_ALL=false ;;
  esac

  # Extract class:method pairs into a temporary targets file
  REPLAY_TARGETS=$(mktemp "${TMPDIR:-/tmp}/replay-targets-XXXXXX")

  if command -v jq &>/dev/null; then
    jq -r '.patched_methods[]? | .class + ":" + .method' "$MANIFEST_JSON" > "$REPLAY_TARGETS" 2>/dev/null
  else
    # Fallback: parse JSON with awk (handles the simple array-of-objects format)
    awk '
      /"class"/ { gsub(/[",]/, ""); gsub(/^[[:space:]]*class:[[:space:]]*/, ""); class = $2 }
      /"method"/ { gsub(/[",]/, ""); gsub(/^[[:space:]]*method:[[:space:]]*/, ""); method = $2
        if (class != "" && method != "") print class ":" method
      }
    ' "$MANIFEST_JSON" > "$REPLAY_TARGETS" 2>/dev/null
  fi

  replay_count=$(wc -l < "$REPLAY_TARGETS" | tr -d ' ')
  echo "Loaded $replay_count method targets from previous manifest."

  if [[ "$replay_count" -gt 0 ]]; then
    if [[ -n "$TARGETS_FILE" ]]; then
      # Merge replay targets into existing targets file
      cat "$REPLAY_TARGETS" >> "$TARGETS_FILE"
    else
      TARGETS_FILE="$REPLAY_TARGETS"
    fi
  fi

  echo
fi

# =====================================================================
# Cleanup backups (if requested)
# =====================================================================

if [[ "$DO_CLEANUP_BACKUPS" == true ]]; then
  bak_count=0
  while IFS= read -r -d '' bakfile; do
    rm -f "$bakfile"
    bak_count=$((bak_count + 1))
  done < <(find "$DECODED_DIR" -name "*.smali.bak" -print0 2>/dev/null)
  echo "Cleaned up $bak_count .smali.bak file(s) from $DECODED_DIR"
fi

# =====================================================================
# Main
# =====================================================================

if [[ "$DRY_RUN" == true ]]; then
  echo "=== SDK Neutralizer — DRY RUN ==="
else
  echo "=== SDK Neutralizer ==="
fi
echo "Decoded directory: $DECODED_DIR"
echo "Smali directories: ${SMALI_DIRS[*]}"
echo

# Patch SDK targets
if [[ "$NO_BUILTIN_TARGETS" == true ]]; then
  echo "--- Skipping builtin targets (--no-builtin-targets) ---"
  echo
else
  if [[ "$NEUTRALIZE_ALL" == true ]] || [[ "$NEUTRALIZE_ADS" == true ]]; then
    echo "--- Neutralizing Ad SDK entry points ---"
    patch_ad_targets
    echo
  fi

  if [[ "$NEUTRALIZE_ALL" == true ]] || [[ "$NEUTRALIZE_TRACKERS" == true ]]; then
    echo "--- Neutralizing Tracker SDK entry points ---"
    patch_tracker_targets
    echo
  fi
fi

# Patch custom targets
if [[ -n "$TARGETS_FILE" ]]; then
  echo "--- Neutralizing custom targets from $TARGETS_FILE ---"
  patch_custom_targets
  echo
fi

# Patch packages (--package flag)
if [[ ${#PACKAGE_PATHS[@]} -gt 0 ]]; then
  echo "--- Neutralizing packages ---"
  patch_packages
fi

# Patch manifest
patch_manifest

# Summary
echo
echo "=== Neutralization Summary ==="
echo "Methods patched: $METHODS_PATCHED"
echo "Manifest components disabled: $COMPONENTS_DISABLED"

if [[ "$DRY_RUN" == true ]]; then
  echo
  echo "DRY RUN — no files were modified."
  echo "Remove --dry-run to apply changes."
fi

if [[ "$METHODS_PATCHED" -eq 0 ]] && [[ "$COMPONENTS_DISABLED" -eq 0 ]]; then
  echo
  echo "No targets found in the decoded directory."
  echo "The app may not contain the targeted SDKs, or they may use obfuscated class names."
  exit 2
fi

# =====================================================================
# Save neutralize-manifest.json
# =====================================================================

if [[ "$DO_SAVE_MANIFEST" == true ]] && [[ "$DRY_RUN" == false ]] && \
   [[ "$METHODS_PATCHED" -gt 0 || "$COMPONENTS_DISABLED" -gt 0 ]]; then

  MANIFEST_JSON="$DECODED_DIR/neutralize-manifest.json"
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S")

  # Build options string
  OPTIONS_STR=""
  if [[ "$NEUTRALIZE_ALL" == true ]]; then
    OPTIONS_STR="--all"
  else
    [[ "$NEUTRALIZE_ADS" == true ]] && OPTIONS_STR="${OPTIONS_STR} --ads"
    [[ "$NEUTRALIZE_TRACKERS" == true ]] && OPTIONS_STR="${OPTIONS_STR} --trackers"
    OPTIONS_STR="${OPTIONS_STR# }"
  fi

  # Build JSON from patch log file using printf (no jq dependency for writing)
  {
    printf '{\n'
    printf '  "timestamp": "%s",\n' "$TIMESTAMP"
    printf '  "options": "%s",\n' "$OPTIONS_STR"
    printf '  "patched_methods": [\n'

    first_method=true
    while IFS= read -r logline; do
      if [[ "$logline" == PATCHED:* ]]; then
        # PATCHED:<sdk>:<class>:<method>:<stub_type>:<file>
        IFS=':' read -r _ p_sdk p_class p_method p_stub p_file <<< "$logline"
        if [[ "$first_method" == true ]]; then
          first_method=false
        else
          printf ',\n'
        fi
        printf '    {"sdk": "%s", "class": "%s", "method": "%s", "stub": "%s", "file": "%s"}' \
          "$p_sdk" "$p_class" "$p_method" "$p_stub" "$p_file"
      fi
    done < "$PATCH_LOG_FILE"

    printf '\n  ],\n'
    printf '  "disabled_components": [\n'

    first_comp=true
    while IFS= read -r logline; do
      if [[ "$logline" == MANIFEST_DISABLED:* ]]; then
        # MANIFEST_DISABLED:<type>:<name>:<sdk>
        IFS=':' read -r _ c_type c_name c_sdk <<< "$logline"
        if [[ "$first_comp" == true ]]; then
          first_comp=false
        else
          printf ',\n'
        fi
        printf '    {"type": "%s", "name": "%s", "sdk": "%s"}' \
          "$c_type" "$c_name" "$c_sdk"
      fi
    done < "$PATCH_LOG_FILE"

    printf '\n  ]\n'
    printf '}\n'
  } > "$MANIFEST_JSON"

  echo
  echo "Patch manifest saved: $MANIFEST_JSON"
  echo "Use --replay after re-decode to reapply the same patches."
fi

exit 0
