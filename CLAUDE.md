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
- `plugins/android-reverse-engineering/skills/sdk-neutralizer/` — SDK neutralization skill (6-phase workflow, references, decode-apk.sh, neutralize.sh, registry-scan.py, merge-splits.sh, rebuild-apk.sh)
- `plugins/android-reverse-engineering/skills/sdk-neutralizer/registry/` — SDK registry (29 JSON files defining neutralization targets, manifest components, protected patterns)

## Key Scripts

Core scripts under `plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/`:

```bash
# Check installed dependencies
bash scripts/check-deps.sh

# Install a dependency (auto-detects OS/package manager)
bash scripts/install-dep.sh <dep>   # e.g., jadx, vineflower, dex2jar

# Install ALL neutralizer dependencies at once (java, apktool, apksigner, zip)
bash scripts/install-dep.sh neutralize-all

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
# Check neutralization dependencies (including apktool >= 2.9.0, Python 3.6+ optional)
bash check-neutralize-deps.sh

# Decode APK or XAPK (for XAPK: decodes base APK, preserves splits in .xapk-origin/)
bash decode-apk.sh <file.apk|file.xapk> [-o <decoded-dir>]

# Scan decoded APK against SDK registry (generates targets-file + manifest-components-file)
# Depth: 1=entry_points only, 2=+ad_operations, 3=+deep_patterns
python3 registry-scan.py <decoded-dir> --registry <registry-path> --depth 1|2|3 --category ads|trackers|all --output-dir <decoded-dir>

# Neutralize SDK entry points in decoded APK (dry-run first)
# Registry-driven mode (preferred):
bash neutralize.sh <decoded-dir> --no-builtin-targets --targets-file <decoded-dir>/registry-targets.txt --manifest-components-file <decoded-dir>/registry-manifest.txt [--dry-run] [--package <path>]
# Fallback (builtin targets):
bash neutralize.sh <decoded-dir> [--ads|--trackers|--all] [--dry-run] [--no-backup] [--no-manifest] [--targets-file <file>] [--replay] [--no-save-manifest]

# Merge XAPK splits into decoded base for single APK output (optional, for XAPK input)
bash merge-splits.sh <decoded-dir> [--abi <abi>] [--all-abis] [--skip-resources]

# Rebuild and sign neutralized APK (auto-reassembles XAPK if .xapk-origin/ exists, or single APK if merged)
bash rebuild-apk.sh <decoded-dir> [--auto-keystore|--debug-key|--keystore <file>] [-o <output>] [--no-sign] [--no-res] [--zipalign] [--single-apk]
```

SDK registry under `plugins/android-reverse-engineering/skills/sdk-neutralizer/registry/`:

- 29 SDK JSON files + `_schema.json` schema definition
- Covers: AdMob, Unity Ads, IronSource, AppLovin, Meta AN, Vungle, InMobi, Chartboost, Pangle, BidMachine, Smaato, PubNative, Ogury, Fyber, Amazon APS, Facebook, Firebase Analytics, Firebase Crashlytics, AppsFlyer, Adjust, Braze, CleverTap, Guru Fusion, Mintegral, Mixpanel, MobileFuse, Moloco, PubMatic, TradPlus
- Each JSON defines: packages, entry_points, ad_operations, deep_patterns, manifest_components, protected_patterns
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

The plugin version is declared in **two** files that **must be kept in sync**:
- `.claude-plugin/marketplace.json` → `plugins[0].version` (marketplace catalog)
- `plugins/android-reverse-engineering/.claude-plugin/plugin.json` → `version` (plugin manifest)

Claude Code reads the version from `plugin.json` with priority — if that file has a stale version, `/plugin` will show the old number even if `marketplace.json` is updated. **Always bump both files together.**

## Conventions

- Line endings are LF (enforced via `.gitattributes` for WSL/Windows compatibility)
- Scripts target Bash 4.0+ and support Linux (apt/dnf/pacman) and macOS (Homebrew)
- Scripts fall back to user-local installs (`~/.local/`) when sudo is unavailable
