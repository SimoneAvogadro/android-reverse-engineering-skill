# Reverse Engineering & API Extraction — AI Coding Agent Skills

A collection of AI coding agent skills for reverse engineering mobile and desktop applications. Includes **Android** (APK/XAPK/JAR/AAR) and **Windows** (EXE/DLL/.NET) plugins that decompile binaries, extract APIs, trace call flows, and document findings.

Works with **Claude Code**, **OpenAI Codex**, **Cursor**, **GitHub Copilot**, **Cline**, **Windsurf**, **Roo Code**, **Aider**, and **OpenCode**.

---

## 🪟 Windows Reverse Engineering (NEW)

Decompiles Windows EXE/DLL/.NET assemblies and **extracts Win32 API calls**, network endpoints, registry operations, cryptographic usage, and more.

### What it does

- **Auto-detects** binary type (.NET vs native PE) and selects the best decompiler
- **Decompiles** native PE binaries using **Ghidra** headless (C pseudocode output)
- **Decompiles** .NET assemblies using **ILSpy** (ilspycmd) to C# source
- **Extracts and documents APIs**: Win32 calls, WinHTTP/WinINet, Winsock, .NET HttpClient, registry, crypto, COM/WMI
- **Traces call flows** from entry points (WinMain, DllMain, ServiceMain, Main) through to API calls
- **Analyzes** PE structure: imports, exports, sections, strings, security features
- **Detects** persistence mechanisms, process injection patterns, and hardcoded secrets

### Requirements

