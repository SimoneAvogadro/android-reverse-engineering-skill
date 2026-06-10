# Android Reverse Engineering & API Extraction — Claude Code skill

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![GitHub stars](https://img.shields.io/github/stars/SimoneAvogadro/android-reverse-engineering-skill?style=social)](https://github.com/SimoneAvogadro/android-reverse-engineering-skill/stargazers) [![GitHub last commit](https://img.shields.io/github/last-commit/SimoneAvogadro/android-reverse-engineering-skill)](https://github.com/SimoneAvogadro/android-reverse-engineering-skill/commits/master)

A Claude Code skill that decompiles Android APK/XAPK/JAR/AAR files, **extracts HTTP APIs**, **audits privacy** by detecting tracker/analytics and advertising SDKs, and **neutralizes SDK telemetry** at the smali bytecode level for enterprise deployment — so you can document endpoints, understand data collection, assess ad monetization, and produce sanitized APKs without the original source code.

> **First-class Kotlin support**: modern Android apps are Kotlin/KMP, heavily obfuscated with R8. This skill recovers the **original Kotlin class names** from metadata R8 cannot strip, and extracts APIs from **Ktor**, **Apollo (GraphQL)** and **Koin** — not just the classic Retrofit/OkHttp stack. See [Kotlin name recovery](#kotlin-name-recovery-r8-deobfuscation) below.

> **Windows / PowerShell support (experimental)**: The `*.ps1` scripts alongside the bash ones are a recent community contribution, still being stabilised. For any issues please open an issue on **this** repository (not on the contributors' upstream forks): the PowerShell scripts are maintained here by [@SimoneAvogadro](https://github.com/SimoneAvogadro).

## Table of Contents

- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Repository Structure](#repository-structure)
- [References](#references)
- [Acknowledgments](#acknowledgments)
- [Disclaimer](#disclaimer)
- [License](#license)

## What it does

| Capability | Description |
|------------|-------------|
| **Fingerprint first (Phase 0)** | Triage an APK/XAPK in seconds — detect the framework (Flutter / React Native / Cordova / Xamarin / native-Kotlin), HTTP stack, obfuscation level and native libs *before* spending time on a full decompile |
| **Decompile** | APK, XAPK, JAR, and AAR files using jadx and Fernflower/Vineflower (single engine or side-by-side comparison) |
| **Recover Kotlin names** | Rebuild original `*Repository` / `*ViewModel` / `*UseCase` class names from R8-obfuscated binaries using Kotlin metadata that R8 cannot strip |
| **Extract APIs** | Retrofit, OkHttp, Volley **and modern Kotlin/KMP stacks: Ktor, Apollo (GraphQL), Koin DI** — endpoints, hardcoded URLs, auth headers, tokens and HMAC request-signing schemes |
| **Trace call flows** | From Activities/Fragments through ViewModels and repositories down to HTTP calls |
| **Detect tracker/analytics SDKs** | Firebase Analytics, Adjust, AppsFlyer, Mixpanel, Amplitude, Segment, Braze, CleverTap, Flurry — with deep analysis of init, events, user identification, consent, and data exfiltration endpoints |
| **Detect advertising SDKs** | AdMob, Unity Ads, IronSource/LevelPlay, AppLovin/MAX, Meta Audience Network, Vungle, InMobi, Chartboost, Pangle, Mintegral — with ad format mapping, mediation analysis, and consent framework detection |
| **Neutralize SDK entry points** | Replace tracker/ad SDK method bodies with no-op stubs at the smali level, disable manifest components, and rebuild a signed APK for enterprise sideloading |
| **Analyze structure** | Manifest, packages, architecture patterns |
| **Handle obfuscation** | R8-resistant path/URL extraction plus strategies for navigating ProGuard/R8 output |

## Requirements

**Required:**

- Java JDK 17+
- [jadx](https://github.com/skylot/jadx) (CLI)

**Optional (recommended):**

- [Vineflower](https://github.com/Vineflower/vineflower) or [Fernflower](https://github.com/JetBrains/fernflower) — better output on complex Java code
- [dex2jar](https://github.com/ThexXTURBOXx/dex2jar) — needed to use Fernflower on APK/DEX files

**For SDK neutralization (`/neutralize`):**
- [apktool](https://apktool.org/) (required) — APK decode/rebuild
- apksigner or jarsigner (required) — APK signing (apksigner required for XAPK)
- zip (required for XAPK rebuild)

See `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/setup-guide.md` for detailed installation instructions.

## Installation

### From GitHub (recommended)

Inside Claude Code, run:

```text
/plugin marketplace add SimoneAvogadro/android-reverse-engineering-skill
/plugin install android-reverse-engineering@android-reverse-engineering-skill
```

The skill will be permanently available in all future sessions.

### Permissions

Claude Code will ask for approval when the skill runs bash scripts (e.g., `neutralize.sh`, `find-ads.sh`, `apktool`). This is standard Claude Code security behaviour — `allowed-tools` in skills declares which tools may be used, but does not bypass your permission settings.

To avoid repeated prompts, you can either:

- **Per-session**: when prompted, select *"Yes, and don't ask again for: bash:\*"*
- **Permanent**: add the following to your `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(bash */sdk-neutralizer/scripts/*)",
      "Bash(bash */ad-analysis/scripts/*)",
      "Bash(bash */tracker-analysis/scripts/*)",
      "Bash(bash */android-reverse-engineering/scripts/*)",
      "Bash(apktool *)"
    ]
  }
}
```

### From a local clone

```bash
git clone https://github.com/SimoneAvogadro/android-reverse-engineering-skill.git
```

Then in Claude Code:

```text
/plugin marketplace add /path/to/android-reverse-engineering-skill
/plugin install android-reverse-engineering@android-reverse-engineering-skill
```

## Usage

### Slash commands

```text
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

```
/neutralize path/to/app.apk
```
Neutralizes tracker/ad SDK entry points in the APK, producing a sanitized APK for enterprise sideloading with telemetry disabled.

> **Warning**: SDK neutralization modifies bytecode and can cause crashes, broken features, or unexpected behaviour. The APK signature is invalidated. Ensure you have authorization to modify the application and that your use complies with applicable laws and the app's EULA. See the [Disclaimer](#disclaimer) for details.

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
- "Neutralize trackers in this APK"
- "Remove telemetry from this app"
- "Sanitize this APK for enterprise deployment"

### Manual scripts

The scripts can also be used standalone:

```bash
# Check dependencies
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.sh

# Install a missing dependency (auto-detects OS and package manager)
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh jadx
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh vineflower

# Install ALL neutralizer dependencies at once (java, apktool, apksigner, zip)
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh neutralize-all

# Fingerprint an APK/XAPK BEFORE decompiling (Phase 0 triage):
# framework, HTTP stack, obfuscation level, native libs, notable SDKs
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/fingerprint.sh app.apk

# Decompile APK with jadx (default)
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh app.apk

# Decompile XAPK (auto-extracts and decompiles each APK inside)
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh app-bundle.xapk

# Decompile with Fernflower
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh --engine fernflower library.jar

# Run both engines and compare
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh --engine both --deobf app.apk

# Find API calls — defaults to a full scan across every supported stack
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --retrofit
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --urls

# Modern Kotlin/KMP stacks and obfuscation-resistant extraction
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --ktor    # Ktor client
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --apollo  # Apollo / GraphQL
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --paths   # quoted path literals that survive R8 inlining

# Find tracker/analytics SDKs
bash plugins/android-reverse-engineering/skills/tracker-analysis/scripts/find-trackers.sh output/sources/
bash plugins/android-reverse-engineering/skills/tracker-analysis/scripts/find-trackers.sh output/sources/ --firebase
bash plugins/android-reverse-engineering/skills/tracker-analysis/scripts/find-trackers.sh output/sources/ --adjust

# Find advertising SDKs
bash plugins/android-reverse-engineering/skills/ad-analysis/scripts/find-ads.sh output/sources/
bash plugins/android-reverse-engineering/skills/ad-analysis/scripts/find-ads.sh output/sources/ --admob
bash plugins/android-reverse-engineering/skills/ad-analysis/scripts/find-ads.sh output/sources/ --mediation

# Neutralize SDK entry points (decode → patch → rebuild)
bash plugins/android-reverse-engineering/skills/sdk-neutralizer/scripts/decode-apk.sh app.apk -o app-decoded
bash plugins/android-reverse-engineering/skills/sdk-neutralizer/scripts/neutralize.sh app-decoded --all --dry-run
bash plugins/android-reverse-engineering/skills/sdk-neutralizer/scripts/neutralize.sh app-decoded --all
bash plugins/android-reverse-engineering/skills/sdk-neutralizer/scripts/rebuild-apk.sh app-decoded --auto-keystore

# XAPK full round-trip — decode preserves splits, rebuild reassembles XAPK
bash plugins/android-reverse-engineering/skills/sdk-neutralizer/scripts/decode-apk.sh app-bundle.xapk -o app-decoded
# .xapk-origin/ now contains splits/, manifest.json, metadata.json
bash plugins/android-reverse-engineering/skills/sdk-neutralizer/scripts/neutralize.sh app-decoded --all --dry-run
bash plugins/android-reverse-engineering/skills/sdk-neutralizer/scripts/neutralize.sh app-decoded --all
bash plugins/android-reverse-engineering/skills/sdk-neutralizer/scripts/rebuild-apk.sh app-decoded --auto-keystore
# → produces app-decoded-neutralized.xapk with all splits re-signed

# Replay previous patches after re-decoding
bash plugins/android-reverse-engineering/skills/sdk-neutralizer/scripts/neutralize.sh app-decoded --replay
```

### Kotlin name recovery (R8 deobfuscation)

Most real-world Kotlin/KMP apps ship through R8, so the decompiled classes come
out as `a.b.c`. R8 renames the JVM symbols but **cannot strip the Kotlin
metadata strings** — the Kotlin runtime (reflection, coroutines) needs the
original fully-qualified names at runtime. This skill mines those
`@DebugMetadata` / `@Metadata` annotations to rebuild an `obfuscated → real`
class-name map. On a typical app it recovers ~100 % of the
`*Repository` / `*ViewModel` / `*UseCase` / `*Impl` classes you actually want to
read.

```bash
# 1. Build the mapping from the decompiled sources
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/recover-kotlin-names.sh output/sources/ output/names/
#    → output/names/mapping.tsv, mapping.json, by_package/

# 2. Query it: resolve an obfuscated name, search by real name, or grep
#    the sources with each hit annotated with its recovered class name
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/lookup-name.sh output/names/ LoginRepository
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/lookup-name.sh output/names/ -o a.b.c
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/lookup-name.sh output/names/ --grep 'login' output/sources/
```

## Repository Structure

```text
android-reverse-engineering-skill/
├── .claude-plugin/
│   └── marketplace.json                    # Marketplace catalog
├── plugins/
│   └── android-reverse-engineering/
│       ├── .claude-plugin/
│       │   └── plugin.json                 # Plugin manifest
│       ├── skills/
│       │   ├── android-reverse-engineering/ # Core RE skill
│       │   │   ├── SKILL.md                # Core workflow (Phase 0–5)
│       │   │   ├── references/
│       │   │   │   ├── setup-guide.md
│       │   │   │   ├── jadx-usage.md
│       │   │   │   ├── fernflower-usage.md
│       │   │   │   ├── api-extraction-patterns.md
│       │   │   │   ├── kotlin-name-recovery.md
│       │   │   │   ├── third_party_hosts.txt   # denylist for first/third-party bucketing
│       │   │   │   └── call-flow-analysis.md
│       │   │   └── scripts/
│       │   │       ├── check-deps.sh       # Bash
│       │   │       ├── check-deps.ps1      # PowerShell
│       │   │       ├── install-dep.sh
│       │   │       ├── install-dep.ps1
│       │   │       ├── decompile.sh
│       │   │       ├── decompile.ps1
│       │   │       ├── fingerprint.sh          # Phase 0 — pre-decompile triage
│       │   │       ├── recover-kotlin-names.sh # R8 → real Kotlin class names
│       │   │       ├── lookup-name.sh          # query the recovered name map
│       │   │       ├── find-api-calls.sh
│       │   │       └── find-api-calls.ps1
│       │   ├── tracker-analysis/            # Tracker/analytics SDK detection
│       │   │   ├── SKILL.md                # 4-phase workflow
│       │   │   ├── references/
│       │   │   │   ├── tracker-sdk-catalog.md
│       │   │   │   ├── tracker-init-patterns.md
│       │   │   │   └── data-exfiltration-patterns.md
│       │   │   └── scripts/
│       │   │       └── find-trackers.sh
│       │   ├── ad-analysis/                 # Advertising SDK detection
│       │   │   ├── SKILL.md                # 3-phase workflow
│       │   │   ├── references/
│       │   │   │   ├── ad-sdk-catalog.md
│       │   │   │   ├── mediation-patterns.md
│       │   │   │   └── ad-format-patterns.md
│       │   │   └── scripts/
│       │   │       └── find-ads.sh
│       │   └── sdk-neutralizer/             # SDK neutralization for enterprise
│       │       ├── SKILL.md                # 6-phase workflow
│       │       ├── references/
│       │       │   ├── neutralization-guide.md
│       │       │   └── smali-patterns.md
│       │       └── scripts/
│       │           ├── check-neutralize-deps.sh
│       │           ├── decode-apk.sh
│       │           ├── merge-splits.sh
│       │           ├── neutralize.sh
│       │           ├── rebuild-apk.sh
│       │           └── registry-scan.py
│       └── commands/
│           ├── decompile.md                # /decompile slash command
│           ├── find-trackers.md            # /find-trackers slash command
│           ├── find-ads.md                 # /find-ads slash command
│           └── neutralize.md               # /neutralize slash command
├── LICENSE
└── README.md
```

## References

- [jadx — Dex to Java decompiler](https://github.com/skylot/jadx)
- [Fernflower — JetBrains analytical decompiler](https://github.com/JetBrains/fernflower)
- [Vineflower — Fernflower community fork](https://github.com/Vineflower/vineflower)
- [dex2jar — DEX to JAR converter](https://github.com/ThexXTURBOXx/dex2jar)
- [apktool — Android resource decoder](https://apktool.org/)

## Acknowledgments

Thanks to the contributors who have shaped this skill:

- [@tajchert](https://github.com/tajchert) — Phase 0 fingerprinting, R8-resistant Kotlin name recovery (`recover-kotlin-names.sh`, `lookup-name.sh`), and Ktor / Apollo / Koin / HMAC extraction patterns (#16)
- [@philjn](https://github.com/philjn) — Native Windows / PowerShell support (`check-deps.ps1`, `install-dep.ps1`, `decompile.ps1`, `find-api-calls.ps1`) and split/bundled APK detection in `decompile.sh` (#8)
- [@txhno](https://github.com/txhno) — Migration to the maintained [`ThexXTURBOXx/dex2jar`](https://github.com/ThexXTURBOXx/dex2jar) fork (#12)
- [@muqiao215](https://github.com/muqiao215) — Decompile partial-success handling, Fernflower timeout safeguard, intermediate-artifact directory (#10)
- [@kevinaimonster](https://github.com/kevinaimonster) — Chinese localization (`SKILL.md` discovery keywords) (#4)

## Disclaimer

This plugin is provided strictly for **lawful purposes**, including but not limited to:

- Security research and authorized penetration testing
- Interoperability analysis permitted under applicable law (e.g., EU Directive 2009/24/EC, US DMCA §1201(f))
- Malware analysis and incident response
- Educational use and CTF competitions
- Enterprise privacy compliance and data minimisation (GDPR Art. 5(1)(c))
- Authorized internal distribution of sanitized applications

**SDK neutralization** modifies APK bytecode and invalidates the original signature. The resulting APK will fail Play Integrity checks and is intended only for enterprise sideloading via MDM or authorized internal distribution. Using this feature to circumvent digital rights management for unauthorized purposes is prohibited.

**You are solely responsible** for ensuring that your use of this tool complies with all applicable laws, regulations, and terms of service. Unauthorized reverse engineering of software you do not own or do not have permission to analyze may violate intellectual property laws and computer fraud statutes in your jurisdiction.

The authors disclaim any liability for misuse of this tool.

## License

Apache 2.0 — see [LICENSE](LICENSE)
