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

This skill requires an APK file or a split APK bundle (XAPK/APKM/APKS). It will decode the APK with apktool, neutralize SDK methods in the smali code, and rebuild a signed APK. Split bundles are merged into a single APK before decoding, so the result is always one installable APK.

Required tools: `java 17+`, `apktool`, `unzip`, and Android SDK Build-Tools (`apksigner` + `zipalign`; build-tools 35+ for `zipalign -P 16`), plus [APKEditor](https://github.com/REAndroid/APKEditor) for XAPK/APKM/APKS input. zipalign is **required** whenever the APK has stored native libraries with `extractNativeLibs="false"` (the rebuild fails without it). `jarsigner` is only a v1-signature fallback for apps targeting SDK < 30.

**Windows**: `check-neutralize-deps.ps1`, `decode-apk.ps1`, `detect-protection.ps1`, `detect-adwrapper.ps1` and `rebuild-apk.ps1` (PowerShell 5.1+) mirror the bash scripts, with PowerShell-style flags (`-Output`, `-KeepSplits`, `-AutoKeystore`, ...). `neutralize.sh` and `registry-scan.py` still require bash and python3 (WSL or Git Bash) for now. Example:

```
powershell -NoProfile -ExecutionPolicy Bypass -File <plugin-root>\skills\sdk-neutralizer\scripts\decode-apk.ps1 C:\apks\app.xapk -Output C:\work\app-decoded
powershell -NoProfile -ExecutionPolicy Bypass -File <plugin-root>\skills\sdk-neutralizer\scripts\rebuild-apk.ps1 C:\work\app-decoded -AutoKeystore
```

**Exit codes** (all scripts): 0 = success, 1 = error (including unknown options and a misaligned rebuild), 2 = manual action needed (install-dep: sudo, or the Android SDK license not accepted).

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
# Pass the input file: APKEditor is required only for XAPK/APKM/APKS input
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/check-neutralize-deps.sh <apk-or-xapk-file>
```

The output also reports `ZIPALIGN_PAGE_ALIGN:16k|4k|none` (whether zipalign supports `-P 16` for 16 KB-page devices or only `-p`).

If any `INSTALL_REQUIRED:` lines appear, ask the user to install all dependencies at once. `build-tools` downloads Google's Android SDK Build-Tools (pinned 36.0.0, SHA-256 verified; `sdkmanager` is used instead when `ANDROID_HOME`/`ANDROID_SDK_ROOT` has one). It is licensed under the [Android Software Development Kit License Agreement](https://developer.android.com/studio/terms): **show the user that link and get their explicit acceptance before passing `--accept-android-sdk-license`** — never pass it on your own.

```bash
# Install all neutralizer deps (java, apktool, apkeditor, build-tools, zip) in one command
bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/install-dep.sh neutralize-all --accept-android-sdk-license
```

Without the flag, `build-tools` prints the license notice and exits 2. Never run `install-dep.sh` with `sudo`: per-user tools (apktool, APKEditor, build-tools) go to the invoking user's `~/.local`, so it refuses to run under sudo and calls sudo itself only for system packages (Java, zip). If it exits with code 2 because sudo needs a password and there is no TTY, it prints the exact package command under `[MANUAL ACTION REQUIRED]` (e.g. `sudo apt-get update && sudo apt-get install -y openjdk-17-jdk`): ask the user to run that command in their terminal, then re-run `install-dep.sh neutralize-all` as their own user.

### Phase 2: Decode APK

Decode the APK into smali and resources using decode-apk.sh. `.apk` input is decoded directly. Split bundles (`.xapk`, `.apkm`, `.apks`, or a directory of split APKs) are first merged into one APK with APKEditor and then decoded: resources that exist only in config splits (density, locale, ABI) are kept. Decoding the base APK alone would turn every reference to them into `@null` (e.g. AppCompat selector drawables), which crashes at inflation and cannot be repaired after decoding.

**Action**: Run the decode script.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/decode-apk.sh <apk-or-xapk-file> -o <decoded-dir>
```

The script verifies the output contains `smali/` and `AndroidManifest.xml` and outputs `DECODED_DIR:<path>`.

For split bundle input, it also outputs:
- `MERGED_FROM_SPLITS:<decoded-dir>/.merged-from-splits.json` — source file, merged split names, APKEditor version, package and version
- `OBB_WARNING:<name>` — OBB files are never part of the APK; the user must copy them to the device separately

If the input is a split bundle, tell the user its splits were merged into a single APK, installable with plain `adb install`.

**Deprecated**: `--keep-splits` decodes only the base APK and keeps the splits in `.xapk-origin/` so that Phase 5 reassembles an XAPK (outputs `DEPRECATION_WARNING:keep-splits` and `XAPK_ORIGIN:<path>`). Split-only resources become `@null` and the app may crash. Use it only if the user explicitly asks for XAPK output; it will be removed.

### Phase 2b: Protection Check (detection only)

Apps wrapped by an anti-tamper, integrity or licensing protection do not run once rebuilt and re-signed: the protection checks the signing certificate, the Play install or its own encrypted code at startup. Find this out **now**, not after a rebuild and a device test.

`decode-apk.sh` runs the check automatically after a successful decode (its exit code is unchanged). To run it again on a decoded directory:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/detect-protection.sh <decoded-dir>
```

Parse:
- `PROTECTION_DETECTED:<id>:<category>:<high|medium|low>:<evidence,...>` — one line per protection found
- `PROTECTION_SUMMARY:<none|integrity|license|hardener|signature-vm>` — the most severe category

Set expectations with the user **before** Phase 3, according to the summary:
- **`signature-vm`** (Google Play PairIP with `SignatureCheck` / `VMRunner` / `libpairipcore.so`) or **`hardener`** (commercial packer or RASP: DexGuard, Promon, Appdome, Verimatrix, Arxan, SecNeo/Bangcle, Jiagu, Legu, ...): tell the user that a rebuilt, re-signed APK **will not run**. Neutralization can still produce a report of the SDKs and what would be patched, but the rebuilt APK will not be usable. Ask whether to stop, or continue for the report only.
- **`license`** (PairIP license check only, or the LVL library): the rebuilt APK may stop at a "Get this app from Play" screen or refuse to run. Tell the user and ask whether to continue.
- **`integrity`** (Play Integrity / SafetyNet client, low confidence, often bundled by SDKs): the app starts; online features whose backend enforces the verdict may fail. Mention it in the report.
- **`none`**: continue.

**Never try to remove, disable, patch around or otherwise defeat a protection.** This skill only detects it and informs the user. With a `medium` confidence hardener match, say that the match is probable, not certain.

### Phase 2c: In-house Ad-Wrapper Check (detection only)

Some publishers ship their own in-house ad/analytics mediation wrapper: an app-owned layer that drives the third-party network SDKs (AdMob, AppLovin, IronSource, ...) AND can serve direct WebView/MRAID "house" interstitials with **no** third-party SDK involved. Neutralizing every network SDK from the registry does **not** stop that house-ad path. Concrete examples: Rovio's `com.rovio.beacon` (Bad Piggies / Angry Birds), Guru's `guru.ads.fusion` — both now have dedicated registry entries flagged `"in_house_wrapper": true`.

`decode-apk.sh` runs this check automatically after a successful decode (its exit code is unchanged). To run it again:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/detect-adwrapper.sh <decoded-dir>
```

Parse:
- `ADWRAPPER_DETECTED:<package>:<high|medium|low>:<evidence,...>` — one line per candidate wrapper (evidence keys: `adclasses`, `networks`, `webview`, `mraid`, `analytics`, `vendor`, and `registry=<sdk_id>` when a dedicated entry already exists)
- `ADWRAPPER_SUMMARY:<none|candidate>`

If a candidate is found, tell the user this app has an in-house ads wrapper at `<package>` and that the network-SDK neutralization may not fully stop ads. Then:
- If the evidence has `registry=<sdk_id>`, a dedicated entry already exists — make sure it is applied (it is picked up by Phase 3a automatically).
- Otherwise, run the unknown-SDK **discovery workflow** (Phase 3b/3c) on `<package>` and consider adding a dedicated registry entry for it.

The detector excludes known third-party SDKs (from the registry) and common libraries, so a genuine third-party ad SDK is **not** reported as an in-house wrapper. It never modifies anything.

### Phase 3: Identify Targets

Target identification has four sub-phases. The goal is to combine deterministic registry matching with heuristic discovery for maximum coverage.

**Depth levels** control how aggressively SDKs are neutralized:
- **Depth 1** (default, safest): Only SDK entry points (init, start). Disables SDK initialization.
- **Depth 2**: Entry points + ad operations (load, show, cache). Safety net if init stub is bypassed.
- **Depth 3** (most aggressive): All above + deep patterns (bulk-stub internal packages). Version-dependent.

Ask the user which depth level to use. Default to depth 1 unless they request more.

#### Phase 3a — Registry Scan (Known SDKs)

Run `registry-scan.py` to match the decoded APK against the SDK registry (47 SDKs, 369 entry points, 355 ad operations, 31 deep patterns).

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
- Phase 2c (`detect-adwrapper.sh`) reported `ADWRAPPER_DETECTED:` for a package **without** a `registry=` annotation (an in-house wrapper with no dedicated registry entry yet — a prime discovery target)
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
| com/vendor/adwrapper | ads | Discovery | - | 3 methods | 0 components |
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

Rebuild the decoded directory into a single signed APK (split bundles were already merged during Phase 2).

#### Phase 5a — Signing Preference

**Before calling rebuild**, you **MUST ask the user** their signing preference:

> How would you like to sign the rebuilt APK?
>
> 1. **Stable debug key** (recommended) — the user-level neutralizer debug key, created once and always reused, so later builds install over earlier ones
> 2. **Custom keystore** — provide path, alias, and password
> 3. **No signing** — output unsigned APK (cannot be installed directly)

Map the user's choice to the corresponding flag:
- Option 1 → `--auto-keystore`
- Option 2 → `--keystore <file> --key-alias <alias> --store-pass <pass> --key-pass <pass>`
- Option 3 → `--no-sign`

The user-level key lives at `~/.config/android-re/neutralizer-debug.keystore` (`$XDG_CONFIG_HOME` is honoured; `%APPDATA%\android-re\neutralizer-debug.keystore` on Windows). It is created once (race-safe, private permissions) and used by both `--auto-keystore` and the default `--debug-key`, so the certificate never changes between builds. `~/.android/debug.keystore` is never picked automatically: pass it explicitly (`--keystore ~/.android/debug.keystore --key-alias androiddebugkey`) if the user wants it. `--keystore` takes precedence whatever the flag order.

**Upgrading from older builds**: APKs built before this stable key existed were signed with a per-directory key. The first install of a build signed with the stable key over such an APK fails with a signature mismatch: uninstall the old build once (`adb uninstall <package>`).

#### Phase 5b — Run Rebuild

**Action**: Run the rebuild script with the chosen signing option.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/rebuild-apk.sh <decoded-dir> --auto-keystore
```

Options:
- `-o <output>` — custom output path (default: `<decoded-dir>-neutralized.apk`)
- `--auto-keystore` / `--debug-key` (default) — sign with the stable user-level neutralizer debug key
- `--keystore <file>` — use a custom keystore
- `--no-sign` — output unsigned APK
- `--zipalign` / `--no-zipalign` — control zipalign step

The script zipaligns before signing (`-P 16` when the zipalign supports 16 KB pages, otherwise `-p`), so stored native libraries are page-aligned. If the APK has stored `.so` files and `extractNativeLibs="false"` (common in APKEditor-merged APKs) and no zipalign is found, it **fails** before signing. After signing it checks every stored entry (4-byte alignment; `.so` page alignment) and **fails** (exit 1) on a misaligned entry, leaving the APK as `<output>.misaligned` instead of `<output>`. apksigner is taken from Android SDK build-tools first; with only `jarsigner` (v1 signatures) the rebuild refuses apps targeting SDK 30+.

Parse the output for:
- `KEYSTORE_USED:`, `KEYSTORE_SOURCE:` (`debug-user` = existing stable key, `debug-generated` = stable key created now, `custom`), `KEYSTORE_ALIAS:`
- `SIGN_OK:`, `VERIFY_OK:`
- `ALIGN_OK:<n>:16k|4k|none|n/a` — no fatal misalignment; `n` stored `.so` files and their page alignment (`none` only comes with the warning below)
- `ALIGN_WARNING:so-not-page-aligned` — stored `.so` files are not page-aligned; tolerated only because `extractNativeLibs` is not `"false"` (the installer extracts them). Happens only with `--no-zipalign` or jarsigner without zipalign
- `ALIGN_WARNING:not-16k` — the `.so` files are only 4 KB aligned: devices with 16 KB pages (Android 15+) refuse the APK; tell the user to install build-tools 35+
- `ALIGN_FAIL:<entry>` — one line per misaligned entry (max 20); the rebuild failed
- `ABI_WARNING:32bit-only:<abis>` — the APK has only 32-bit native code: warn the user that many recent phones (e.g. Galaxy S25, Pixel 7 and later) are 64-bit only and will refuse it, and suggest an arm64-v8a build of the app

**Deprecated XAPK output**: a directory decoded with `--keep-splits` is reassembled into an XAPK with all splits re-signed (outputs `DEPRECATION_WARNING:xapk-output`, `SPLIT_SIGNED:`, `XAPK_ASSEMBLED:`). It needs `apksigner` and `zip`, installs with `adb install-multiple`, and will be removed.

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
- [Protection check result from Phase 2b: `PROTECTION_SUMMARY` and each `PROTECTION_DETECTED` protection, e.g. "Protected by Google Play PairIP (signature check + VM): the rebuilt APK will not run"]
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

If the input was a split bundle, include this section (from `.merged-from-splits.json` and the rebuild output):

| Item | Value |
|---|---|
| Source bundle | app.xapk |
| Splits merged (APKEditor 1.4.9) | base.apk, config.arm64_v8a.apk, config.xhdpi.apk |
| Native ABIs / alignment | arm64-v8a / `ALIGN_OK:13:16k` |
| OBB files (not in the APK) | none |

## Output

- Sanitized APK: `<path>`
- Output format: APK / APK (merged from a split bundle with APKEditor) / XAPK (deprecated `--keep-splits`)
- Signed with: Android SDK debug key / user-level neutralizer debug key / custom keystore
- Keystore used: `<path>` (source: `KEYSTORE_SOURCE:` value)
- Install via: `adb install <path>` (deprecated XAPK: unzip it and run `adb install-multiple *.apk`)
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
