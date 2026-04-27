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

If the input is an XAPK, inform the user that it's a split APK bundle. Let them know that in Phase 5 (Rebuild) they will be asked whether to produce a **merged single APK** (easier to install) or keep the **XAPK bundle** (preserves all splits).

### Phase 3: Identify Targets

Target identification has four sub-phases. The goal is to combine deterministic registry matching with heuristic discovery for maximum coverage.

**Depth levels** control how aggressively SDKs are neutralized:
- **Depth 1** (default, safest): Only SDK entry points (init, start). Disables SDK initialization.
- **Depth 2**: Entry points + ad operations (load, show, cache). Safety net if init stub is bypassed.
- **Depth 3** (most aggressive): All above + deep patterns (bulk-stub internal packages). Version-dependent.

Ask the user which depth level to use. Default to depth 1 unless they request more.

#### Phase 3a — Registry Scan (Known SDKs)

Run `registry-scan.py` to match the decoded APK against the SDK registry (29 SDKs, 123 entry points, 156 ad operations, 30 deep patterns).

**Action**: Run registry scan.

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/registry-scan.py "<decoded-dir>" \
  --registry "${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/registry/" \
  --depth 1 --category all \
  --output-dir "<decoded-dir>"
```

Parse stdout for:
- `MATCHED:<sdk_id>:<display_name>:<category>:<n_targets>` — matched SDK with target count
- `UNKNOWN_PACKAGE:<package>:<class_count>` — unknown packages (candidates for Phase 3b)
- `REGISTRY_TARGETS:<path>` — generated targets file for neutralize.sh
- `REGISTRY_MANIFEST:<path>` — generated manifest components file

Present matched SDKs as a table:

| SDK | Category | Depth | Targets | Manifest Components |
|---|---|---|---|---|
| Google AdMob | ads | 1 | 2 entry points | 3 components |
| Firebase Analytics | analytics | 1 | 8 entry points | 7 components |
| AppsFlyer | attribution | 1 | 19 entry points | 3 components |
| ... | | | | |

If the user requests **depth 2 or 3**, re-run registry-scan.py with the higher depth level.

**Fallback**: If Python 3 is not available, fall back to the builtin catalog:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh <decoded-dir> --all --dry-run
```

#### Phase 3b — Unknown SDK Discovery

Activate this sub-phase when:
- `registry-scan.py` reported `UNKNOWN_PACKAGE:` candidates
- The user asks to discover SDKs beyond the registry
- Few matches in Phase 3a but the user expects more

The registry scan automatically filters unknowns:
- Excludes obfuscated packages (single-letter names like `a/`, `b/c/`)
- Excludes known utility libraries (okhttp, retrofit, gson, protobuf, kotlinx, androidx, etc.)
- Excludes the app's own package (from AndroidManifest)
- Only includes packages with 10+ classes and 3+ name segments

**CRITICAL — Use Claude Code built-in tools, NOT bash commands.** Glob, Grep, and Read are auto-approved.

**Discovery workflow** for each unknown package candidate:

1. **List main classes** — use Glob:
   ```
   Glob: **/smali*/com/vendor/sdk/**/*.smali
   ```

2. **Search for SDK patterns** — use Grep:
   ```
   Grep: pattern="\.method.*(init|initialize|start|load|show)" path=<smali-dir>/com/vendor/sdk/
   Grep: pattern="const-string.*http" path=<smali-dir>/com/vendor/sdk/
   ```

3. **Check manifest** for components (activities, services, providers, receivers) with that package.

4. **Classify**: "probable SDK ads", "probable SDK tracker", "utility library", "app code"

Present results as a table:

| Package | Classes | SDK Patterns | Classification | Suggested Action |
|---|---|---|---|---|
| `com/vendor/analytics` | 45 | init, logEvent, URL endpoints | Tracker | Deep analysis |
| `com/vendor/mediator` | 120 | no direct init | Mediator/wrapper | Check SDK refs |
| `org/example/util` | 8 | no SDK patterns | Utility library | Ignore |

#### Phase 3c — Deep Analysis (opt-in, explicit confirmation required)

**IMPORTANT**: Before proceeding, present the candidates and ask:
> "I identified N SDK candidates for deep analysis. This involves web search and smali reverse engineering. Which ones should I analyze? (list numbers or 'all')"

