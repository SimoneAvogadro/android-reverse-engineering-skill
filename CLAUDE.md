# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Claude Code Skill (plugin) for Android reverse engineering, API extraction, and privacy auditing. It provides four skills:
- **android-reverse-engineering**: 5-phase workflow — dependency verification, APK/XAPK/JAR/AAR decompilation (jadx and/or Fernflower), manifest/structure analysis, call flow tracing, and HTTP API endpoint extraction
- **tracker-analysis**: 4-phase workflow — detect analytics/tracker SDKs (Firebase, Adjust, AppsFlyer, Mixpanel, Amplitude, Segment, Braze, CleverTap, Flurry), analyze init/events/user ID/consent, report data exfiltration endpoints
- **ad-analysis**: 3-phase workflow — detect ad SDKs (AdMob, Unity, IronSource, AppLovin, Meta AN, Vungle, InMobi, Chartboost, Pangle, Mintegral), map ad formats and mediation setup, report privacy/consent
- **sdk-neutralizer**: 6-phase workflow — decode APK, identify tracker/ad SDK entry points, neutralize by replacing smali method bodies with stubs, disable manifest components, rebuild and sign APK for enterprise sideloading

## Repository Structure

- `.claude-plugin/marketplace.json` — Marketplace catalog entry
- `plugins/android-reverse-engineering/.claude-plugin/plugin.json` — Plugin manifest
- `plugins/android-reverse-engineering/commands/decompile.md` — `/decompile` slash command
- `plugins/android-reverse-engineering/commands/find-trackers.md` — `/find-trackers` slash command
- `plugins/android-reverse-engineering/commands/find-ads.md` — `/find-ads` slash command
- `plugins/android-reverse-engineering/commands/neutralize.md` — `/neutralize` slash command
- `plugins/android-reverse-engineering/skills/android-reverse-engineering/` — Core RE skill (5-phase workflow, references, scripts)
- `plugins/android-reverse-engineering/skills/tracker-analysis/` — Tracker/analytics SDK detection skill (4-phase workflow, references, find-trackers.sh)
- `plugins/android-reverse-engineering/skills/ad-analysis/` — Advertising SDK detection skill (3-phase workflow, references, find-ads.sh)
- `plugins/android-reverse-engineering/skills/sdk-neutralizer/` — SDK neutralization skill (6-phase workflow, references, decode-apk.sh/.ps1, detect-protection.sh/.ps1, detect-adwrapper.sh/.ps1, neutralize.sh, registry-scan.py, rebuild-apk.sh/.ps1, check-neutralize-deps.sh/.ps1)
- `plugins/android-reverse-engineering/skills/sdk-neutralizer/registry/` — SDK registry (48 JSON files defining neutralization targets, manifest components, protected patterns; includes `consent-umptcf.json`, a code-injection entry for UMP/IAB-TCF consent)

## Key Scripts

Core scripts under `plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/`:

```bash
# Check installed dependencies
bash scripts/check-deps.sh

# Install a dependency (auto-detects OS/package manager)
bash scripts/install-dep.sh <dep>   # e.g., jadx, vineflower, dex2jar

# Install ALL neutralizer dependencies at once (java, apktool, apkeditor, build-tools, zip);
# build-tools (pinned Android SDK Build-Tools 36.0.0) needs the user's explicit license acceptance
bash scripts/install-dep.sh neutralize-all --accept-android-sdk-license

# Decompile an APK/JAR/AAR/XAPK
bash scripts/decompile.sh [--engine jadx|fernflower|both] [--deobf] [--no-res] [-o outdir] <file>

# Search decompiled source for API calls
bash scripts/find-api-calls.sh <source-dir> [--retrofit|--okhttp|--volley|--urls|--auth|--all]
```

Tracker analysis script under `plugins/android-reverse-engineering/skills/tracker-analysis/scripts/`:

```bash
# Search for tracker/analytics SDKs
bash find-trackers.sh <source-dir> [--firebase|--adjust|--appsflyer|--mixpanel|--amplitude|--segment|--braze|--clevertap|--flurry|--all]
```

Ad analysis script under `plugins/android-reverse-engineering/skills/ad-analysis/scripts/`:

