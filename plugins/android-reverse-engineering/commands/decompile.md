---
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/check-deps.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/decompile.sh *), Read, Glob, Grep
description: Decompile an Android APK/XAPK/APKS/APKM/JAR/AAR and analyze its structure
user-invocable: true
argument-hint: <path to APK, XAPK, APKS, APKM, JAR, or AAR file>
argument: path to APK, XAPK, APKS, APKM, JAR, or AAR file (optional)
---

# /decompile

Decompile an Android application and perform initial structure analysis.

## Instructions

You are starting the Android reverse engineering workflow. Follow these steps:

### Step 1: Get the target file

If the user provided a file path as an argument, use that. Otherwise, ask the user for the path to the APK, XAPK, APKS, APKM, JAR, or AAR file they want to decompile.

### Step 2: Check and install dependencies

Run the dependency check:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/check-deps.sh
```

Parse the output looking for `INSTALL_REQUIRED:` and `INSTALL_OPTIONAL:` lines.

**If required dependencies are missing**, install them one by one:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/install-dep.sh java
bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/install-dep.sh jadx
```

The install script auto-detects the OS and installs without sudo when possible (user-local install to `~/.local/`). If sudo is needed, it will prompt — if the user declines or sudo is unavailable, the script prints exact manual instructions (exit code 2). Show those instructions to the user and stop.

**For optional dependencies** (`INSTALL_OPTIONAL:vineflower`, `INSTALL_OPTIONAL:dex2jar`, etc.), ask the user if they want to install them. Recommend vineflower and dex2jar for better results.

After any installations, re-run `check-deps.sh` to verify. Do not proceed until all required dependencies pass.

### Step 3: Decompile

Run the decompile script on the target file. Choose the engine based on the input:

- **APK or XAPK/APKS/APKM bundle** → use jadx first (handles resources natively; bundles are auto-extracted by the Bash script):

  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/decompile.sh <file>
  ```

- **JAR/AAR** and Fernflower is available → prefer fernflower for better Java output:

  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/decompile.sh --engine fernflower <file>
  ```

- **If jadx output has warnings** or the user wants the best quality → run both and compare:

  ```bash
  bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/decompile.sh --engine both <file>
  ```

For obfuscated apps (if the user mentions it or you detect single-letter package names), add `--deobf`:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/scripts/decompile.sh --deobf <file>
```

### Step 4: Analyze structure

After decompilation completes:

1. Read `AndroidManifest.xml` from the resources directory. For XAPK/APKS/APKM, check the base APK's output first; each contained APK has its own output subdirectory.
2. If the bundle contains `manifest.json`, review its preserved copy, `xapk-manifest.json`, in the output directory. APKS/APKM metadata differs by producer and may not include this file.
3. List the top-level package structure
4. Identify the app's main Activity, Application class, and architecture pattern
5. Report a summary to the user

### Step 5: Offer next steps

Tell the user what they can do next:

- **Trace call flows**: "I can follow the execution flow from any Activity to its API calls"
- **Extract APIs**: "I can search for all HTTP endpoints and document them"
- **Analyze specific classes**: "Point me to a specific class or feature to analyze"
- **Re-decompile with Fernflower**: If jadx output has warnings, offer to re-run with `--engine both` for comparison

Refer to the full skill documentation in `${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/SKILL.md` for the complete workflow.
