---
description: Neutralize tracker and ad SDK entry points in Android APKs at the smali bytecode level. Replaces SDK method bodies with stubs (return-void, return null) and disables manifest components. Produces sanitized APKs for enterprise sideloading with telemetry and advertising disabled.
trigger: neutralize SDK|neutralize trackers|neutralize ads|remove trackers|disable telemetry|sanitize APK|enterprise APK|strip trackers|strip ads|kill telemetry|patch SDK
---

# SDK Neutralizer

Neutralize tracker/analytics and advertising SDK entry points in decoded Android APKs. Replaces SDK method bodies with no-op stubs at the smali level and disables manifest components, producing a sanitized APK for enterprise deployment.

## IMPORTANT — Responsible Use Notice

**Before starting any neutralization work, you MUST warn the user about the following.** Present this notice clearly and ask the user to confirm they understand and accept before proceeding.

### Side Effects

Neutralizing SDK entry points can cause **unexpected app behaviour**:

- **Crashes**: stubbed `getInstance()` methods return `null`. Any code that calls methods on the result without null-checking will throw `NullPointerException` and crash.
- **Broken features**: some app features depend on SDK functionality (e.g., rewarded ads gate premium content, analytics events trigger server-side logic, A/B testing controls UI). Neutralizing the SDK breaks these features.
- **Silent data loss**: if the app persists analytics data locally before sending, stubbing the send methods leaves orphan data that may grow indefinitely.
- **Startup failures**: SDKs initialized via `ContentProvider` auto-init may cause errors during app startup if their components are disabled in the manifest.
- **Native library conflicts**: SDKs with native `.so` components may perform integrity checks that detect the modification and crash or silently disable unrelated functionality.

**The dry-run step is mandatory** — always show the user what will be patched and get explicit confirmation before applying changes.

### Legal and EULA Implications

Modifying an APK may violate:

- **The app's Terms of Service or EULA** — most app licenses explicitly prohibit reverse engineering and modification.
- **SDK provider agreements** — ad/analytics SDK terms typically prohibit tampering with their code.
- **Intellectual property laws** — depending on jurisdiction, unauthorized modification may constitute copyright infringement.
- **Distribution restrictions** — redistributing modified APKs (even internally) may require legal authorization.

Legitimate use cases exist (enterprise privacy compliance, authorized security testing, interoperability under EU Directive 2009/24/EC, GDPR data minimisation), but the user **must verify they have proper authorization** for their specific situation.

**Always remind the user**: "Make sure you have the right to modify this application and that your use complies with applicable laws, the app's EULA, and your organization's policies."

## Prerequisites

This skill requires an APK file. It will decode the APK with apktool, neutralize SDK methods in the smali code, and rebuild a signed APK.

Required tools: `java 17+`, `apktool`, `apksigner` or `jarsigner`

## Workflow

### Phase 0: Responsible Use Warning

**Before any technical step**, present the user with the side effects and legal notice above. Ask the user to explicitly confirm:

1. They have authorization to modify this APK (e.g., they own the app, have enterprise authorization, or are doing authorized security research).
2. They understand that the modified APK may crash, lose features, or behave unexpectedly.
3. They understand that the APK signature will be invalidated and Play Integrity will fail.

**Do not proceed if the user does not confirm.** This is not optional.

### Phase 1: Verify Dependencies

Check that all required tools are installed.

**Action**: Run the dependency check.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/check-neutralize-deps.sh
```

If any `INSTALL_REQUIRED:` lines appear, install the missing dependencies:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/install-dep.sh <dep>
```

### Phase 2: Decode APK

Decode the APK (or XAPK) into smali and resources using decode-apk.sh. This script handles both `.apk` and `.xapk` files — for XAPKs it automatically extracts the base APK, skipping split/config APKs.

