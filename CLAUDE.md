# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Claude Code Skill (plugin) for Android reverse engineering, API extraction, and privacy auditing. It provides three skills:
- **android-reverse-engineering**: 5-phase workflow — dependency verification, APK/XAPK/JAR/AAR decompilation (jadx and/or Fernflower), manifest/structure analysis, call flow tracing, and HTTP API endpoint extraction
- **tracker-analysis**: 4-phase workflow — detect analytics/tracker SDKs (Firebase, Adjust, AppsFlyer, Mixpanel, Amplitude, Segment, Braze, CleverTap, Flurry), analyze init/events/user ID/consent, report data exfiltration endpoints
- **ad-analysis**: 3-phase workflow — detect ad SDKs (AdMob, Unity, IronSource, AppLovin, Meta AN, Vungle, InMobi, Chartboost, Pangle, Mintegral), map ad formats and mediation setup, report privacy/consent

## Repository Structure

- `.claude-plugin/marketplace.json` — Marketplace catalog entry
- `plugins/android-reverse-engineering/.claude-plugin/plugin.json` — Plugin manifest
- `plugins/android-reverse-engineering/commands/decompile.md` — `/decompile` slash command
- `plugins/android-reverse-engineering/commands/find-trackers.md` — `/find-trackers` slash command
- `plugins/android-reverse-engineering/commands/find-ads.md` — `/find-ads` slash command
- `plugins/android-reverse-engineering/skills/android-reverse-engineering/` — Core RE skill (5-phase workflow, references, scripts)
- `plugins/android-reverse-engineering/skills/tracker-analysis/` — Tracker/analytics SDK detection skill (4-phase workflow, references, find-trackers.sh)
- `plugins/android-reverse-engineering/skills/ad-analysis/` — Advertising SDK detection skill (3-phase workflow, references, find-ads.sh)

## Key Scripts

Core scripts under `plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/`:

```bash
# Check installed dependencies
bash scripts/check-deps.sh

# Install a dependency (auto-detects OS/package manager)
bash scripts/install-dep.sh <dep>   # e.g., jadx, vineflower, dex2jar

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

## Conventions

- Line endings are LF (enforced via `.gitattributes` for WSL/Windows compatibility)
- Scripts target Bash 4.0+ and support Linux (apt/dnf/pacman) and macOS (Homebrew)
- Scripts fall back to user-local installs (`~/.local/`) when sudo is unavailable