**Only after user confirmation**, for each selected SDK:

1. **Web search**: Search for the package name to identify the SDK:
   - `"com.vendor.sdk" android SDK`
   - `site:maven.org "com.vendor.sdk"`
   - `"com.vendor.sdk" gradle dependency`

2. **Read main smali classes**: Identify the public API (init, config, entry points).

3. **Propose to the user**: "This appears to be **X SDK** version Y, used for Z. Entry points found: `init()`, `start()`, `logEvent()`. Neutralize it?"

4. **If confirmed**, generate entry for targets file:
   ```
   # [X SDK] discovered via deep analysis
   com/vendor/sdk/MainClass:init
   com/vendor/sdk/MainClass:start
   ```

5. **Optionally**, propose a draft registry JSON entry for future inclusion.

#### Phase 3d — Compile & Confirm

Merge all target sources:
- **Registry targets** from Phase 3a (`registry-targets.txt`)
- **Custom discovery** from Phase 3b/3c (append to `custom-targets.txt`)
- **User-provided** `--targets-file` if any

Present the complete summary:

| SDK | Category | Source | Depth | Targets | Manifest Components |
|---|---|---|---|---|---|
| Google AdMob | ads | Registry | 1 | 2 methods | 3 components |
| Firebase Analytics | analytics | Registry | 1 | 8 methods | 7 components |
| guru/ads/fusion | ads | Discovery | - | 3 methods | 0 components |
| ... | | | | | |

**Ads vs Trackers distinction**: Always present ads and trackers separately — they have different implications (revenue impact vs privacy).

Ask for final confirmation:
- Which categories/SDKs to neutralize
- `--ads` — only ad SDKs
- `--trackers` — only tracker/analytics SDKs
- `--all` — both (default)
- Optionally exclude specific SDKs

### Phase 4: Neutralize

Run the neutralization script. **Always run a dry-run first** to preview changes.

#### Registry-driven mode (preferred, requires Python 3.6+)

Uses `registry-targets.txt` and `registry-manifest.txt` generated by Phase 3a. The `--no-builtin-targets` flag disables hardcoded targets to rely entirely on the registry.

```bash
# Preview (dry-run)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh <decoded-dir> \
  --no-builtin-targets --dry-run \
  --targets-file <decoded-dir>/registry-targets.txt \
  --manifest-components-file <decoded-dir>/registry-manifest.txt

# Apply
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh <decoded-dir> \
  --no-builtin-targets \
  --targets-file <decoded-dir>/registry-targets.txt \
  --manifest-components-file <decoded-dir>/registry-manifest.txt
```

**If Phase 3b/3c produced custom targets**, add a second `--targets-file` or append to the registry file:

```bash
# Append custom targets to registry targets
cat <decoded-dir>/custom-targets.txt >> <decoded-dir>/registry-targets.txt
```

#### Fallback mode (no Python)

If Python 3 is not available, use the builtin hardcoded targets:

```bash
# Preview
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh <decoded-dir> --all --dry-run

# Apply
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh <decoded-dir> --all
```

Parse the output for `PATCHED:` and `MANIFEST_DISABLED:` lines to build the report.

#### Options reference

- `--no-builtin-targets` — skip hardcoded target functions, rely on `--targets-file` + `--manifest-components-file`
- `--targets-file <file>` — load targets from file (registry-scan.py output or custom)
- `--manifest-components-file <file>` — load manifest components from file (registry-scan.py output)
- `--ads` / `--trackers` / `--all` — target selection (for builtin mode)
- `--dry-run` — preview only
- `--no-backup` — skip `.smali.bak` creation
- `--no-manifest` — skip manifest patching
- `--package <path>` — neutralize all methods in a package recursively
- `--replay` — replay patches from a previous `neutralize-manifest.json` (useful after re-decode)
- `--no-save-manifest` — skip saving `neutralize-manifest.json`

After a successful (non-dry-run) neutralization, a `neutralize-manifest.json` is saved in the decoded directory. This file records all patched methods and disabled components. If the APK is re-decoded, use `--replay` to reapply the same patches automatically.

### Phase 5: Rebuild & Sign

Rebuild the decoded directory back into a signed APK (or XAPK if the original was an XAPK).

#### Phase 5a — XAPK Output Format Choice (XAPK input only)

**If the input was an XAPK**, you **MUST ask the user** how to rebuild:

