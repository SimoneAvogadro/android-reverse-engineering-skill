---
description: Detect and analyze analytics/tracker SDKs in decompiled Android apps. Identifies Firebase Analytics, Adjust, AppsFlyer, Mixpanel, Amplitude, Segment, Braze, CleverTap, Flurry, and other telemetry SDKs. Extracts initialization patterns, event logging, user identification, consent mechanisms, and data exfiltration endpoints.
trigger: find trackers|tracker analysis|analytics SDK|detect trackers|privacy analysis trackers|telemetry SDK|Firebase Analytics|Adjust SDK|AppsFlyer|Mixpanel|Amplitude|Segment|Braze|CleverTap|Flurry|what trackers|which analytics|tracking SDK
---

# Tracker Analysis

Detect and analyze analytics/tracker SDKs embedded in decompiled Android applications. Produces a structured privacy report covering SDK identification, initialization, event logging, user identification, consent handling, and known data exfiltration endpoints.

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
- Look for `AndroidManifest.xml` in the parent or sibling `resources/` directory — it contains tracker-relevant metadata

### Phase 2: Broad Detection Sweep

Run the tracker detection script to identify all tracker SDKs present in the codebase.

**Action**: Execute the detection script.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/scripts/find-trackers.sh <sources-dir> --all
```

For targeted searches on a specific SDK:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/scripts/find-trackers.sh <sources-dir> --firebase
bash ${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/scripts/find-trackers.sh <sources-dir> --adjust
bash ${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/scripts/find-trackers.sh <sources-dir> --mixpanel
```

Parse the output to identify which SDKs are present. Empty sections mean that SDK is not used.

### Phase 3: Deep Semantic Analysis

For each detected SDK, perform a thorough analysis following the patterns in the reference documents.

**For each SDK found, trace these in order:**

1. **Initialization**: How is the SDK initialized? Where is the API key/app ID? Is it hardcoded or loaded from config?
   - Read the initialization code and extract credentials
   - Check `AndroidManifest.xml` for meta-data entries
   - See `${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/references/tracker-init-patterns.md`

2. **Event Logging**: What events are tracked? Are they standard SDK events or custom?
   - List all event names (both string literals and constants)
   - Note what data is attached to each event (parameters, properties)
   - Look for revenue/purchase tracking

3. **User Identification**: How are users identified across sessions?
   - Find `setUserId`, `identify`, `onUserLogin` calls
   - Check what user properties are set (email, name, custom attributes)
   - Look for cross-device identification

4. **Consent & Opt-out**: Does the app implement consent management for this SDK?
   - Find opt-out/opt-in calls
   - Check for GDPR compliance (forget-me, data deletion)
   - Check for consent gating (is analytics enabled only after consent?)

5. **Data Exfiltration**: Where does the data go?
   - Identify endpoints from `${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/references/data-exfiltration-patterns.md`
   - Check for custom endpoints or proxy/relay configurations
   - Look for batch upload patterns

### Phase 4: Produce Report

Generate a structured tracker analysis report.

**Report format:**

```markdown
# Tracker Analysis Report — <app name>

## Summary

| SDK | Version hint | Init location | Events tracked | User ID | Consent |
|-----|-------------|---------------|----------------|---------|---------|
| Firebase Analytics | (from gradle/manifest) | Application.onCreate | 12 custom + standard | setUserId | setConsent ✓ |
| Adjust | — | MainActivity | 3 events | — | gdprForgetMe ✓ |
| ... | | | | | |

## Detailed Analysis

### Firebase Analytics

- **Initialization**: `FirebaseAnalytics.getInstance()` in `MyApp.java:34`
- **API Key / App ID**: `google_app_id` = `1:123456:android:abc` (from strings.xml)
- **Events tracked**:
  - `select_content` (standard) — item_id, item_name
  - `purchase_complete` (custom) — amount, currency, product_id
  - ...
- **User identification**: `setUserId("...")` called in `LoginViewModel.java:78`
- **User properties**: `subscription_tier`, `app_version`
- **Consent**: `setAnalyticsCollectionEnabled(false)` in `ConsentManager.java:22`, toggled based on user preference
- **Endpoints**: `app-measurement.com` (standard, no custom relay)

### [Next SDK...]

## Privacy Summary

- **Total SDKs detected**: N
- **SDKs with consent gating**: list
- **SDKs without consent gating**: list (⚠️)
- **User data shared**: email, user ID, device ID, location, ...
- **Known endpoint domains**: list of all domains data is sent to
```

## References

- `${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/references/tracker-sdk-catalog.md` — Package names, classes, manifest markers for detection
- `${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/references/tracker-init-patterns.md` — Init calls, event logging, user ID, consent per SDK
- `${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/references/data-exfiltration-patterns.md` — Endpoints, proxy patterns, batch upload
