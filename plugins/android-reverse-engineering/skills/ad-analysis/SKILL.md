---
description: Detect and analyze advertising SDKs in decompiled Android apps. Identifies AdMob, Unity Ads, IronSource/LevelPlay, AppLovin/MAX, Meta Audience Network, Vungle, InMobi, Chartboost, Pangle, Mintegral. Extracts ad formats (banner, interstitial, rewarded, native), mediation setup, ad unit IDs, and consent/privacy frameworks.
trigger: find ads|ad analysis|advertising SDK|detect ads|ad network|AdMob|Unity Ads|IronSource|AppLovin|Facebook ads|Meta Audience Network|Vungle|InMobi|Chartboost|Pangle|Mintegral|mediation|ad format|rewarded ad|interstitial ad|banner ad
---

# Ad Analysis

Detect and analyze advertising SDKs embedded in decompiled Android applications. Produces a structured report covering ad network identification, ad formats used, mediation configuration, ad unit/placement IDs, and consent/privacy framework compliance.

## Prerequisites

This skill operates on **already decompiled** source code. If the app has not been decompiled yet, use the `android-reverse-engineering` skill first:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/decompile.sh <apk-file>
```

The decompiled sources directory (typically `<output>/sources/`) is the input for this skill.

## Workflow

### Phase 1: Verify Decompiled Sources

Confirm that the decompiled source directory exists and contains Java/Kotlin files.

**Action**: Check the provided directory path.

- If the user provides a path, verify it exists and contains `.java` or `.kt` files
- If no decompiled sources are available, instruct the user to run `/decompile` first
- Look for `AndroidManifest.xml` — it contains ad-related Activities, Services, meta-data (APPLICATION_ID, sdk keys), and the AD_ID permission

### Phase 2: Detect SDKs, Formats, and Mediation

Run the ad detection script to identify all ad SDKs, formats, and mediation setup.

**Action**: Execute the detection script.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/scripts/find-ads.sh <sources-dir> --all
```

For targeted searches:
```bash
# Single SDK
bash ${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/scripts/find-ads.sh <sources-dir> --admob
bash ${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/scripts/find-ads.sh <sources-dir> --unity

# Specific aspects
bash ${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/scripts/find-ads.sh <sources-dir> --formats    # cross-SDK format detection
bash ${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/scripts/find-ads.sh <sources-dir> --mediation   # mediation adapter detection
bash ${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/scripts/find-ads.sh <sources-dir> --consent     # consent/privacy frameworks
```

Parse the output to identify:
- Which ad SDKs are present
- Which ad formats are used (banner, interstitial, rewarded, native, app-open)
- Whether mediation is set up and which SDK is the mediator
- Consent framework presence

For each detected SDK, read the surrounding code to extract:

1. **Initialization**: Where and how is the SDK initialized? Extract app ID/SDK key
2. **Ad formats**: Which formats are implemented? Extract ad unit/placement IDs
3. **Mediation**: Is this SDK a mediator or a mediated network? Which adapters are present?
   - See `${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/references/mediation-patterns.md`
4. **Ad format details**: For each format, understand the load/show lifecycle
   - See `${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/references/ad-format-patterns.md`
5. **Consent**: Does the app implement UMP, TCF, or SDK-specific consent?

### Phase 2b: Identify Active Entry Points

Distinguish which ad SDKs the app calls directly vs which are only present as passive mediation dependencies.

