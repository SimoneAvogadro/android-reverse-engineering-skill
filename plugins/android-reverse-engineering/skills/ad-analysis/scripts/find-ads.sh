#!/usr/bin/env bash
# find-ads.sh — Search decompiled source for advertising SDK usage
set -euo pipefail

usage() {
  cat <<EOF
Usage: find-ads.sh <source-dir> [OPTIONS]

Search decompiled Java/Kotlin source for advertising SDK usage.

Arguments:
  <source-dir>    Path to the decompiled sources directory

Options:
  --admob         Search only for AdMob/Google Mobile Ads
  --unity         Search only for Unity Ads
  --ironsource    Search only for IronSource/LevelPlay
  --applovin      Search only for AppLovin/MAX
  --facebook      Search only for Meta Audience Network
  --vungle        Search only for Vungle/Liftoff
  --inmobi        Search only for InMobi
  --chartboost    Search only for Chartboost
  --pangle        Search only for Pangle/TikTok
  --mintegral     Search only for Mintegral
  --formats       Search only for cross-SDK ad format patterns
  --mediation     Search only for mediation adapter patterns
  --consent       Search only for consent/privacy framework patterns
  --manifest      Search only for AndroidManifest.xml ad markers
  --entrypoints   Search only for ad SDK calls in app code (excludes library packages)
  --all           Search all patterns (default)
  -h, --help      Show this help message

Output:
  Results are printed as file:line:match for easy navigation.
EOF
  exit 0
}

SOURCE_DIR=""
SEARCH_ADMOB=false
SEARCH_UNITY=false
SEARCH_IRONSOURCE=false
SEARCH_APPLOVIN=false
SEARCH_FACEBOOK=false
SEARCH_VUNGLE=false
SEARCH_INMOBI=false
SEARCH_CHARTBOOST=false
SEARCH_PANGLE=false
SEARCH_MINTEGRAL=false
SEARCH_FORMATS=false
SEARCH_MEDIATION=false
SEARCH_CONSENT=false
SEARCH_MANIFEST=false
SEARCH_ENTRYPOINTS=false
SEARCH_ALL=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --admob)       SEARCH_ADMOB=true;       SEARCH_ALL=false; shift ;;
    --unity)       SEARCH_UNITY=true;       SEARCH_ALL=false; shift ;;
    --ironsource)  SEARCH_IRONSOURCE=true;  SEARCH_ALL=false; shift ;;
    --applovin)    SEARCH_APPLOVIN=true;    SEARCH_ALL=false; shift ;;
    --facebook)    SEARCH_FACEBOOK=true;    SEARCH_ALL=false; shift ;;
    --vungle)      SEARCH_VUNGLE=true;      SEARCH_ALL=false; shift ;;
    --inmobi)      SEARCH_INMOBI=true;      SEARCH_ALL=false; shift ;;
    --chartboost)  SEARCH_CHARTBOOST=true;  SEARCH_ALL=false; shift ;;
    --pangle)      SEARCH_PANGLE=true;      SEARCH_ALL=false; shift ;;
    --mintegral)   SEARCH_MINTEGRAL=true;   SEARCH_ALL=false; shift ;;
    --formats)     SEARCH_FORMATS=true;     SEARCH_ALL=false; shift ;;
    --mediation)   SEARCH_MEDIATION=true;   SEARCH_ALL=false; shift ;;
    --consent)     SEARCH_CONSENT=true;     SEARCH_ALL=false; shift ;;
    --manifest)    SEARCH_MANIFEST=true;    SEARCH_ALL=false; shift ;;
    --entrypoints) SEARCH_ENTRYPOINTS=true; SEARCH_ALL=false; shift ;;
    --all)         SEARCH_ALL=true; shift ;;
    -h|--help)     usage ;;
    -*)            echo "Error: Unknown option $1" >&2; usage ;;
    *)             SOURCE_DIR="$1"; shift ;;
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

run_grep_xml() {
  local pattern="$1"
  grep -rn --include="*.xml" -E "$pattern" "$SOURCE_DIR" 2>/dev/null || true
}