> How would you like to rebuild the neutralized app?
>
> 1. **Merged single APK** (recommended for sideloading) — merges split contents into one APK, installable with standard `adb install`. May be missing some locale/density resources.
> 2. **XAPK bundle** (preserves original structure) — requires `adb install-multiple` to install. All splits preserved exactly.

**If the user chooses option 1 (merged single APK):**

Run `merge-splits.sh` to merge split contents into the decoded base APK directory:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/merge-splits.sh <decoded-dir>
```

Options:
- `--abi <abi>` — merge only a specific ABI (e.g., `arm64-v8a`)
- `--all-abis` — merge all ABIs (larger but universal APK)
- `--skip-resources` — skip resource split merge (locale/density)
- Default (no flags): picks the most common ABI (`arm64-v8a` > `armeabi-v7a` > `x86_64` > `x86`)

Parse output for `MERGE_ABI:`, `MERGE_RESOURCES:`, `SKIPPED_RESOURCES:`, `FEATURE_SPLIT_WARNING:`, `MANIFEST_CLEANED:`, and `MERGE_COMPLETE:` lines.

**Important merge limitations to communicate to the user:**
- Resource splits (locale, density) are merged best-effort — compiled `resources.arsc` cannot be fused without `aapt2`. The merged APK uses default resources from the base APK.
- Feature module splits (containing DEX code) **cannot** be merged — the script warns about these.
- Native library merge changes `android:extractNativeLibs` to `true`, which increases installed size.

After merge, the rebuild script auto-detects the `.merged` marker and produces a single `.apk`.

**If the user chooses option 2 (XAPK bundle):** skip `merge-splits.sh` and proceed directly to rebuild — the script will auto-reassemble the XAPK.

#### Phase 5b — Signing Preference

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

#### Phase 5c — Run Rebuild

**Action**: Run the rebuild script with the chosen signing option.

```bash
# Single merged APK (after merge-splits.sh, auto-detected via .merged marker)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/rebuild-apk.sh <decoded-dir> --auto-keystore

# Or explicitly force single APK output
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/rebuild-apk.sh <decoded-dir> --auto-keystore --single-apk

# XAPK bundle (default when .xapk-origin/ exists and no .merged marker)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/rebuild-apk.sh <decoded-dir> --auto-keystore
```

Options:
- `-o <output>` — custom output path
- `--single-apk` — force single APK output (auto-enabled when `.merged` marker exists)
- `--auto-keystore` — auto-detect best keystore (recommended)
- `--debug-key` — always generate new debug keystore
- `--keystore <file>` — use a custom keystore
- `--no-sign` — output unsigned APK
- `--zipalign` / `--no-zipalign` — control zipalign step

For XAPK input without merge, the rebuild is automatic: the script detects `.xapk-origin/`, re-signs all split APKs with the same keystore, and produces a `.xapk` output. Parse the output for `KEYSTORE_USED:`, `KEYSTORE_SOURCE:`, `SPLIT_SIGNED:`, and `XAPK_ASSEMBLED:` lines.

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

## Split Merge Details (if applicable)

If the original input was an XAPK and the user chose merged single APK output, include this section:

| Merge Step | Result |
|---|---|
| ABI splits merged | arm64-v8a (3 native libraries) |
| Resource splits | 2 merged (best-effort), 1 skipped |
| Feature splits | 0 (or: 1 warning — could not merge) |
| Manifest cleanup | isSplitRequired, extractNativeLibs→true, com.android.vending.splits.required |

**Merge limitations:**
- Locale/density resources use defaults from the base APK (compiled `resources.arsc` from splits cannot be fused)
- `android:extractNativeLibs` was set to `true` — native libs are extracted on install (uses more disk space)
- Feature module splits (if any) were NOT merged and their functionality may be missing

## Output

- Sanitized APK/XAPK: `<path>`
- Output format: APK (single) / APK (merged from XAPK) / XAPK (split bundle)
- Signed with: auto-detected debug key / generated debug key / custom keystore
- Keystore used: `<path>` (source: `KEYSTORE_SOURCE:` value)
- Install via: `adb install <path>` (APK / merged APK) or `adb install-multiple <base.apk> <split1.apk> ...` (XAPK)
- For XAPK: unzip the XAPK and run `adb install-multiple *.apk`
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