**Action**: Run the entry point detection.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/scripts/find-ads.sh <sources-dir> --entrypoints
```

This searches for ad SDK init/load/show calls **only in app code**, excluding known library packages (`com/google`, `com/unity3d`, `com/ironsource`, etc.). The results reveal which SDKs the app actively uses.

**Analysis**:

1. Compare the entry point results with the full SDK detection from Phase 2
2. For each detected SDK, classify it as:
   - **Active**: the app code calls its init/load/show methods directly
   - **Passive**: its code is present only inside library packages (mediation adapters)
3. Determine the ad architecture:
   - **Single mediator**: the app calls only 1 ad SDK (e.g., AdMob `MobileAds.initialize()`), all others are passive adapter dependencies
   - **Multiple direct**: the app calls 2+ ad SDKs directly (manual ad network brokerage)
   - **Hybrid**: the app calls a mediator for some formats and additional SDKs directly for others

See `${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/references/mediation-patterns.md` — "Active vs Passive SDKs" section for detailed patterns.

### Phase 3: Produce Report

Generate a structured ad analysis report.

**Report format:**

```markdown
# Ad Analysis Report — <app name>

## Summary

| Ad Network | Role | Formats | Ad Unit IDs | Consent |
|---|---|---|---|---|
| AdMob | Mediator | Banner, Interstitial, Rewarded | ca-app-pub-XXX/YYY, ... | UMP ✓ |
| Unity Ads | Mediated | Interstitial, Rewarded | (via mediation) | — |
| IronSource | Mediated | Rewarded | (via mediation) | — |

## Ad Architecture

- **Type**: Single mediator / Multiple direct / Hybrid
- **Active entry points** (called from app code):
  - `MobileAds.initialize()` — `com/example/app/AdManager.java:28`
  - `InterstitialAd.load()` — `com/example/app/GameActivity.java:112`
- **Passive SDKs** (present only as mediation adapter dependencies):
  - Unity Ads, IronSource, AppLovin, Meta AN — invoked only via `com.google.ads.mediation.*` adapters

```
App code ──→ AdMob (mediator)
               ├──→ Google Ads (direct)
               ├──→ UnityAdapter ──→ Unity Ads SDK  [passive]
               ├──→ IronSourceAdapter ──→ IS SDK    [passive]
               └──→ AppLovinAdapter ──→ AL SDK      [passive]
```

## Mediation Setup

- **Primary mediator**: AdMob
- **Strategy**: Hybrid (bidding + waterfall)
- **Mediated networks**: Unity Ads, IronSource, AppLovin, Meta AN
- **Adapter classes found**: list

## Ad Formats by Placement

### Banner
- **SDK**: AdMob (direct)
- **Size**: BANNER (320×50)
- **Ad unit**: `ca-app-pub-XXXXX/YYYYY`
- **Location**: `MainActivity.java:45` — bottom of screen
- **Auto-refresh**: yes

### Interstitial
- **SDK**: AdMob (mediated to Unity, IronSource)
- **Ad unit**: `ca-app-pub-XXXXX/ZZZZZ`
- **Load location**: `GameActivity.java:112`
- **Show trigger**: level complete (`onLevelComplete()`)

### Rewarded
- **SDK**: AdMob (mediated)
- **Ad unit**: `ca-app-pub-XXXXX/WWWWW`
- **Reward**: 50 coins (`onUserEarnedReward`)
- **Show trigger**: "Watch ad for coins" button

## Ad Unit / Placement IDs

| ID | Format | SDK | Location |
|---|---|---|---|
| `ca-app-pub-XXXXX/YYYYY` | Banner | AdMob | MainActivity.java:45 |
| `ca-app-pub-XXXXX/ZZZZZ` | Interstitial | AdMob | GameActivity.java:112 |

## Privacy & Consent

- **UMP / Funding Choices**: ✓ implemented in `ConsentActivity.java`
- **TCF v2**: ✓ (IABTCF_ keys in SharedPreferences)
- **COPPA**: tagForChildDirectedTreatment = false
- **AD_ID permission**: declared in manifest
- **Per-network consent**: setHasUserConsent called for [list]
```

## References

- `${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/references/ad-sdk-catalog.md` — Package names, classes, manifest markers for detection
- `${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/references/mediation-patterns.md` — Mediation layers, waterfall vs bidding, adapter identification
- `${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/references/ad-format-patterns.md` — Banner, interstitial, rewarded, native, app-open patterns