# --- AdMob / Google Mobile Ads ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_ADMOB" == true ]]; then
  section "AdMob — Initialization"
  run_grep '(MobileAds\.initialize\s*\(|MobileAds\.setRequestConfiguration|com\.google\.android\.gms\.ads)'
  section "AdMob — Banner"
  run_grep '(AdView\s|AdSize\.|\.loadAd\s*\(|AdRequest\.Builder|com\.google\.android\.gms\.ads\.AdView)'
  section "AdMob — Interstitial"
  run_grep '(InterstitialAd\.load\s*\(|InterstitialAdLoadCallback|FullScreenContentCallback|com\.google\.android\.gms\.ads\.interstitial)'
  section "AdMob — Rewarded"
  run_grep '(RewardedAd\.load\s*\(|RewardedAdLoadCallback|OnUserEarnedRewardListener|RewardedInterstitialAd\.load)'
  section "AdMob — Native"
  run_grep '(AdLoader\.Builder|NativeAd\.|NativeAdView|UnifiedNativeAd|NativeAdOptions|com\.google\.android\.gms\.ads\.nativead)'
  section "AdMob — App Open"
  run_grep '(AppOpenAd\.load\s*\(|AppOpenAd\.AppOpenAdLoadCallback|AppOpenAdManager)'
  section "AdMob — Ad Unit IDs"
  run_grep '(ca-app-pub-|/[0-9]+/[0-9]+|adUnitId|setAdUnitId\s*\()'
fi

# --- Unity Ads ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_UNITY" == true ]]; then
  section "Unity Ads — Initialization"
  run_grep '(UnityAds\.initialize\s*\(|UnityAds\.isInitialized|IUnityAdsInitializationListener|com\.unity3d\.ads)'
  section "Unity Ads — Load & Show"
  run_grep '(UnityAds\.load\s*\(|UnityAds\.show\s*\(|IUnityAdsLoadListener|IUnityAdsShowListener)'
  section "Unity Ads — Banner"
  run_grep '(BannerView\s*\(|UnityBannerSize|com\.unity3d\.services\.banners)'
fi

# --- IronSource / LevelPlay ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_IRONSOURCE" == true ]]; then
  section "IronSource — Initialization"
  run_grep '(IronSource\.init\s*\(|IronSource\.setUserId|IronSourceConfig|com\.ironsource\.mediationsdk)'
  section "IronSource — Interstitial"
  run_grep '(IronSource\.loadInterstitial|IronSource\.showInterstitial|IronSource\.isInterstitialReady|InterstitialListener)'
  section "IronSource — Rewarded Video"
  run_grep '(IronSource\.showRewardedVideo|IronSource\.isRewardedVideoAvailable|RewardedVideoListener)'
  section "IronSource — Banner"
  run_grep '(IronSource\.loadBanner|IronSource\.destroyBanner|IronSourceBannerLayout|BannerListener)'
  section "IronSource — LevelPlay"
  run_grep '(LevelPlay|LevelPlayAdError|LevelPlayBannerAdView|LevelPlayInterstitialAd|LevelPlayRewardedAd)'
fi

# --- AppLovin / MAX ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_APPLOVIN" == true ]]; then
  section "AppLovin — Initialization"
  run_grep '(AppLovinSdk\.getInstance|AppLovinSdk\.initializeSdk|AppLovinSdkSettings|com\.applovin\.sdk)'
  section "AppLovin MAX — Banner"
  run_grep '(MaxAdView\s|MaxAdViewAdListener|maxAdView\.loadAd|maxAdView\.startAutoRefresh)'
  section "AppLovin MAX — Interstitial"
  run_grep '(MaxInterstitialAd\s*\(|MaxAdListener|interstitialAd\.loadAd|interstitialAd\.showAd)'
  section "AppLovin MAX — Rewarded"
  run_grep '(MaxRewardedAd\.getInstance|MaxRewardedAdListener|rewardedAd\.loadAd|rewardedAd\.showAd)'
  section "AppLovin MAX — Native"
  run_grep '(MaxNativeAdLoader|MaxNativeAdView|MaxNativeAdListener)'
fi

# --- Facebook / Meta Audience Network ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_FACEBOOK" == true ]]; then
  section "Meta Audience Network — Initialization"
  run_grep '(AudienceNetworkAds\.initialize|AudienceNetworkAds\.buildInitSettings|com\.facebook\.ads)'
  section "Meta AN — Banner"
  run_grep '(com\.facebook\.ads\.AdView|com\.facebook\.ads\.AdSize|\.loadAd\s*\(.*AdView)'
  section "Meta AN — Interstitial"
  run_grep '(com\.facebook\.ads\.InterstitialAd|InterstitialAdListener|InterstitialAdExtendedListener)'
  section "Meta AN — Rewarded"
  run_grep '(RewardedVideoAd\s*\(|RewardedVideoAdListener|RewardedVideoAdExtendedListener|com\.facebook\.ads\.RewardedVideoAd)'
  section "Meta AN — Native"
  run_grep '(NativeAd\s*\(|NativeBannerAd|NativeAdListener|com\.facebook\.ads\.NativeAd|NativeAdLayout)'
