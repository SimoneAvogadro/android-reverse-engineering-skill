# Android Reverse Engineering & API Extraction — Claude Code skill

A Claude Code skill that decompiles Android APK/XAPK/JAR/AAR files, **extracts HTTP APIs**, and **audits privacy** by detecting tracker/analytics and advertising SDKs — so you can document endpoints, understand data collection, and assess ad monetization without the original source code.

## What it does

- **Decompiles** APK, XAPK, JAR, and AAR files using jadx and Fernflower/Vineflower (single engine or side-by-side comparison)
- **Extracts and documents APIs**: Retrofit endpoints, OkHttp calls, hardcoded URLs, auth headers and tokens
- **Traces call flows** from Activities/Fragments through ViewModels and repositories down to HTTP calls
- **Detects tracker/analytics SDKs**: Firebase Analytics, Adjust, AppsFlyer, Mixpanel, Amplitude, Segment, Braze, CleverTap, Flurry — with deep analysis of init, events, user identification, consent, and data exfiltration endpoints
- **Detects advertising SDKs**: AdMob, Unity Ads, IronSource/LevelPlay, AppLovin/MAX, Meta Audience Network, Vungle, InMobi, Chartboost, Pangle, Mintegral — with ad format mapping, mediation analysis, and consent framework detection
- **Analyzes** app structure: manifest, packages, architecture patterns
- **Handles obfuscated code**: strategies for navigating ProGuard/R8 output

## Requirements

**Required:**
- Java JDK 17+
- [jadx](https://github.com/skylot/jadx) (CLI)

**Optional (recommended):**
- [Vineflower](https://github.com/Vineflower/vineflower) or [Fernflower](https://github.com/JetBrains/fernflower) — better output on complex Java code
- [dex2jar](https://github.com/pxb1988/dex2jar) — needed to use Fernflower on APK/DEX files

See `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/setup-guide.md` for detailed installation instructions.

## Installation

### From GitHub (recommended)

Inside Claude Code, run:

```
/plugin marketplace add SimoneAvogadro/android-reverse-engineering-skill
/plugin install android-reverse-engineering@android-reverse-engineering-skill
```

The skill will be permanently available in all future sessions.

### From a local clone

```bash
git clone https://github.com/SimoneAvogadro/android-reverse-engineering-skill.git
```

Then in Claude Code:

```
/plugin marketplace add /path/to/android-reverse-engineering-skill
/plugin install android-reverse-engineering@android-reverse-engineering-skill
```

## Usage

### Slash commands

```
/decompile path/to/app.apk
```
Runs the full workflow: dependency check, decompilation, and initial structure analysis.

```
/find-trackers path/to/decompiled/sources/
```
Detects analytics/tracker SDKs and produces a privacy report with init patterns, events, user identification, consent handling, and data endpoints.

```
/find-ads path/to/decompiled/sources/
```
Detects advertising SDKs and produces a report with ad formats, mediation setup, ad unit IDs, and consent framework analysis.

### Natural language

The skills activate on phrases like:

- "Decompile this APK"
- "Reverse engineer this Android app"
- "Extract API endpoints from this app"
- "Follow the call flow from LoginActivity"
- "Analyze this AAR library"
- "Find trackers in this app"
- "What analytics SDKs does this app use?"
- "Detect ad networks in this app"
- "Show me the ad mediation setup"

### Manual scripts

The scripts can also be used standalone:

```bash
# Check dependencies
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.sh

# Install a missing dependency (auto-detects OS and package manager)
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh jadx
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh vineflower

# Decompile APK with jadx (default)
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh app.apk

# Decompile XAPK (auto-extracts and decompiles each APK inside)
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh app-bundle.xapk

# Decompile with Fernflower
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh --engine fernflower library.jar

# Run both engines and compare
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh --engine both --deobf app.apk

# Find API calls
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --retrofit
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --urls

# Find tracker/analytics SDKs
bash plugins/android-reverse-engineering/skills/tracker-analysis/scripts/find-trackers.sh output/sources/
bash plugins/android-reverse-engineering/skills/tracker-analysis/scripts/find-trackers.sh output/sources/ --firebase
bash plugins/android-reverse-engineering/skills/tracker-analysis/scripts/find-trackers.sh output/sources/ --adjust

# Find advertising SDKs
bash plugins/android-reverse-engineering/skills/ad-analysis/scripts/find-ads.sh output/sources/
bash plugins/android-reverse-engineering/skills/ad-analysis/scripts/find-ads.sh output/sources/ --admob
bash plugins/android-reverse-engineering/skills/ad-analysis/scripts/find-ads.sh output/sources/ --mediation
```

## Repository Structure

```
android-reverse-engineering-skill/
├── .claude-plugin/
│   └── marketplace.json                    # Marketplace catalog
├── plugins/
│   └── android-reverse-engineering/
│       ├── .claude-plugin/
│       │   └── plugin.json                 # Plugin manifest
│       ├── skills/
│       │   ├── android-reverse-engineering/ # Core RE skill
│       │   │   ├── SKILL.md                # 5-phase workflow
│       │   │   ├── references/
│       │   │   │   ├── setup-guide.md
│       │   │   │   ├── jadx-usage.md
│       │   │   │   ├── fernflower-usage.md
│       │   │   │   ├── api-extraction-patterns.md
│       │   │   │   └── call-flow-analysis.md
│       │   │   └── scripts/
│       │   │       ├── check-deps.sh
│       │   │       ├── install-dep.sh
│       │   │       ├── decompile.sh
│       │   │       └── find-api-calls.sh
│       │   ├── tracker-analysis/            # Tracker/analytics SDK detection
│       │   │   ├── SKILL.md                # 4-phase workflow
│       │   │   ├── references/
│       │   │   │   ├── tracker-sdk-catalog.md
│       │   │   │   ├── tracker-init-patterns.md
│       │   │   │   └── data-exfiltration-patterns.md
│       │   │   └── scripts/
│       │   │       └── find-trackers.sh
│       │   └── ad-analysis/                 # Advertising SDK detection
│       │       ├── SKILL.md                # 3-phase workflow
│       │       ├── references/
│       │       │   ├── ad-sdk-catalog.md
│       │       │   ├── mediation-patterns.md
│       │       │   └── ad-format-patterns.md
│       │       └── scripts/
│       │           └── find-ads.sh
│       └── commands/
│           ├── decompile.md                # /decompile slash command
│           ├── find-trackers.md            # /find-trackers slash command
│           └── find-ads.md                 # /find-ads slash command
├── LICENSE
└── README.md
```

## References

- [jadx — Dex to Java decompiler](https://github.com/skylot/jadx)
- [Fernflower — JetBrains analytical decompiler](https://github.com/JetBrains/fernflower)
- [Vineflower — Fernflower community fork](https://github.com/Vineflower/vineflower)
- [dex2jar — DEX to JAR converter](https://github.com/pxb1988/dex2jar)
- [apktool — Android resource decoder](https://apktool.org/)

## Disclaimer

This plugin is provided strictly for **lawful purposes**, including but not limited to:

- Security research and authorized penetration testing
- Interoperability analysis permitted under applicable law (e.g., EU Directive 2009/24/EC, US DMCA §1201(f))
- Malware analysis and incident response
- Educational use and CTF competitions

**You are solely responsible** for ensuring that your use of this tool complies with all applicable laws, regulations, and terms of service. Unauthorized reverse engineering of software you do not own or do not have permission to analyze may violate intellectual property laws and computer fraud statutes in your jurisdiction.

The authors disclaim any liability for misuse of this tool.

## License

Apache 2.0 — see [LICENSE](LICENSE)