**Required (at least one decompiler):**
- Java JDK 17+ and [Ghidra](https://github.com/NationalSecurityAgency/ghidra) — for native PE binaries
- [ilspycmd](https://github.com/icsharpcode/ILSpy) (`dotnet tool install -g ilspycmd`) — for .NET assemblies

**Optional (recommended):**
- [strings2](https://github.com/glmcdona/strings2) or SysInternals Strings — extract embedded strings
- dumpbin (Visual Studio C++ Build Tools) — PE header analysis
- [de4dot](https://github.com/de4dot/de4dot) — .NET deobfuscation

### Installation

Inside Claude Code, run:

```
/plugin install windows-reverse-engineering@android-reverse-engineering-skill
```

### Usage

```
/decompile path/to/app.exe
```

The skill auto-detects the binary type and runs the appropriate decompiler. You can also use natural language: "Reverse engineer this DLL", "Extract API calls from this .NET app", "Trace the login flow".

### Manual scripts (PowerShell)

```powershell
# Check dependencies
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/check-deps.ps1

# Install a missing dependency
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/install-dep.ps1 ghidra
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/install-dep.ps1 ilspycmd

# Decompile (auto-detect engine)
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/decompile.ps1 app.exe

# Decompile with specific engine
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/decompile.ps1 -Engine ilspy MyDotNetApp.dll

# Find API calls
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/find-api-calls.ps1 output/sources/
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/find-api-calls.ps1 output/sources/ -Network
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/find-api-calls.ps1 output/sources/ -Urls
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/find-api-calls.ps1 output/sources/ -Process
```

---

## 🤖 Android Reverse Engineering


- **Decompiles** APK, XAPK, JAR, and AAR files using jadx and Fernflower/Vineflower (single engine or side-by-side comparison)
- **Extracts and documents APIs**: Retrofit endpoints, OkHttp calls, hardcoded URLs, auth headers and tokens
- **Traces call flows** from Activities/Fragments through ViewModels and repositories down to HTTP calls
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

### Slash command

```
/decompile path/to/app.apk
```

This runs the full workflow: dependency check, decompilation, and initial structure analysis.

### Natural language

The skill activates on phrases like:

- "Decompile this APK"
- "Reverse engineer this Android app"
- "Extract API endpoints from this app"
- "Follow the call flow from LoginActivity"
- "Analyze this AAR library"

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
```

## Repository Structure

```
android-reverse-engineering-skill/
├── .claude-plugin/
│   └── marketplace.json                    # Marketplace catalog (both plugins)
├── plugins/
│   ├── android-reverse-engineering/        # Android plugin
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   ├── skills/
│   │   │   └── android-reverse-engineering/
│   │   │       ├── SKILL.md
│   │   │       ├── references/
│   │   │       │   ├── setup-guide.md
│   │   │       │   ├── jadx-usage.md
│   │   │       │   ├── fernflower-usage.md
│   │   │       │   ├── api-extraction-patterns.md
│   │   │       │   └── call-flow-analysis.md
│   │   │       └── scripts/
│   │   │           ├── check-deps.sh
│   │   │           ├── install-dep.sh
│   │   │           ├── decompile.sh
│   │   │           └── find-api-calls.sh
│   │   └── commands/
│   │       └── decompile.md
│   └── windows-reverse-engineering/        # Windows plugin (NEW)
│       ├── .claude-plugin/
│       │   └── plugin.json
│       ├── skills/
│       │   └── windows-reverse-engineering/
│       │       ├── SKILL.md                # Core workflow (5 phases)
│       │       ├── references/
│       │       │   ├── setup-guide.md
│       │       │   ├── ghidra-headless-usage.md
│       │       │   ├── ilspy-usage.md
│       │       │   ├── api-extraction-patterns.md
│       │       │   └── call-flow-analysis.md
│       │       └── scripts/
│       │           ├── check-deps.ps1
│       │           ├── install-dep.ps1
│       │           ├── decompile.ps1
│       │           ├── find-api-calls.ps1
│       │           └── ghidra-scripts/
│       │               └── ExportDecompiled.py
│       └── commands/
│           └── decompile.md
├── LICENSE
└── README.md
```

## References

### Android
- [jadx — Dex to Java decompiler](https://github.com/skylot/jadx)
- [Fernflower — JetBrains analytical decompiler](https://github.com/JetBrains/fernflower)
- [Vineflower — Fernflower community fork](https://github.com/Vineflower/vineflower)
- [dex2jar — DEX to JAR converter](https://github.com/pxb1988/dex2jar)
- [apktool — Android resource decoder](https://apktool.org/)

### Windows
- [Ghidra — NSA reverse engineering framework](https://github.com/NationalSecurityAgency/ghidra)
- [ILSpy — .NET decompiler](https://github.com/icsharpcode/ILSpy)
- [de4dot — .NET deobfuscator](https://github.com/de4dot/de4dot)
- [strings2 — Advanced string extraction](https://github.com/glmcdona/strings2)
- [x64dbg — Open source Windows debugger](https://x64dbg.com/)

## Supported Agents

This skill works with all major AI coding agents. Use the universal installer to set up for your agent:

```powershell
# Windows (PowerShell)
.\install.ps1                    # Interactive — choose your agent
.\install.ps1 -Agent cursor      # Install for Cursor
.\install.ps1 -Agent all         # Install for all agents
.\install.ps1 -List              # List supported agents
.\install.ps1 -CheckDeps         # Run dependency check
```

```bash
# Linux / macOS / WSL
./install.sh                     # Interactive
./install.sh --agent codex       # Install for Codex
./install.sh --agent all         # Install for all agents
./install.sh --list              # List supported agents
```

| Agent | Config Files | Auto-Detection |
|---|---|---|
| **Claude Code** | `.claude-plugin/` | Plugin manifest + SKILL.md |
| **OpenAI Codex** | `AGENTS.md` | Reads from repo root |
| **OpenCode** | `AGENTS.md` | Reads from repo root |
| **Cursor** | `.cursor/rules/*.mdc` | Glob-matched + description-based |
| **GitHub Copilot** | `.github/instructions/*.instructions.md` | File-pattern matched |
| **Cline** | `.clinerules/*.md` | Auto-loaded into context |
| **Windsurf** | `.windsurf/rules/*.md` | Auto-loaded by Cascade |
| **Roo Code** | `.roo/rules/*.md` | Auto-loaded, alphabetical order |
| **Aider** | `.aider.conf.yml` → `AGENTS.md` | Loaded via `read:` config |

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
