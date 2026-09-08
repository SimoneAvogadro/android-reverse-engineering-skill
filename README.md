# Android Reverse Engineering & API Extraction

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![GitHub stars](https://img.shields.io/github/stars/SimoneAvogadro/android-reverse-engineering-skill?style=social)](https://github.com/SimoneAvogadro/android-reverse-engineering-skill/stargazers) [![GitHub last commit](https://img.shields.io/github/last-commit/SimoneAvogadro/android-reverse-engineering-skill)](https://github.com/SimoneAvogadro/android-reverse-engineering-skill/commits/master)

A skill for Claude Code and **Cursor** that decompiles Android APK/XAPK/JAR/AAR files and **extracts the HTTP APIs** used by the app (Retrofit endpoints, OkHttp calls, hardcoded URLs, authentication patterns) so you can document and reproduce them without the original source code.

> **First-class Kotlin support**: modern Android apps are Kotlin/KMP, heavily obfuscated with R8. This skill recovers the **original Kotlin class names** from metadata R8 cannot strip, and extracts APIs from **Ktor**, **Apollo (GraphQL)** and **Koin**, not just the classic Retrofit/OkHttp stack. See [Kotlin name recovery](#kotlin-name-recovery-r8-deobfuscation) below.

> **Cross-platform scripts**: Bash scripts on Linux/macOS and native PowerShell (`*.ps1`) on Windows cover the full workflow: fingerprint, decompile, API extraction, and Kotlin name recovery. See [Usage](#usage) for examples on each platform.

# Table of Contents

- [What it does](#what-it-does)
- [Requirements](#requirements)
- [Installation](#installation)
  - [Claude Code](#claude-code)
  - [Cursor](#cursor)
- [Usage](#usage)
- [Repository Structure](#repository-structure)
- [References](#references)
- [Acknowledgments](#acknowledgments)
- [Disclaimer](#disclaimer)
- [License](#license)

# What it does

| Capability | Description |
|------------|-------------|
| **Fingerprint first (Phase 0)** | Triage an APK/XAPK in seconds: detect the framework (Flutter / React Native / Cordova / Xamarin / native-Kotlin), HTTP stack, obfuscation level and native libs *before* spending time on a full decompile |
| **Decompile** | APK, XAPK, JAR, and AAR files using jadx and Fernflower/Vineflower (single engine or side-by-side comparison) |
| **Recover Kotlin names** | Rebuild original `*Repository` / `*ViewModel` / `*UseCase` class names from R8-obfuscated binaries using Kotlin metadata that R8 cannot strip |
| **Extract APIs** | Retrofit, OkHttp, Volley **and modern Kotlin/KMP stacks: Ktor, Apollo (GraphQL), Koin DI**; endpoints, hardcoded URLs, auth headers, tokens and HMAC request-signing schemes |
| **Trace call flows** | From Activities/Fragments through ViewModels and repositories down to HTTP calls |
| **Analyze structure** | Manifest, packages, architecture patterns |
| **Handle obfuscation** | R8-resistant path/URL extraction plus strategies for navigating ProGuard/R8 output |

# Requirements

**Required:**

- Java JDK 17+
- [jadx](https://github.com/skylot/jadx) (CLI)

**Optional (recommended):**

- [Vineflower](https://github.com/Vineflower/vineflower) or [Fernflower](https://github.com/JetBrains/fernflower): better output on complex Java code
- [dex2jar](https://github.com/ThexXTURBOXx/dex2jar): needed to use Fernflower on APK/DEX files

See `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/setup-guide.md` for detailed installation instructions.

# Installation

## Claude Code

### From GitHub (recommended)

Inside Claude Code, run:

```text
/plugin marketplace add SimoneAvogadro/android-reverse-engineering-skill
/plugin install android-reverse-engineering@android-reverse-engineering-skill
```

The skill will be permanently available in all future sessions.

### From a local clone

```bash
git clone https://github.com/SimoneAvogadro/android-reverse-engineering-skill.git
```

Then in Claude Code:

```text
/plugin marketplace add /path/to/android-reverse-engineering-skill
/plugin install android-reverse-engineering@android-reverse-engineering-skill
```

## Cursor

Cursor loads **project skills** from `.cursor/skills/` in the **workspace root** — the folder you open in Cursor, not every repo on disk.

Clone this repository, then pick one setup:

| Goal | What to do |
|------|------------|
| **Use the skill here** (simplest) | Open this repo as your Cursor workspace. Put APKs anywhere on disk and reference them by path. |
| **Use the skill in another project** | Copy (or git submodule) **both** `.cursor/skills/android-reverse-engineering/` **and** `plugins/android-reverse-engineering/` into that project's repo root, then open **that** project in Cursor. The skill's `SKILL.md` references scripts under `plugins/…` relative to the workspace root — copying only `SKILL.md` is not enough. |
| **Both projects at once** | Add this repo and your other project to a [multi-root workspace](https://code.visualstudio.com/docs/editor/workspaces#_multiroot-workspaces). |
| **All projects (advanced)** | Install under `~/.cursor/skills/android-reverse-engineering/`, but adjust script paths in `SKILL.md` to a fixed location on disk (e.g. where you cloned this repo). |

The project skill lives at `.cursor/skills/android-reverse-engineering/` and points to the shared scripts under `plugins/android-reverse-engineering/skills/android-reverse-engineering/`.

1. Ensure **Java 17+**, **jadx**, and optionally **dex2jar** / **Vineflower** are on your PATH (see [setup-guide](plugins/android-reverse-engineering/skills/android-reverse-engineering/references/setup-guide.md)).
2. Verify dependencies (run from the workspace root that contains `plugins/`):
   - **Linux / macOS:** `bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.sh`
   - **Windows:** `& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.ps1`
3. Invoke via `@android-reverse-engineering` or phrases like "decompile this APK".

Unlike Claude Code, Cursor has no global `/plugin install` — the skill is available only in workspaces where `.cursor/skills/android-reverse-engineering/` is present (unless you use the personal-skill path above).

# Usage

## Slash command

```text
/decompile path/to/app.apk
```

This runs the full workflow: dependency check, decompilation, and initial structure analysis.

## Natural language

The skill activates on phrases like:

- "Decompile this APK"
- "Reverse engineer this Android app"
- "Extract API endpoints from this app"
- "Follow the call flow from LoginActivity"
- "Analyze this AAR library"

## Manual scripts (bash on Linux/macOS)

```bash
# Check dependencies
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.sh

# Install a missing dependency (auto-detects OS and package manager)
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh jadx
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh vineflower

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

# Find API calls (defaults to a full scan across every supported stack)
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --retrofit
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --urls

# Modern Kotlin/KMP stacks and obfuscation-resistant extraction
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --ktor    # Ktor client
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --apollo  # Apollo / GraphQL
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh output/sources/ --paths   # quoted path literals that survive R8 inlining
```

## Manual scripts (PowerShell on Windows)

```powershell
# Check dependencies
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.ps1

# Fingerprint before decompiling (Phase 0)
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/fingerprint.ps1 app.apk

# Decompile
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.ps1 app.apk
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.ps1 -Engine both -Deobf app.apk

# Find API calls
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.ps1 output/sources/
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.ps1 output/sources/ -Ktor -Apollo -Paths

# Kotlin name recovery
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/recover-kotlin-names.ps1 output/sources output/names
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/lookup-name.ps1 output/names LoginRepository
```

## Kotlin name recovery (R8 deobfuscation)

Most real-world Kotlin/KMP apps ship through R8, so the decompiled classes come out as `a.b.c`. R8 renames the JVM symbols but **cannot strip the Kotlin metadata strings**; the Kotlin runtime (reflection, coroutines) needs the original fully-qualified names at runtime. This skill mines those `@DebugMetadata` / `@Metadata` annotations to rebuild an `obfuscated → real` class-name map. On a typical app it recovers ~100 % of the `*Repository` / `*ViewModel` / `*UseCase` / `*Impl` classes you actually want to read.

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

# Repository Structure

```text
android-reverse-engineering-skill/
├── .claude-plugin/
│   └── marketplace.json                    # Marketplace catalog
├── plugins/
│   └── android-reverse-engineering/
│       ├── .claude-plugin/
│       │   └── plugin.json                 # Plugin manifest
│       ├── skills/
│       │   └── android-reverse-engineering/
│       │       ├── SKILL.md                # Core workflow (Phase 0–5)
│       │       ├── references/
│       │       │   ├── setup-guide.md
│       │       │   ├── jadx-usage.md
│       │       │   ├── fernflower-usage.md
│       │       │   ├── api-extraction-patterns.md
│       │       │   ├── kotlin-name-recovery.md
│       │       │   ├── third_party_hosts.txt   # denylist for first/third-party bucketing
│       │       │   └── call-flow-analysis.md
│       │       └── scripts/
│       │           ├── check-deps.sh       # Bash
│       │           ├── check-deps.ps1      # PowerShell
│       │           ├── install-dep.sh
│       │           ├── install-dep.ps1
│       │           ├── decompile.sh
│       │           ├── decompile.ps1
│       │           ├── fingerprint.sh          # Phase 0: pre-decompile triage
│       │           ├── fingerprint.ps1
│       │           ├── recover-kotlin-names.sh # R8 → real Kotlin class names
│       │           ├── recover-kotlin-names.ps1
│       │           ├── recover_kotlin_names.py
│       │           ├── lookup-name.sh          # query the recovered name map
│       │           ├── lookup-name.ps1
│       │           ├── lookup_names.py
│       │           ├── find-api-calls.sh
│       │           └── find-api-calls.ps1
│       └── commands/
│           └── decompile.md                # /decompile slash command
├── .cursor/
│   └── skills/
│       └── android-reverse-engineering/
│           └── SKILL.md                    # Cursor project skill (thin wrapper)
├── LICENSE
└── README.md
```

# References

- [jadx: Dex to Java decompiler](https://github.com/skylot/jadx)
- [Fernflower: JetBrains analytical decompiler](https://github.com/JetBrains/fernflower)
- [Vineflower: Fernflower community fork](https://github.com/Vineflower/vineflower)
- [dex2jar: DEX to JAR converter](https://github.com/ThexXTURBOXx/dex2jar)
- [apktool: Android resource decoder](https://apktool.org/)

# Acknowledgments

Thanks to the contributors who have shaped this skill:

- [@tajchert](https://github.com/tajchert): Phase 0 fingerprinting, R8-resistant Kotlin name recovery (`recover-kotlin-names.sh`, `lookup-name.sh`), and Ktor / Apollo / Koin / HMAC extraction patterns (#16)
- [@philjn](https://github.com/philjn): Native Windows / PowerShell support (`check-deps.ps1`, `install-dep.ps1`, `decompile.ps1`, `find-api-calls.ps1`) and split/bundled APK detection in `decompile.sh` (#8)
- [@txhno](https://github.com/txhno): Migration to the maintained [`ThexXTURBOXx/dex2jar`](https://github.com/ThexXTURBOXx/dex2jar) fork (#12)
- [@muqiao215](https://github.com/muqiao215): Decompile partial-success handling, Fernflower timeout safeguard, intermediate-artifact directory (#10)
- [@kevinaimonster](https://github.com/kevinaimonster): Chinese localization (`SKILL.md` discovery keywords) (#4)

# Disclaimer

This plugin is provided strictly for **lawful purposes**, including but not limited to:

- Security research and authorized penetration testing
- Interoperability analysis permitted under applicable law (e.g., EU Directive 2009/24/EC, US DMCA §1201(f))
- Malware analysis and incident response
- Educational use and CTF competitions

**You are solely responsible** for ensuring that your use of this tool complies with all applicable laws, regulations, and terms of service. Unauthorized reverse engineering of software you do not own or do not have permission to analyze may violate intellectual property laws and computer fraud statutes in your jurisdiction.

The authors disclaim any liability for misuse of this tool.

# License

Apache 2.0; see [LICENSE](LICENSE)
