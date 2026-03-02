# Mediation Patterns

How ad mediation works in decompiled Android code — identifying the primary mediator, adapter chains, waterfall vs bidding, and configuration extraction.

## What is Mediation

Ad mediation allows an app to use multiple ad networks through a single SDK. A **mediator** (e.g., AdMob, IronSource, AppLovin MAX) orchestrates which ad network serves each impression via:

- **Waterfall**: Networks are tried in priority order; first to fill wins
- **Bidding (header bidding)**: Networks bid simultaneously; highest bid wins
- **Hybrid**: Some networks bid, others fill via waterfall

## Identifying the Primary Mediator

The mediator is the SDK that controls ad loading. Look for:

### Google AdMob Mediation
```java
// AdMob is the mediator when you see mediation adapters:
com.google.ads.mediation.*
// Adapter classes follow the pattern:
com.google.ads.mediation.unity.UnityAdapter
com.google.ads.mediation.ironsource.IronSourceMediationAdapter
com.google.ads.mediation.applovin.AppLovinMediationAdapter
com.google.ads.mediation.facebook.FacebookMediationAdapter
com.google.ads.mediation.vungle.VungleMediationAdapter
```

**Grep**:
```bash
grep -rn 'com\.google\.ads\.mediation\.' "$SOURCE_DIR"
```

### IronSource / LevelPlay Mediation
```java
// IronSource is the mediator when you see adapter packages:
com.ironsource.adapters.*
// Adapter naming:
com.ironsource.adapters.admob.*
com.ironsource.adapters.unityads.*
com.ironsource.adapters.applovin.*
com.ironsource.adapters.facebook.*
com.ironsource.adapters.vungle.*
```

**Grep**:
```bash
grep -rn 'com\.ironsource\.adapters\.' "$SOURCE_DIR"
```

### AppLovin MAX Mediation
```java
// MAX is the mediator when you see MAX adapter packages:
com.applovin.mediation.adapters.*
// Adapter classes extend MediationAdapterBase:
com.applovin.mediation.adapters.GoogleMediationAdapter
com.applovin.mediation.adapters.UnityAdsMediationAdapter
com.applovin.mediation.adapters.IronSourceMediationAdapter
com.applovin.mediation.adapters.FacebookMediationAdapter
```

**Grep**:
```bash
grep -rn 'com\.applovin\.mediation\.adapters\.' "$SOURCE_DIR"
```

## Waterfall vs Bidding

### Waterfall indicators
```bash
# Priority/floor price configuration
grep -rn 'waterfall\|floorPrice\|ecpm\|eCPM\|setPriority\|adNetworkOrder' "$SOURCE_DIR"

# Manual network ordering
grep -rn 'setNetworkOrder\|setAdapterOrder\|setWaterfallConfiguration' "$SOURCE_DIR"
```

### Bidding indicators
```bash
# Real-time bidding signals
grep -rn 'bidding\|headerBidding\|bidToken\|collectSignal\|getBiddingToken' "$SOURCE_DIR"

# Bidding adapter classes (often have "Bidding" in the name)
grep -rn 'BiddingAdapter\|BiddingProvider\|RTBAdapter' "$SOURCE_DIR"

# MAX bidding
grep -rn 'MaxMediatedNetworkInfo\|isBidding\|bidFloor' "$SOURCE_DIR"
```

## Adapter Discovery

### List all mediation adapters present
```bash
# Find all adapter class files
find "$SOURCE_DIR" -path "*/mediation/adapters/*.java" -o -path "*/adapters/*Adapter*.java" | head -50

# Find adapter registration/initialization
grep -rn 'registerAdapter\|initializeAdapter\|setAdapterState\|MediationAdapter' "$SOURCE_DIR"
```

### Extract adapter configuration
```bash
# Network IDs and app keys passed to adapters
grep -rn 'setAppKey\|setAppId\|setGameId\|setSdkKey\|setNetworkKey' "$SOURCE_DIR"

# Ad unit/placement mapping (mediator → network)
grep -rn 'placementMap\|adUnitMap\|networkPlacementId\|customEventExtras' "$SOURCE_DIR"
```

## Common Mediation Setups

### Setup 1: AdMob as Mediator
```
AdMob (primary) → loads via:
  ├── Google Ads (direct)
  ├── UnityAdapter → Unity Ads SDK
  ├── IronSourceMediationAdapter → IronSource SDK
  ├── AppLovinMediationAdapter → AppLovin SDK
  └── FacebookMediationAdapter → Meta AN SDK
```

