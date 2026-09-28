---
allowed-tools: Bash, Read, Glob, Grep, Write, Edit
description: Neutralize tracker/ad SDK entry points in an Android APK for enterprise deployment
user-invocable: true
argument-hint: <path to APK file>
argument: path to APK file (optional)
---

# /neutralize

Neutralize tracker and ad SDK entry points in an Android APK, producing a sanitized APK for enterprise sideloading.

## Instructions

You are starting the SDK neutralization workflow. Follow these steps:

### Step 1: Responsible use warning

**This step is mandatory and must not be skipped.**

Before doing anything else, warn the user clearly about the implications of SDK neutralization:

> **Before we proceed, please be aware of the following:**
>
> **Side effects** — Neutralizing SDK entry points can cause the app to crash (NullPointerException from stubbed methods), lose features (rewarded ads, A/B testing, analytics-gated content), or behave unexpectedly at startup. The original APK signature will be invalidated — Play Integrity will fail.
>
> **Legal/EULA implications** — Modifying an APK may violate the app's Terms of Service, SDK provider agreements, and intellectual property laws depending on your jurisdiction. Legitimate uses include authorized enterprise deployment, security research, and privacy compliance (EU Directive 2009/24/EC, GDPR data minimisation), but you are responsible for verifying you have proper authorization.
>
> **Please confirm**: Do you have authorization to modify this application, and do you understand the potential side effects?

**Wait for the user to explicitly confirm before proceeding.** If the user declines or expresses doubt, do not continue — suggest they consult their legal/compliance team first.

### Step 2: Get the APK/XAPK file

If the user provided a path as an argument, use that. Otherwise, ask the user for the path to the APK or split bundle (XAPK/APKM/APKS).

Verify the file exists and is an APK or a split bundle:

```bash
file "$APK_PATH"
```

### Step 3: Check dependencies

Run the dependency check to ensure all required tools are installed:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/check-neutralize-deps.sh "$APK_PATH"
```

(Passing the file makes APKEditor required for XAPK/APKM/APKS input.)

On Windows without bash, `check-neutralize-deps.ps1`, `decode-apk.ps1`, `detect-protection.ps1` and `rebuild-apk.ps1` (PowerShell 5.1) are available; `neutralize.sh` and `registry-scan.py` still require bash + python3 (WSL or Git Bash) for now.

If any `INSTALL_REQUIRED:` lines appear, install all dependencies at once (java, apktool, apkeditor, build-tools, zip). `build-tools` is Google's Android SDK Build-Tools (zipalign + apksigner), licensed under the Android Software Development Kit License Agreement (https://developer.android.com/studio/terms): show the user this link and ask for explicit acceptance **before** passing `--accept-android-sdk-license`. Never accept it on the user's behalf:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/install-dep.sh neutralize-all --accept-android-sdk-license
```

Never run `install-dep.sh` itself with `sudo`: it installs per-user tools (apktool, APKEditor, build-tools) into `~/.local` of the invoking user and refuses to run under sudo. It calls sudo on its own only for system packages (Java, zip). If it exits with code 2 because sudo needs a password and there is no TTY (common inside Claude Code), it prints the exact `[MANUAL ACTION REQUIRED]` command (e.g. `sudo apt-get update && sudo apt-get install -y openjdk-17-jdk`): ask the user to run **that** command in their terminal, then re-run `install-dep.sh neutralize-all` without sudo.

### Step 4: Decode APK/XAPK

Decode the APK or split bundle using decode-apk.sh. A split bundle (`.xapk`, `.apkm`, `.apks`) is first merged into one APK with APKEditor, then decoded, so resources that live only in the splits are kept (decoding the base alone turns them into `@null`):

```bash
# Strip the .apk/.xapk/.apkm/.apks extension for the output dir name
DECODED_DIR="${APK_PATH%.*}-decoded"
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/decode-apk.sh "$APK_PATH" -o "$DECODED_DIR"
```

Verify the decoded directory contains `smali/` and `AndroidManifest.xml` (the script does this automatically and outputs `DECODED_DIR:<path>`).

