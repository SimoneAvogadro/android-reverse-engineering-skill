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

If any `INSTALL_REQUIRED:` lines appear, ask the user to install all dependencies at once:

```bash
# Install all neutralizer deps (java, apktool, apksigner, zip) in one command
bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/install-dep.sh neutralize-all
```

If the script exits with code 2 (sudo needed but no TTY), tell the user to run in their terminal:

```
sudo bash <plugin-root>/skills/android-reverse-engineering/scripts/install-dep.sh neutralize-all
```

### Phase 2: Decode APK

Decode the APK (or XAPK) into smali and resources using decode-apk.sh. This script handles both `.apk` and `.xapk` files — for XAPKs it automatically extracts and decodes the base APK, while preserving the full XAPK structure (split APKs, manifest, icon) in a `.xapk-origin/` directory inside the decoded output for automatic reassembly during rebuild.

**Action**: Run the decode script.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/decode-apk.sh <apk-or-xapk-file> -o <decoded-dir>
```

The script verifies the output contains `smali/` and `AndroidManifest.xml` and outputs `DECODED_DIR:<path>`.

For XAPK input, the script also outputs `XAPK_ORIGIN:<path>` and creates:
- `.xapk-origin/metadata.json` — XAPK metadata (package, version, split list)
- `.xapk-origin/manifest.json` — original XAPK manifest
- `.xapk-origin/splits/` — all split APKs (config.arm64_v8a.apk, config.en.apk, etc.)

If the input is an XAPK, inform the user that it's a split APK bundle and that all splits will be automatically re-signed during rebuild.

### Phase 3: Identify Targets

Target identification has three sub-phases. The goal is to find all SDK entry points to neutralize while minimizing manual approval prompts.

#### Phase 3a — Built-in Catalog Detection

Use `neutralize.sh --dry-run` to detect known SDK targets. This is more reliable than `find-ads.sh`/`find-trackers.sh` because it searches smali directly (not Java source) and matches the exact patterns that will be patched.

**Action**: Run dry-run detection.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh <decoded-dir> --all --dry-run
```

Parse the output for:
- `DRY_RUN:WOULD_PATCH:` lines — smali methods that would be stubbed
- `DRY_RUN:WOULD_DISABLE:` lines — manifest components that would be disabled

**NOTE**: Do NOT use `find-ads.sh` or `find-trackers.sh` here — those scripts search Java/Kotlin source (`.java`, `.kt`), not smali. The decoded directory from Phase 2 contains only smali bytecode, so those scripts will find nothing.

#### Phase 3b — Custom/Proprietary SDK Discovery (if needed)

Activate this sub-phase when:
- The user mentions a specific SDK not in the built-in catalog (e.g., `guru/ads/fusion`, `com/proprietary/analytics`)
- The dry-run found few or no targets but the user expects more
- The user asks to find "all" trackers/ads, including custom/proprietary ones

**CRITICAL — Use Claude Code built-in tools, NOT bash commands.** Glob, Grep, and Read are auto-approved and require no manual user approval. Using `bash find`, `bash grep`, or `bash head` forces the user to approve each command individually.

**Discovery workflow using built-in tools:**

1. **Find smali files by package pattern** — use Glob:
   ```
   Glob: **/smali*/com/guru/**/*.smali
   Glob: **/smali*/com/proprietary/analytics/**/*.smali
   ```

2. **Find SDK method signatures** — use Grep on the matched files:
   ```
   Grep: pattern="^\.method.*(init|track|log|show|load|send|report|emit)"
   Grep: pattern="^\.method.*getInstance"
   ```

3. **Find SDK invocations from app code** — use Grep on the app's own smali:
   ```
   Grep: pattern="invoke-(static|virtual|direct).*Lcom/guru/ads/"
   Grep: pattern="invoke-(static|virtual|direct).*Lcom/proprietary/analytics/"
   ```

4. **Examine specific files** — use Read to inspect method bodies and confirm they are SDK entry points worth neutralizing.

**Build the custom targets file** with discovered entry points, one per line, in the format:

```
<smali-class-path>:<method-name>
```

For example:
```
smali/com/guru/ads/fusion/FusionAd.smali:initialize
smali/com/guru/ads/fusion/FusionAd.smali:showAd
smali/com/guru/ads/fusion/FusionTracker.smali:trackEvent
```

**Action**: Write the targets file.

```
Write: <decoded-dir>/custom-targets.txt
```

#### Phase 3c — Compile Target List and Confirm

Present a summary table of all targets to the user:

| SDK | Category | Source | Entry Points |
|---|---|---|---|
| AdMob | Ads | Built-in catalog | 5 methods, 2 components |
| Firebase Analytics | Trackers | Built-in catalog | 3 methods, 1 component |
| guru/ads/fusion | Ads | Custom discovery | 3 methods |
| ... | | | |

Ask which categories/SDKs to neutralize:
- `--ads` — only ad SDKs
- `--trackers` — only tracker/analytics SDKs
- `--all` — both (default)
- Optionally exclude specific SDKs

### Phase 4: Neutralize

Run the neutralization script. **Always run a dry-run first** to preview changes.

**Action**: Dry-run, then apply.

```bash
# Preview changes (no files modified)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh <decoded-dir> --all --dry-run

# Apply changes (with backups)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh <decoded-dir> --all
```

**If Phase 3b produced custom targets**, add `--targets-file` to both commands:

```bash
# Preview with custom targets
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh <decoded-dir> --all --dry-run --targets-file <decoded-dir>/custom-targets.txt

# Apply with custom targets
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh <decoded-dir> --all --targets-file <decoded-dir>/custom-targets.txt
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

Rebuild the decoded directory back into a signed APK (or XAPK if the original was an XAPK).

**Before calling rebuild**, you **MUST ask the user** their signing preference:

> How would you like to sign the rebuilt APK?
>
> 1. **Auto-detect** (recommended) — checks for `~/.android/debug.keystore` first, then generates a debug key
> 2. **Custom keystore** — provide path, alias, and password
> 3. **No signing** — output unsigned APK (cannot be installed directly)

Map the user's choice to the corresponding flag:
- Option 1 → `--auto-keystore`
- Option 2 → `--keystore <file> --key-alias <alias> --store-pass <pass> --key-pass <pass>`
- Option 3 → `--no-sign`

**Action**: Run the rebuild script with the chosen signing option.

```bash
# Example with auto-keystore (recommended default)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/rebuild-apk.sh <decoded-dir> --auto-keystore
```

Options:
- `-o <output>` — custom output path
- `--auto-keystore` — auto-detect best keystore (recommended)
- `--debug-key` — always generate new debug keystore
- `--keystore <file>` — use a custom keystore
- `--no-sign` — output unsigned APK
- `--zipalign` / `--no-zipalign` — control zipalign step

For XAPK input, the rebuild is automatic: the script detects `.xapk-origin/`, re-signs all split APKs with the same keystore, and produces a `.xapk` output. Parse the output for `KEYSTORE_USED:`, `KEYSTORE_SOURCE:`, `SPLIT_SIGNED:`, and `XAPK_ASSEMBLED:` lines.

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

- Sanitized APK/XAPK: `<path>`
- Output format: APK (single) / XAPK (split bundle)
- Signed with: auto-detected debug key / generated debug key / custom keystore
- Keystore used: `<path>` (source: `KEYSTORE_SOURCE:` value)
- Install via: `adb install <path>` (APK) or `adb install-multiple <base.apk> <split1.apk> ...` (XAPK)
- For XAPK: can also use SAI (Split APKs Installer) or unzip and `adb install-multiple *.apk`
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
