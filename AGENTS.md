# Reverse Engineering Skills

This repository provides AI-assisted reverse engineering tools for **Windows** (EXE/DLL/.NET) and **Android** (APK/XAPK/JAR/AAR) binaries. It includes decompilation scripts, API extraction, call flow tracing, and structured output documentation.

All scripts and references live under `plugins/`. The instructions below tell you how to use them.

---

## Windows Reverse Engineering

Decompile Windows EXE, DLL, SYS, and .NET assemblies using Ghidra (native PE → C pseudocode) and ILSpy (managed .NET → C# source). Auto-detects binary type.

### Dependencies

Run the dependency checker first:

```powershell
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/check-deps.ps1
```

**Required (at least one decompiler):**
- Java JDK 17+ and Ghidra (set `GHIDRA_INSTALL_DIR` env var) — for native PE
- ilspycmd (`dotnet tool install -g ilspycmd`) — for .NET assemblies

**Optional:** strings/strings2, dumpbin (requires Visual Studio C++ Build Tools), de4dot (.NET deobfuscator)

Install missing dependencies:
```powershell
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/install-dep.ps1 <dep>
# Available: java, ghidra, ilspycmd, dotnet-sdk, strings, dumpbin, de4dot
```

### PowerShell Execution Policy

If scripts are blocked, auto-fix with:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
```
If group policy prevents this, prefix all script calls with `powershell -ExecutionPolicy Bypass -File`.

### Workflow

#### Phase 1: Verify Dependencies
```powershell
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/check-deps.ps1
```
Output includes `INSTALL_REQUIRED:<dep>` and `INSTALL_OPTIONAL:<dep>` lines. Install any required deps before proceeding.

#### Phase 2: Decompile
```powershell
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/decompile.ps1 [OPTIONS] <file>
```
Options:
- `-Output <dir>` — custom output directory (default: `<filename>-decompiled`)
- `-Engine auto|ghidra|ilspy` — decompiler engine (default: `auto`)
- `-NoStrings` — skip strings extraction

Auto-detection: .NET assemblies (CLI header present) → ILSpy. Native PE → Ghidra. The script reads the PE header to determine binary type.

**Output structure (Ghidra):**
```
<output>/decompiled/   — C pseudocode per function
<output>/imports.txt   — import table
<output>/exports.txt   — export table
<output>/strings.txt   — extracted strings
<output>/summary.txt   — analysis summary
```

**Output structure (ILSpy):**
```
<output>/sources/      — C# source files with .csproj
```

#### Phase 3: Analyze Structure
- Review PE headers (architecture, subsystem, entry point, security features)
- Survey import table — reveals which DLLs/APIs the binary uses
- For .NET: examine namespace structure, referenced assemblies, DI container setup
- For native: group functions by purpose, identify entry points, look for C++ vtables

#### Phase 4: Trace Call Flows
- Start from entry points: `WinMain`, `main`, `DllMain`, `ServiceMain`, `DriverEntry` (native) or `static void Main()`, `Program.cs`, `Startup.cs` (.NET)
- Follow initialization chain → user action handlers → business logic → API calls
- Map dependency injection in .NET (`AddScoped`, `AddSingleton`, `AddTransient`)
- Handle obfuscated code: use framework type names and string refs as anchors

#### Phase 5: Extract APIs
```powershell
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/find-api-calls.ps1 <output>/sources/ [OPTIONS]
```
Options: `-Network`, `-Registry`, `-FileSystem`, `-Process`, `-Crypto`, `-Com`, `-Services`, `-Urls`, `-Auth`, `-Persistence`

Document each API call:
```markdown
### `FunctionName` (DLL: source.dll)
- **Source**: filename.c:42
- **Category**: Network / Registry / File I/O / Process / Crypto
- **Parameters**: param1: value, param2: value
- **Called from**: Main → InitNetwork → SendData → WinHttpSendRequest
- **Purpose**: Description
```

### Reference Documentation
- `plugins/windows-reverse-engineering/skills/windows-reverse-engineering/references/setup-guide.md`
- `plugins/windows-reverse-engineering/skills/windows-reverse-engineering/references/ghidra-headless-usage.md`
- `plugins/windows-reverse-engineering/skills/windows-reverse-engineering/references/ilspy-usage.md`
- `plugins/windows-reverse-engineering/skills/windows-reverse-engineering/references/api-extraction-patterns.md`
- `plugins/windows-reverse-engineering/skills/windows-reverse-engineering/references/call-flow-analysis.md`

---

## Android Reverse Engineering

Decompile Android APK, XAPK, JAR, and AAR files using jadx and Fernflower/Vineflower. Extract Retrofit endpoints, OkHttp calls, hardcoded URLs, and authentication patterns.

### Dependencies

```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.sh
```

**Required:** Java JDK 17+, jadx
**Optional:** Fernflower/Vineflower, dex2jar, apktool

Install missing:
```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh <dep>
```

### Workflow

#### Phase 1: Verify Dependencies
```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.sh
```

#### Phase 2: Decompile
```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh [OPTIONS] <file>
```
Options:
- `--output <dir>` — custom output directory
- `--engine jadx|fernflower|both` — decompiler engine (default: `jadx`)
- `--deobf` — enable deobfuscation

#### Phase 3: Analyze Structure
- Review AndroidManifest.xml for activities, services, receivers, permissions
- Survey package structure and identify architecture patterns (MVP, MVVM, Clean Architecture)
- Find application entry points (Application class, main Activity, ContentProviders)

#### Phase 4: Trace Call Flows
- Start from Activity/Fragment → ViewModel → Repository → API client
- Follow Dagger/Hilt dependency injection
- Map Retrofit interface → OkHttp interceptors → actual HTTP calls

#### Phase 5: Extract APIs
```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh <output>/sources/ [OPTIONS]
```
Options: `--retrofit`, `--okhttp`, `--urls`, `--auth`, `--volley`

### Reference Documentation
- `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/setup-guide.md`
- `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/jadx-usage.md`
- `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/fernflower-usage.md`
- `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/api-extraction-patterns.md`
- `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/call-flow-analysis.md`
