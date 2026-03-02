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

If any `INSTALL_REQUIRED:` lines appear, install the missing dependencies:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/install-dep.sh <dep>
```

### Step 4: Decode APK/XAPK

Decode the APK or XAPK using decode-apk.sh (handles both formats; for XAPKs extracts the base APK automatically):

```bash
# Strip both .apk and .xapk extensions for the output dir name
DECODED_DIR="${APK_PATH%.*}-decoded"
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/decode-apk.sh "$APK_PATH" -o "$DECODED_DIR"
```

Verify the decoded directory contains `smali/` and `AndroidManifest.xml` (the script does this automatically and outputs `DECODED_DIR:<path>`).

### Step 5: Identify targets

Run entry point detection to find which SDK calls exist in the app code:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/ad-analysis/scripts/find-ads.sh "${DECODED_DIR}" --entrypoints
bash ${CLAUDE_PLUGIN_ROOT}/skills/tracker-analysis/scripts/find-trackers.sh "${DECODED_DIR}" --entrypoints
```

Present the results and ask the user what to neutralize:
- **Ads only** (`--ads`)
- **Trackers only** (`--trackers`)
- **Both** (`--all`, recommended)

### Step 6: Dry-run preview

Always run a dry-run first so the user can review what will be patched:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh "${DECODED_DIR}" --all --dry-run
```

Show the user the list of methods that would be patched and manifest components that would be disabled. Ask for explicit confirmation before proceeding. Remind the user about possible side effects for any SDK where the stub could cause breakage (especially `getInstance()` returning null).

### Step 7: Neutralize

Apply the neutralization:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/neutralize.sh "${DECODED_DIR}" --all
```

Parse the `PATCHED:` and `MANIFEST_DISABLED:` output lines for the report.

### Step 8: Rebuild & sign

Rebuild the APK with a debug signing key:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/scripts/rebuild-apk.sh "${DECODED_DIR}" --debug-key
```

### Step 9: Report & next steps

Generate a neutralization report following the format in `${CLAUDE_PLUGIN_ROOT}/skills/sdk-neutralizer/SKILL.md` (Phase 6). **The report must include the "Side Effects & Legal Notice" section.**

Tell the user what they can do next:
- **Test thoroughly**: "Install via `adb install <apk>` and test for crashes — especially features tied to ads or analytics"
- **Verify**: "I can re-run entry point detection on the rebuilt APK to confirm neutralization"
- **Custom targets**: "If the app uses obfuscated SDK calls, provide a targets file for additional patching"
- **Deep analysis**: "Run `/find-trackers` or `/find-ads` for full SDK analysis"
- **Restore**: "Backup `.smali.bak` files were created — I can restore the original methods"
- **Legal review**: "Have your legal/compliance team review before distributing the modified APK"
