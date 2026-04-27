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

If the user provided a path as an argument, use that. Otherwise, ask the user for the path to the APK or XAPK file.

Verify the file exists and is an APK or XAPK:

```bash
file "$APK_PATH"
```

### Step 3: Check dependencies

Run the dependency check to ensure all required tools are installed:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/check-neutralize-deps.sh
```

If any `INSTALL_REQUIRED:` lines appear, install all dependencies at once:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/install-dep.sh neutralize-all
```

If the script exits with code 2 (sudo needed but no TTY — common inside Claude Code), tell the user to run this command in their terminal:

```
sudo bash <full-path-to>/install-dep.sh neutralize-all
```

Provide the **full resolved path** (replace `${CLAUDE_PLUGIN_ROOT}` with the actual path) so the user can copy-paste directly.

### Step 4: Decode APK/XAPK

Decode the APK or XAPK using decode-apk.sh (handles both formats; for XAPKs extracts and decodes the base APK while preserving the full XAPK structure for rebuild):

```bash
# Strip both .apk and .xapk extensions for the output dir name
DECODED_DIR="${APK_PATH%.*}-decoded"
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/decode-apk.sh "$APK_PATH" -o "$DECODED_DIR"
```

Verify the decoded directory contains `smali/` and `AndroidManifest.xml` (the script does this automatically and outputs `DECODED_DIR:<path>`).

If the output includes `XAPK_ORIGIN:<path>`, inform the user: "This is an XAPK (split APK bundle). The base APK has been decoded for neutralization, and all split APKs are preserved. During rebuild, all APKs (base + splits) will be re-signed with the same key and reassembled into a new XAPK."

### Step 5: Identify targets — Registry Scan

The decoded directory contains smali bytecode. Use `registry-scan.py` to match against the SDK registry (29 SDKs, 123 entry points, 156 ad operations).

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

**If the input was an XAPK**, ask the user how they want the output:

> The original input was an XAPK (split APK bundle). How would you like to rebuild?
>
> 1. **Merged single APK** (recommended for sideloading) — merges split contents into one APK, installable with standard `adb install`. May be missing some locale/density resources.
> 2. **XAPK bundle** (preserves original structure) — requires `adb install-multiple` to install. All splits preserved exactly.

If the user chooses option 1, run `merge-splits.sh` before rebuilding:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/merge-splits.sh "${DECODED_DIR}"
```

**Then ask the user their signing preference**:

> How would you like to sign the rebuilt APK?
>
> 1. **Auto-detect** (recommended) — checks `~/.android/debug.keystore` first, then generates a debug key
> 2. **Custom keystore** — provide path, alias, and password
> 3. **No signing** — output unsigned APK

Then rebuild with the appropriate flag:

```bash
# Auto-detect keystore (recommended)
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/rebuild-apk.sh "${DECODED_DIR}" --auto-keystore

# Or with custom keystore
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/rebuild-apk.sh "${DECODED_DIR}" --keystore /path/to/keystore

# Or unsigned
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/rebuild-apk.sh "${DECODED_DIR}" --no-sign
```

Parse the output for:
- `KEYSTORE_USED:<path>` — which keystore was used
- `KEYSTORE_SOURCE:<source>` — how it was resolved (debug-standard, debug-previous, debug-generated, custom)
- `KEYSTORE_ALIAS:<alias>` — the key alias used for signing
- `SPLIT_SIGNED:<filename>` — each re-signed split APK (XAPK only)
- `XAPK_ASSEMBLED:<path>` — final XAPK output (XAPK only)

For XAPK output: inform the user that install requires `adb install-multiple` (unzip the XAPK first, then `adb install-multiple *.apk`).

### Step 9: Report & next steps

Generate a neutralization report following the format in `${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/SKILL.md` (Phase 6). **The report must include the "Side Effects & Legal Notice" section.**

Include in the report:
- **Output format**: APK or XAPK (split bundle)
- **Keystore used**: path and source (from `KEYSTORE_USED:` / `KEYSTORE_SOURCE:` output)
- **Install command**: `adb install <path>` for APK, `adb install-multiple <base.apk> <splits...>` for XAPK

Tell the user what they can do next:
- **Test thoroughly**: for APK: "Install via `adb install <apk>`"; for XAPK: "Unzip the XAPK, then install via `adb install-multiple *.apk`" — test for crashes, especially features tied to ads or analytics
- **Verify**: "I can re-run entry point detection on the rebuilt APK to confirm neutralization"
- **Custom targets**: "If the app uses obfuscated SDK calls, provide a targets file for additional patching"
- **Deep analysis**: "Run `/find-trackers` or `/find-ads` for full SDK analysis"
- **Restore**: "Backup `.smali.bak` files were created — I can restore the original methods"
- **Legal review**: "Have your legal/compliance team review before distributing the modified APK"