```bash
# Search for advertising SDKs
bash find-ads.sh <source-dir> [--admob|--unity|--ironsource|--applovin|--facebook|--formats|--mediation|--consent|--entrypoints|--all]
```

SDK neutralizer scripts under `plugins/android-reverse-engineering/skills/sdk-neutralizer/scripts/`:

```bash
# Check neutralization dependencies (including apktool >= 2.9.0, Python 3.6+ optional;
# APKEditor required when <input> is a split bundle; reports zipalign -P 16 support)
bash check-neutralize-deps.sh [<input>]

# Decode APK, or merge a split bundle (XAPK/APKM/APKS/dir) with APKEditor then decode
# (writes .merged-from-splits.json; --keep-splits = deprecated base-only decode + .xapk-origin/)
bash decode-apk.sh <file.apk|file.xapk|file.apkm|file.apks|dir> [-o <decoded-dir>] [--keep-splits]

# Detect anti-tamper / integrity / licensing protection (PairIP, LVL, packers/RASP from
# APKiD signatures) — detection only, never bypassed; run automatically by decode-apk,
# always exits 0; PROTECTION_DETECTED:<id>:<category>:<confidence>:<evidence> +
# PROTECTION_SUMMARY:<none|integrity|license|hardener|signature-vm>
bash detect-protection.sh <decoded-dir>

# Detect a publisher's in-house ad/analytics mediation wrapper (a layer that drives the
# network ad SDKs, or serves house/WebView ads, on the app's behalf — e.g. com.rovio.beacon,
# guru.ads.fusion) that per-network registry neutralization can miss — detection only, never
# modified/removed; run automatically by decode-apk, always exits 0; excludes known SDKs
# (registry, minus entries flagged "in_house_wrapper": true) + common libs;
# ADWRAPPER_DETECTED:<package>:<confidence>:<evidence> + ADWRAPPER_SUMMARY:<none|candidate>
bash detect-adwrapper.sh <decoded-dir>

# Scan decoded APK against SDK registry (generates targets-file + manifest-components-file)
# Depth: 1=entry_points only, 2=+ad_operations, 3=+deep_patterns
python3 registry-scan.py <decoded-dir> --registry <registry-path> --depth 1|2|3 --category ads|trackers|all --output-dir <decoded-dir>

# Neutralize SDK entry points in decoded APK (dry-run first)
# Registry-driven mode (preferred):
bash neutralize.sh <decoded-dir> --no-builtin-targets --targets-file <decoded-dir>/registry-targets.txt --manifest-components-file <decoded-dir>/registry-manifest.txt [--dry-run] [--package <path>]
# Fallback (builtin targets):
bash neutralize.sh <decoded-dir> [--ads|--trackers|--all] [--dry-run] [--no-backup] [--no-manifest] [--targets-file <file>] [--replay] [--no-save-manifest]

# Rebuild and sign a single APK (zipalign -P 16 / -p — required for stored .so with
# extractNativeLibs=false; alignment check of all stored entries; ABI warning;
# stable user-level debug key ~/.config/android-re/neutralizer-debug.keystore);
# a deprecated --keep-splits dir (.xapk-origin/) is reassembled into an XAPK instead
bash rebuild-apk.sh <decoded-dir> [--auto-keystore|--debug-key|--keystore <file>] [-o <output>] [--no-sign] [--zipalign|--no-zipalign]
```

Windows: `check-neutralize-deps.ps1`, `decode-apk.ps1`, `detect-protection.ps1`, `detect-adwrapper.ps1` and `rebuild-apk.ps1` mirror the bash scripts (PowerShell 5.1, `-Output`/`-KeepSplits`/`-AutoKeystore`...); `neutralize.sh` and `registry-scan.py` still require bash + python3 (WSL/Git Bash) for now. `APKEDITOR_JAR` overrides the APKEditor JAR location on both platforms.

SDK registry under `plugins/android-reverse-engineering/skills/sdk-neutralizer/registry/`:

