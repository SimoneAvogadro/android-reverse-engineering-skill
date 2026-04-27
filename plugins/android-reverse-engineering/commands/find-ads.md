---
allowed-tools: Bash, Read, Glob, Grep, Write
description: Detect and analyze advertising SDKs in decompiled Android sources
user-invocable: true
argument-hint: <path to decompiled sources directory>
argument: path to decompiled sources directory (optional)
---

# /find-ads

Detect and analyze advertising SDKs in a decompiled Android app.

## Instructions

You are starting the ad analysis workflow. Follow these steps:

### Step 1: Get the source directory

If the user provided a path as an argument, use that. Otherwise, ask the user for the path to the decompiled sources directory.

If no decompiled sources exist yet, tell the user to run `/decompile` first on their APK/XAPK file.

Verify the directory exists and contains `.java` or `.kt` files:

```bash
find "$SOURCE_DIR" -name "*.java" -o -name "*.kt" | head -5
```

### Step 2: Run broad detection

Execute the ad detection script to sweep for all known ad SDKs:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/scripts/find-ads.sh "$SOURCE_DIR" --all
```

Parse the output — non-empty sections indicate a detected SDK or feature.

### Step 3: Analyze detected SDKs and identify active entry points

For each SDK found:

1. **Identify the role** — is it the primary mediator or a mediated network?
2. **Extract ad unit/placement IDs** — find all ID strings
3. **Map ad formats** — which formats (banner, interstitial, rewarded, native, app-open) are implemented?
4. **Trace the load/show lifecycle** — where is each ad loaded and when is it shown?
5. **Check mediation setup** — if mediation is detected, identify all adapters and the waterfall/bidding strategy

**Distinguish active vs passive SDKs** by running entry point detection:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/scripts/find-ads.sh "$SOURCE_DIR" --entrypoints
```

This searches for ad SDK calls **only in app code** (excluding library packages like `com/google`, `com/unity3d`, etc.). Compare these results with the full detection from Step 2:

- SDKs that appear in `--entrypoints` output are **actively called** by the app
- SDKs detected in Step 2 but absent from `--entrypoints` are **passive dependencies** (mediation adapters only)
- Determine the **ad architecture**: Single mediator, Multiple direct, or Hybrid

Use the reference documents in `${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/references/` for SDK-specific patterns.

### Step 3b: Filter false positives

When analyzing the results, distinguish real SDK presence from false positives:

- **HIGH confidence** — SDK-specific classes/imports are present (e.g., `MobileAds.initialize()`, `import com.unity3d.ads.UnityAds`). The SDK is definitely integrated.
- **MEDIUM confidence** — Only generic ad format names matched (e.g., `InterstitialAd`, `BannerView`, `RewardedAd`). These class names may be from the actual SDK or from custom wrappers. Verify by checking the full import path.
- **LOW confidence** — Only generic strings matched (e.g., "banner", "interstitial" in comments or unrelated code). Check the context.

**Quick verification**: For any SDK flagged as detected, check if its package directory actually exists:
```bash
# Example: verify Unity Ads is really present
find "$SOURCE_DIR" -path "*/com/unity3d/ads" -type d
```

Use `--summary` for a quick confidence-scored overview before diving into raw output:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/scripts/find-ads.sh "$SOURCE_DIR" --summary
```

### Step 4: Produce report

Generate a structured report with:
- **Summary table**: ad network, role (mediator/mediated/active/passive), formats, ad unit IDs, consent
- **Ad architecture**: type (Single mediator / Multiple direct / Hybrid), active entry points with file:line, passive SDK list, ASCII diagram
- **Mediation setup**: primary mediator, strategy, mediated networks, adapter classes
- **Ad formats by placement**: for each format — SDK, ad unit, load/show location, trigger
- **Ad unit ID table**: all discovered IDs with format, SDK, and source location
- **Privacy & consent**: UMP, TCF, COPPA, AD_ID permission, per-network consent

Refer to `${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/SKILL.md` for the full report format.

### Step 5: Offer next steps

Tell the user what they can do next:
- **Deep-dive a specific ad network**: "I can trace the full integration for AdMob"
- **Analyze mediation waterfall**: "I can map the exact network priority order"
- **Check trackers**: "Run `/find-trackers` to analyze analytics/tracker SDKs too"
- **Export report**: "I can save this report as a markdown file"