### Setup 2: IronSource/LevelPlay as Mediator
```
IronSource (primary) → loads via:
  ├── IronSource Network (direct)
  ├── AdMob adapter → Google Mobile Ads SDK
  ├── Unity adapter → Unity Ads SDK
  ├── AppLovin adapter → AppLovin SDK
  └── Vungle adapter → Vungle SDK
```

### Setup 3: AppLovin MAX as Mediator
```
AppLovin MAX (primary) → loads via:
  ├── AppLovin Network (direct, always bidding)
  ├── GoogleMediationAdapter → AdMob SDK
  ├── IronSourceMediationAdapter → IronSource SDK
  ├── UnityAdsMediationAdapter → Unity Ads SDK
  └── FacebookMediationAdapter → Meta AN SDK
```

## Active vs Passive SDKs

When mediation is present, most ad SDKs in the APK are **passive dependencies** — they are only invoked internally by the mediator's adapter classes, never by the app's own code.

### The Entry Point Graph

```
App code (com.example.myapp.*)
    │
    ▼
Mediator SDK (e.g., AdMob)          ← ACTIVE: called by app code
    │
    ├──→ Adapter (com.google.ads.mediation.unity.*)
    │        └──→ Unity Ads SDK     ← PASSIVE: called only by adapter
    │
    ├──→ Adapter (com.google.ads.mediation.ironsource.*)
    │        └──→ IronSource SDK    ← PASSIVE: called only by adapter
    │
    └──→ Adapter (com.google.ads.mediation.applovin.*)
             └──→ AppLovin SDK      ← PASSIVE: called only by adapter
```

### How to Distinguish

An SDK is **active** if its init/load/show calls appear in app code. An SDK is **passive** if its code is present only inside library packages.

**Key principle**: Search for SDK calls only in non-library directories. Known library packages to exclude:

| Package prefix | SDK |
|---|---|
| `com/google` | Google/AdMob |
| `com/unity3d` | Unity Ads |
| `com/ironsource` | IronSource/LevelPlay |
| `com/applovin` | AppLovin/MAX |
| `com/facebook` | Meta Audience Network |
| `com/vungle`, `io/vungle` | Vungle/Liftoff |
| `com/inmobi` | InMobi |
| `com/chartboost` | Chartboost |
| `com/bytedance`, `com/pgl` | Pangle/TikTok |
| `com/mbridge`, `com/mintegral` | Mintegral |

### Grep Examples

```bash
# Search for ad SDK calls ONLY in app code (exclude all library packages)
grep -rn --include="*.java" --include="*.kt" \
  --exclude-dir="com/google" --exclude-dir="com/unity3d" \
  --exclude-dir="com/ironsource" --exclude-dir="com/applovin" \
  --exclude-dir="com/facebook" --exclude-dir="com/vungle" \
  --exclude-dir="com/inmobi" --exclude-dir="com/chartboost" \
  --exclude-dir="com/bytedance" --exclude-dir="com/pgl" \
  --exclude-dir="com/mbridge" \
  -E '(MobileAds\.initialize|UnityAds\.initialize|IronSource\.init|AppLovinSdk\.getInstance)' \
  "$SOURCE_DIR"
```

**Interpreting results**:
- If `MobileAds.initialize` appears in `com/example/myapp/AdManager.java` → AdMob is **active**
- If `UnityAds.initialize` appears only in `com/google/ads/mediation/unity/UnityAdapter.java` → Unity Ads is **passive** (but this file is excluded, so it won't show up)
- If `UnityAds.initialize` appears in `com/example/myapp/AdsHelper.java` → Unity Ads is also **active** (direct integration alongside mediation)

### Architecture Classification

| Architecture | Meaning | Example |
|---|---|---|
| **Single mediator** | App calls 1 SDK; all others are passive adapter deps | AdMob init + 5 mediated networks |
| **Multiple direct** | App calls 2+ SDKs directly; no mediation | AdMob banners + Unity interstitials |
| **Hybrid** | App calls a mediator + some SDKs directly | AdMob mediation + direct IronSource rewarded |

### Automated Detection

Use the `--entrypoints` flag of `find-ads.sh`:

```bash
bash find-ads.sh <source-dir> --entrypoints
```

This runs the exclusion-based grep automatically and shows only app-initiated SDK calls.

## Extracting Mediation Configuration

Look for server-side configuration that controls the mediation waterfall:

```bash
# JSON config responses from mediation servers
grep -rn 'mediationConfig\|auctionResponse\|waterfallConfig\|adNetworkConfig' "$SOURCE_DIR"

# Remote config / A/B test for ad setup
grep -rn 'RemoteConfig.*ad\|firebase.*ad_config\|ad_waterfall\|ad_network_ids' "$SOURCE_DIR"
```