**Action**: Run the decode script.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/decode-apk.sh <apk-or-xapk-file> -o <decoded-dir>
```

The script verifies the output contains `smali/` and `AndroidManifest.xml` and outputs `DECODED_DIR:<path>`.

### Phase 3: Identify Targets

Run the tracker and ad detection scripts on the decoded smali to identify which SDKs are present and which entry points the app uses.

**Action**: Run entry point detection.

```bash
# Detect ad SDK entry points called from app code
bash ${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/scripts/find-ads.sh <decoded-dir> --entrypoints

# Detect tracker SDK entry points called from app code
bash ${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/scripts/find-trackers.sh <decoded-dir> --entrypoints
```

Present the detected SDKs and entry points to the user. Ask which categories to neutralize:
- `--ads` — only ad SDKs
- `--trackers` — only tracker/analytics SDKs
- `--all` — both (default)

### Phase 4: Neutralize

Run the neutralization script. **Always run a dry-run first** to preview changes.

**Action**: Dry-run, then apply.

```bash
# Preview changes (no files modified)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh <decoded-dir> --all --dry-run

# Apply changes (with backups)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh <decoded-dir> --all
```

Parse the output for `PATCHED:` and `MANIFEST_DISABLED:` lines to build the report.

Options:
- `--ads` / `--trackers` / `--all` — target selection
- `--dry-run` — preview only
- `--no-backup` — skip `.smali.bak` creation
- `--no-manifest` — skip manifest patching
- `--targets-file <file>` — additional custom targets
- `--replay` — replay patches from a previous `neutralize-manifest.json` (useful after re-decode)
- `--no-save-manifest` — skip saving `neutralize-manifest.json`

After a successful (non-dry-run) neutralization, a `neutralize-manifest.json` is saved in the decoded directory. This file records all patched methods and disabled components. If the APK is re-decoded, use `--replay` to reapply the same patches automatically.

### Phase 5: Rebuild & Sign

Rebuild the decoded directory back into a signed APK.

**Action**: Run the rebuild script.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/rebuild-apk.sh <decoded-dir> --debug-key
```

Options:
- `-o <output.apk>` — custom output path
- `--debug-key` — auto-generate debug keystore (default)
- `--keystore <file>` — use a custom keystore
- `--no-sign` — output unsigned APK
- `--zipalign` / `--no-zipalign` — control zipalign step

### Phase 6: Verify & Report

Generate a structured neutralization report and suggest next steps.

**Report format:**

```markdown
# Neutralization Report — <app name>

## Summary

| Category | SDKs Targeted | Methods Patched | Manifest Components Disabled |
|---|---|---|---|
| Ad SDKs | AdMob, Unity, IronSource | 12 | 5 |
| Tracker SDKs | Firebase, Adjust, AppsFlyer | 8 | 3 |
| **Total** | **6** | **20** | **8** |

## Patched Methods

| SDK | Method | File | Stub Type |
|---|---|---|---|
| AdMob | initialize | smali/com/google/.../MobileAds.smali | return-void |
| Firebase | logEvent | smali/com/google/.../FirebaseAnalytics.smali | return-void |
| Firebase | getInstance | smali/com/google/.../FirebaseAnalytics.smali | const/4+return-object |
| ... | | | |

## Disabled Manifest Components

| Component | Type | SDK |
|---|---|---|
| com.google.android.gms.ads.AdActivity | activity | AdMob |
| com.google.android.gms.measurement.AppMeasurementService | service | Firebase |
| ... | | |

## Warnings

- Play Integrity / SafetyNet will FAIL (expected for enterprise sideloading)
- Stubbed getInstance() methods return null — may cause NullPointerException in app code
- Features gated behind ad views (e.g., rewarded content) will stop working
- [Any SDK-specific warnings, e.g., native .so integrity checks detected]
- [Obfuscated classes that could not be matched]

## Side Effects & Legal Notice

This APK has been modified at the bytecode level. The original signature is invalidated.

**Side effects**: The app may crash, lose features, or behave unexpectedly due to
neutralized SDK methods. Test thoroughly before deploying.

**Legal**: Ensure you have proper authorization to modify and distribute this application.
Modifying APKs may violate the app's EULA, SDK provider agreements, or intellectual
property laws. This tool is intended for authorized enterprise use, security research,
and privacy compliance only.

## Output

- Sanitized APK: `<path>`
- Signed with: debug key / custom keystore
- Install via: `adb install <path>`
```

**Next steps to suggest:**
- Re-run `find-ads.sh --entrypoints` and `find-trackers.sh --entrypoints` on the rebuilt APK to verify neutralization
- **Test the APK thoroughly** on a device/emulator — watch for crashes, broken features, and startup errors
- Check for runtime crashes caused by null returns from stubbed `getInstance()` methods
- Use `--targets-file` to add custom neutralization targets for obfuscated code
- Review the legal implications with your organization's legal/compliance team before distributing

## References

- `${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/references/neutralization-guide.md` — Approach overview, stub types, pitfalls, legal disclaimer
- `${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/references/smali-patterns.md` — Complete smali stub catalog per SDK