If the output includes `MERGED_FROM_SPLITS:<path>`, inform the user: "This is a split APK bundle. Its splits were merged into a single APK with APKEditor before decoding; the rebuild will produce one APK installable with `adb install`." Relay any `OBB_WARNING:` lines (OBB files must be copied to the device separately).

The legacy `--keep-splits` flag (decode the base only, rebuild an XAPK) is deprecated: do not use it unless the user explicitly asks for XAPK output.

### Step 4b: Protection check (detection only)

`decode-apk.sh` ends with a protection check (`detect-protection.sh`, informational, exit code unchanged). Re-run it on a decoded directory with:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/detect-protection.sh "${DECODED_DIR}"
```

Read `PROTECTION_DETECTED:<id>:<category>:<confidence>:<evidence>` and `PROTECTION_SUMMARY:<none|integrity|license|hardener|signature-vm>`, then set expectations **before** spending time on targets and a rebuild:
- `signature-vm` (Google Play PairIP with signature check / encrypted VM) or `hardener` (commercial packer / RASP): a rebuilt, re-signed APK **will not run**. Offer to stop, or to continue for the SDK report only.
- `license` (PairIP license check, LVL): the rebuilt APK may stop at a "Get this app from Play" screen. Ask whether to continue.
- `integrity` (Play Integrity / SafetyNet client, often bundled by SDKs): the app starts; note it in the report.

Never try to remove, disable or work around a protection: only report it.

### Step 5: Identify targets — Registry Scan

The decoded directory contains smali bytecode. Use `registry-scan.py` to match against the SDK registry (33 SDKs, 201 entry points, 210 ad operations).

**5a. Run registry scan:**

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/registry-scan.py "${DECODED_DIR}" \
  --registry "${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/registry/" \
  --depth 1 --category all \
  --output-dir "${DECODED_DIR}"
```

Parse stdout:
- `MATCHED:` lines — present as a table (SDK name, category, target count)
- `UNKNOWN_PACKAGE:` lines — candidates for Step 5c
- `REGISTRY_TARGETS:` / `REGISTRY_MANIFEST:` — paths to generated files

**Depth levels**: Ask the user which depth to use:
- **Depth 1** (default, safest): only SDK init/start methods
- **Depth 2**: + ad load/show/cache methods
- **Depth 3**: + bulk-stub internal packages (aggressive, version-dependent)

If the user requests depth 2 or 3, re-run with `--depth 2` or `--depth 3`.

**Fallback** (if Python 3 not available): use builtin hardcoded detection:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh "${DECODED_DIR}" --all --dry-run
```

**5b. Identify wrapper frameworks:**

Search for non-SDK packages that invoke known SDK methods — these are wrapper/bridge classes. Use Grep (auto-approved) to find invocations from app code:

```
Grep: pattern="invoke-.*Lcom/google/android/gms/ads|invoke-.*Lcom/unity3d/ads|invoke-.*Lcom/ironsource|invoke-.*Lcom/applovin"
      path=<decoded-dir>/smali*/
```

Filter to non-SDK packages to identify wrappers. If found, add as `--package` targets.

**5c. Unknown SDK discovery (if registry reported UNKNOWN_PACKAGE candidates):**

For significant unknown packages (10+ classes, proper naming), use Claude Code built-in tools:

1. **Glob** to list main classes in the package
2. **Grep** for SDK patterns: `\.method.*(init|initialize|start|load|show)`, `const-string.*http`
3. **Read** key classes to understand the API
4. Classify: ads SDK, tracker, utility, or app code

Present unknown candidates as a table. If the user wants deep analysis:

**5d. Deep analysis (opt-in, requires user confirmation):**

Ask: "I found N unknown SDK candidates. Want me to research them via web search?"

For each confirmed candidate:
1. Web search for the package name
2. Read main smali classes for public API
3. Propose treatment and generate custom targets

**5e. Compile and confirm:**

Present the complete target summary (registry + custom + wrappers) and ask for confirmation:
- `--ads` / `--trackers` / `--all`
- Which SDKs to include/exclude

### Step 6: Dry-run preview

Always run a dry-run first. Use registry-driven mode when available:

```bash
# Registry-driven mode (preferred)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh "${DECODED_DIR}" \
  --no-builtin-targets --dry-run \
  --targets-file "${DECODED_DIR}/registry-targets.txt" \
  --manifest-components-file "${DECODED_DIR}/registry-manifest.txt"