fi

# --- Vungle / Liftoff ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_VUNGLE" == true ]]; then
  section "Vungle — Initialization & Ads"
  run_grep '(Vungle\.init\s*\(|VungleInitListener|Vungle\.loadAd\s*\(|Vungle\.playAd\s*\(|Vungle\.isInitialized|com\.vungle\.warren)'
  run_grep '(VungleBanner|VungleInterstitial|VungleRewarded|VungleNativeAd|com\.vungle\.ads)'
fi

# --- InMobi ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_INMOBI" == true ]]; then
  section "InMobi — Initialization & Ads"
  run_grep '(InMobiSdk\.init\s*\(|InMobiBanner|InMobiInterstitial|InMobiNative|com\.inmobi\.sdk|com\.inmobi\.ads)'
fi

# --- Chartboost ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_CHARTBOOST" == true ]]; then
  section "Chartboost — Initialization & Ads"
  run_grep '(Chartboost\.startWithAppId|Chartboost\.showInterstitial|Chartboost\.showRewardedVideo|Chartboost\.cacheInterstitial|com\.chartboost\.sdk)'
fi

# --- Pangle / TikTok ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_PANGLE" == true ]]; then
  section "Pangle — Initialization & Ads"
  run_grep '(TTAdSdk\.init\s*\(|TTAdConfig\.Builder|TTAdNative|TTFullScreenVideoAd|TTRewardVideoAd|TTBannerAd|com\.bytedance\.sdk\.openadsdk)'
  run_grep '(PAGSdk\.init\s*\(|PAGConfig\.Builder|PAGBannerAd|PAGInterstitialAd|PAGRewardedAd|com\.pgl\.sys)'
fi

# --- Mintegral ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_MINTEGRAL" == true ]]; then
  section "Mintegral — Initialization & Ads"
  run_grep '(MBridgeSDKFactory\.getMBridgeSDK|MBBannerView|MBInterstitialVideoHandler|MBRewardVideoHandler|MBNewInterstitialHandler|com\.mbridge\.msdk)'
fi

# --- Cross-SDK Ad Format Patterns ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_FORMATS" == true ]]; then
  section "Cross-SDK — All Banner Patterns"
  run_grep '(BannerView|AdView|BannerAd|IronSourceBannerLayout|MaxAdView|MBBannerView|PAGBannerAd|TTBannerAd|InMobiBanner|VungleBanner)'
  section "Cross-SDK — All Interstitial Patterns"
  run_grep '(InterstitialAd|showInterstitial|loadInterstitial|MaxInterstitialAd|MBInterstitialVideoHandler|PAGInterstitialAd|TTFullScreenVideoAd|InMobiInterstitial|VungleInterstitial)'
  section "Cross-SDK — All Rewarded Patterns"
  run_grep '(RewardedAd|RewardedVideo|showRewardedVideo|MaxRewardedAd|MBRewardVideoHandler|PAGRewardedAd|TTRewardVideoAd|VungleRewarded|OnUserEarnedRewardListener)'
  section "Cross-SDK — All Native Patterns"
  run_grep '(NativeAd|NativeAdView|NativeAdLoader|NativeBannerAd|MaxNativeAdLoader|InMobiNative|VungleNativeAd|NativeAdLayout)'
  section "Cross-SDK — Ad Unit / Placement IDs"
  run_grep '(adUnitId|setAdUnitId|placementId|setPlacementId|PLACEMENT_ID|AD_UNIT_ID|ca-app-pub-|BANNER_ID|INTERSTITIAL_ID|REWARDED_ID)'
fi

# --- Mediation Adapters ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_MEDIATION" == true ]]; then
  section "Mediation — Google AdMob Mediation Adapters"
  run_grep '(com\.google\.ads\.mediation|MediationAdapter|MediationBannerAdapter|MediationInterstitialAdapter|MediationRewardedAd)'
  section "Mediation — IronSource Mediation Adapters"
  run_grep '(com\.ironsource\.adapters|IronSourceAdapter|ISBannerAdapter|ISInterstitialAdapter|ISRewardedVideoAdapter)'
  section "Mediation — AppLovin MAX Mediation Adapters"
  run_grep '(com\.applovin\.mediation\.adapters|MediationAdapterBase|MaxAdapter|MaxMediatedNetworkInfo)'
  section "Mediation — Waterfall & Bidding Configuration"
  run_grep '(waterfall|bidding|headerBidding|realTimeBidding|setWaterfall|mediationConfig|adNetworkId|networkName)'