- 48 SDK JSON files + `_schema.json` schema definition
- Covers: AdMob, Unity Ads, IronSource, AppLovin, Meta AN, Vungle, InMobi, Chartboost, Pangle, BidMachine, Smaato, PubNative, Ogury, Fyber, Amazon APS, Facebook, Firebase Analytics, Firebase Crashlytics, AppsFlyer, Adjust, Braze, CleverTap, Guru Fusion, Mintegral, Mixpanel, MobileFuse, Moloco, PubMatic, TradPlus, Tapjoy, Yandex Ads, Google Tag Manager, AppMetrica, AdColony, Google UMP / IAB TCF consent
- Each JSON defines: packages, entry_points, ad_operations, deep_patterns, manifest_components, protected_patterns; a method target may specify either `stub` (trivial no-op/constant return) or `inject` (code injection)
- **Consent neutralization** (`category: consent`, `consent-umptcf.json`) is a distinct capability: instead of stubbing, it INJECTS code that suppresses the Google UMP / IAB TCF consent dialog and writes a reject-all TCF v2.2 state (gdprApplies=1, all-zero consent + legitimate-interest keys, a decode-verified reject-all `IABTCF_TCString`) to the default SharedPreferences, so TCF-honoring SDKs self-limit. The inject kind travels on the targets-file line as an optional third `:`-field; `neutralize.sh` emits the injected smali. See `skills/sdk-neutralizer/references/consent-neutralization.md`. It complements (does not replace) per-SDK stubbing.
- `registry-scan.py` consumes these JSONs to generate neutralization targets

## Architecture

**Plugin structure follows Claude Code skill conventions:**
- `skills/<name>/SKILL.md` defines the skill's workflow and capabilities
- `commands/<name>.md` defines slash commands with YAML frontmatter
- `scripts/` contains executable bash utilities invoked by the skill
- `references/` contains in-depth technical documentation the skill consults

**Script conventions:**
- Exit codes: 0 = success, 1 = error, 2 = manual action needed
- `check-deps.sh` outputs machine-readable `INSTALL_REQUIRED:` and `INSTALL_OPTIONAL:` lines
- `decompile.sh` handles XAPK by extracting the archive and decompiling each APK separately
- `${CLAUDE_PLUGIN_ROOT}` references the plugin root directory; `FERNFLOWER_JAR_PATH` for custom JAR location

**Decompiler strategy:**
- jadx: default for APKs (fast, handles resources natively)
- Fernflower/Vineflower: better Java output for complex code, requires dex2jar for APK input
- `--engine both`: runs both in parallel and compares output quality

## No Build/Test/Lint

This is a documentation-and-scripts plugin with no compiled code, no test suite, and no linter configuration. Changes are validated by reading the markdown/bash and testing scripts manually against APK files.

## Versioning

The plugin version is declared in **three** places across two files that **must always be kept in sync**:
- `.claude-plugin/marketplace.json` → `metadata.version` (marketplace metadata)
- `.claude-plugin/marketplace.json` → `plugins[0].version` (marketplace catalog entry)
- `plugins/android-reverse-engineering/.claude-plugin/plugin.json` → `version` (plugin manifest)

Claude Code reads the version from `plugin.json` with priority — if that file has a stale version, `/plugin` will show the old number even if `marketplace.json` is updated. **Always bump all three together; never update only one file.**

**When to bump:** suggest a version bump whenever a PR or significant change lands (new skill, new script, new SDK registry entries, workflow changes) — minor bump (`1.x.0`) for new features/important PRs, patch bump (`1.x.y`) for fixes and docs-only changes. Keep `master` and long-lived feature branches on the same version after merging between them, so the version fields don't conflict on the next merge.

## Conventions

- Line endings are LF (enforced via `.gitattributes` for WSL/Windows compatibility)
- Scripts target Bash 4.0+ and support Linux (apt/dnf/pacman) and macOS (Homebrew); `install-dep.sh`, `check-neutralize-deps.sh`, `decode-apk.sh` and `rebuild-apk.sh` are written to also run on macOS's stock bash 3.2 with BSD tools
- `.sh`/`.ps1` pairs must keep feature parity; `.ps1` scripts target Windows PowerShell 5.1 (no PS7-only syntax)
- Scripts fall back to user-local installs (`~/.local/`) when sudo is unavailable; `install-dep.sh` must run as the user (it refuses sudo for per-user targets and calls sudo itself only for system packages)