# Fallback (no Python)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh "${DECODED_DIR}" --all --dry-run
```

If wrapper packages were found, add `--package` flags. If custom targets were generated, append them to the targets file first.

Show the user what will be patched. Ask for explicit confirmation. Remind about side effects.

### Step 7: Neutralize

Apply the neutralization:

```bash
# Registry-driven mode (preferred)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh "${DECODED_DIR}" \
  --no-builtin-targets \
  --targets-file "${DECODED_DIR}/registry-targets.txt" \
  --manifest-components-file "${DECODED_DIR}/registry-manifest.txt"

# Fallback (no Python)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh "${DECODED_DIR}" --all
```

Parse the `PATCHED:` and `MANIFEST_DISABLED:` output lines for the report.

### Step 8: Rebuild & sign

The output is always a single APK. **Ask the user their signing preference**:

> How would you like to sign the rebuilt APK?
>
> 1. **Stable debug key** (recommended) — the user-level neutralizer debug key (`~/.config/android-re/neutralizer-debug.keystore`), created once and always reused so later builds install over earlier ones
> 2. **Custom keystore** — provide path, alias, and password
> 3. **No signing** — output unsigned APK

Then rebuild with the appropriate flag:

```bash
# Stable user-level debug key (recommended)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/rebuild-apk.sh "${DECODED_DIR}" --auto-keystore

# Or with custom keystore
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/rebuild-apk.sh "${DECODED_DIR}" --keystore /path/to/keystore

# Or unsigned
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/rebuild-apk.sh "${DECODED_DIR}" --no-sign
```

Parse the output for:
- `KEYSTORE_USED:<path>` — which keystore was used
- `KEYSTORE_SOURCE:<source>` — how it was resolved (`debug-user` = existing stable key, `debug-generated` = stable key created now, `custom`)
- `KEYSTORE_ALIAS:<alias>` — the key alias used for signing
- `ALIGN_OK:<n>:16k|4k|none|n/a` / `ALIGN_WARNING:not-16k|so-not-page-aligned` / `ALIGN_FAIL:<entry>` — alignment of stored entries and page alignment of stored native libraries (zipalign `-P 16` when supported, else `-p`); on `ALIGN_FAIL` the script exits 1 and leaves the APK as `<output>.misaligned`. `ALIGN_WARNING:not-16k` means devices with 16 KB pages will refuse it
- `ABI_WARNING:32bit-only:<abis>` — only 32-bit native code: warn that many recent phones (e.g. Galaxy S25, Pixel 7 and later) are 64-bit only and will refuse to install it
- `DEPRECATION_WARNING:xapk-output`, `SPLIT_SIGNED:<filename>`, `XAPK_ASSEMBLED:<path>` — only for a directory decoded with the deprecated `--keep-splits` (install with `adb install-multiple` after unzipping the XAPK)

### Step 9: Report & next steps

Generate a neutralization report following the format in `${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/SKILL.md` (Phase 6). **The report must include the "Side Effects & Legal Notice" section.**

Include in the report:
- **Output format**: APK, APK merged from a split bundle, or XAPK (deprecated `--keep-splits` only)
- **Keystore used**: path and source (from `KEYSTORE_USED:` / `KEYSTORE_SOURCE:` output)
- **Install command**: `adb install <path>` (deprecated XAPK: `adb install-multiple <base.apk> <splits...>`)
- **Upgrade note**: builds made before the stable user-level key existed were signed with a per-directory key; installing over one of them fails once with a signature mismatch — `adb uninstall <package>` first

Tell the user what they can do next:
- **Test thoroughly**: "Install via `adb install <apk>`" — test for crashes, especially features tied to ads or analytics
- **Verify**: "I can re-run entry point detection on the rebuilt APK to confirm neutralization"
- **Custom targets**: "If the app uses obfuscated SDK calls, provide a targets file for additional patching"
- **Deep analysis**: "Run `/find-trackers` or `/find-ads` for full SDK analysis"
- **Restore**: "Backup `.smali.bak` files were created — I can restore the original methods"
- **Legal review**: "Have your legal/compliance team review before distributing the modified APK"