fi

# --- Consent / Privacy Frameworks ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_CONSENT" == true ]]; then
  section "Consent — Google UMP / Funding Choices"
  run_grep '(ConsentInformation|ConsentRequestParameters|ConsentForm\.load|UserMessagingPlatform|com\.google\.android\.ump)'
  section "Consent — IAB TCF v2"
  run_grep '(IABTCF_|TCString|GDPR_APPLIES|GDPR_CONSENT|gdprApplies|tcfPolicyVersion|tcString)'
  section "Consent — COPPA / Child-Directed"
  run_grep '(tagForChildDirectedTreatment|COPPA|TAG_FOR_CHILD_DIRECTED|setTagForUnderAgeOfConsent|maxAdContentRating)'
  section "Consent — SDK-specific Opt-out"
  run_grep '(setHasUserConsent|setDoNotSell|setCCPADoNotSell|setGDPRConsent|gdprForgetMe|setDataProcessingOptions|setNonPersonalizedOnly)'
fi

# --- AndroidManifest.xml Markers ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_MANIFEST" == true ]]; then
  section "AndroidManifest — Ad Activities & Services"
  run_grep_xml '(com\.google\.android\.gms\.ads|AdActivity|com\.unity3d\.ads|com\.ironsource|com\.applovin|com\.facebook\.ads|com\.vungle|com\.inmobi|com\.chartboost|com\.bytedance)'
  section "AndroidManifest — Ad Permissions"
  run_grep_xml '(AD_ID|com\.google\.android\.gms\.permission\.AD_ID|BIND_GET_INSTALL_REFERRER_SERVICE)'
  section "AndroidManifest — Ad Meta-data"
  run_grep_xml '(com\.google\.android\.gms\.ads\.APPLICATION_ID|com\.google\.android\.gms\.ads\.AD_MANAGER_APP|applovin\.sdk\.key|com\.facebook\.sdk\.ApplicationId|unity\.ads\.gameId)'
fi

# --- Entry Points: Ad SDK calls from app code only ---
if [[ "$SEARCH_ALL" == true || "$SEARCH_ENTRYPOINTS" == true ]]; then
  section "Entry Points — Ad SDK calls from app code (library packages excluded)"

  # Build --exclude-dir arguments for known library packages
  EXCLUDE_DIRS=(
    --exclude-dir="com/google"
    --exclude-dir="com/unity3d"
    --exclude-dir="com/ironsource"
    --exclude-dir="com/applovin"
    --exclude-dir="com/facebook"
    --exclude-dir="com/vungle"
    --exclude-dir="com/inmobi"
    --exclude-dir="com/chartboost"
    --exclude-dir="com/bytedance"
    --exclude-dir="com/pgl"
    --exclude-dir="com/mbridge"
    --exclude-dir="com/mintegral"
    --exclude-dir="com/adcolony"
    --exclude-dir="com/tapjoy"
    --exclude-dir="com/fyber"
    --exclude-dir="com/amazon/device/ads"
    --exclude-dir="io/vungle"
  )

  ENTRYPOINT_PATTERN='(MobileAds\.initialize|MobileAds\.setRequestConfiguration|InterstitialAd\.load|RewardedAd\.load|RewardedInterstitialAd\.load|AppOpenAd\.load|AdView\.loadAd|AdLoader\.Builder|UnityAds\.initialize|UnityAds\.load|UnityAds\.show|IronSource\.init|IronSource\.loadInterstitial|IronSource\.showInterstitial|IronSource\.showRewardedVideo|IronSource\.loadBanner|AppLovinSdk\.getInstance|AppLovinSdk\.initializeSdk|MaxInterstitialAd|MaxRewardedAd|MaxAdView|AudienceNetworkAds\.initialize|Vungle\.init|Vungle\.loadAd|Vungle\.playAd|InMobiSdk\.init|Chartboost\.startWithAppId|TTAdSdk\.init|PAGSdk\.init|MBridgeSDKFactory\.getMBridgeSDK|LevelPlayInterstitialAd|LevelPlayRewardedAd|LevelPlayBannerAdView)'

  # shellcheck disable=SC2086
  grep -rn --include="*.java" --include="*.kt" "${EXCLUDE_DIRS[@]}" -E "$ENTRYPOINT_PATTERN" "$SOURCE_DIR" 2>/dev/null || true

  echo
  echo "NOTE: Only calls from app code are shown above. Library-internal calls are excluded."
  echo "If no results appear, ad SDKs may only be invoked internally via mediation adapters."
fi

echo
echo "=== Search complete ==="
