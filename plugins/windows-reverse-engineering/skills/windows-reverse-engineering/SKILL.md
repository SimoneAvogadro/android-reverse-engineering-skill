---
description: Decompile Windows EXE, DLL, and .NET assemblies using Ghidra or ILSpy. Reverse engineer Windows apps, extract Win32 API calls, network endpoints, registry operations, and trace call flows from entry points to network layer. Use when the user wants to decompile, analyze, or reverse engineer Windows binaries, find API endpoints, or follow call flows.
trigger: decompile EXE|decompile DLL|reverse engineer Windows|extract API|analyze Windows|ghidra|ilspy|follow call flow|decompile .NET|Windows reverse engineering|find API endpoints|PE analysis|Win32 API
---

# Windows Reverse Engineering

Decompile Windows EXE, DLL, SYS, and .NET assemblies using Ghidra (headless) and ILSpy (ilspycmd), trace call flows through application code, and produce structured documentation of extracted APIs — Win32 calls, network endpoints, registry operations, cryptographic usage, and more.

Two decompiler engines are supported:
- **Ghidra** — for native C/C++ PE binaries (produces C pseudocode)
- **ILSpy (ilspycmd)** — for .NET assemblies (produces C# source)

The skill auto-detects the binary type and selects the appropriate engine.

## Prerequisites

This skill requires the following to be installed:

**Required (at least one decompiler):**
- **Java JDK 17+** — needed by Ghidra
- **Ghidra** — for native PE decompilation (set `GHIDRA_INSTALL_DIR` environment variable)
- **ilspycmd** — for .NET assembly decompilation (install via `dotnet tool install -g ilspycmd`)

**Optional (recommended):**
- **strings / strings2** — extract embedded strings from binaries
- **dumpbin** — PE header and import/export analysis (requires Visual Studio C++ Build Tools)
- **de4dot** — .NET deobfuscator for obfuscated assemblies
- **x64dbg** — dynamic debugging (manual use)

Run the dependency checker to verify:

```powershell
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/scripts/check-deps.ps1"
```

If anything is missing, follow the installation instructions in `${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/references/setup-guide.md`.

## PowerShell Execution Policy

All scripts in this skill are PowerShell `.ps1` files. If the system execution policy blocks script execution, automatically adjust it:

```powershell
# Check current policy
$policy = Get-ExecutionPolicy -Scope CurrentUser

# Auto-fix if restricted
if ($policy -eq 'Restricted' -or $policy -eq 'AllSigned') {
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    } catch {
        # Group policy may prevent changes — use Bypass flag per invocation
        # Run all scripts as: powershell -ExecutionPolicy Bypass -File <script.ps1>
    }
}
```

If `Set-ExecutionPolicy` fails due to group policy, run all scripts with:
```powershell
powershell -ExecutionPolicy Bypass -File <script.ps1> [args]
```

## Workflow

### Phase 1: Verify and Install Dependencies

Before decompiling, confirm that the required tools are available — and install any that are missing.

**Action**: Run the dependency check script.

```powershell
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/scripts/check-deps.ps1"
```

The output contains machine-readable lines:
- `INSTALL_REQUIRED:<dep>` — must be installed before proceeding
- `INSTALL_OPTIONAL:<dep>` — recommended but not blocking

**If required dependencies are missing** (exit code 1), install them automatically:

```powershell
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/scripts/install-dep.ps1" <dep>
```

The install script detects available package managers (winget, Chocolatey, dotnet), then:
- Installs without admin when possible (user-local installs, dotnet global tools)
- Uses winget or Chocolatey when available
- If admin is needed but unavailable, it prints the exact manual command and exits with code 2 — show these instructions to the user

**For optional dependencies**, ask the user if they want to install them.

> **Important**: `dumpbin` requires **Visual Studio C++ Build Tools** to be installed. If the user wants PE import/export analysis via dumpbin, they must install the Build Tools from https://visualstudio.microsoft.com/visual-cpp-build-tools/. Alternatively, Ghidra can extract the same information.

After installation, re-run `check-deps.ps1` to confirm everything is in place. Do not proceed to Phase 2 until at least one decompiler (Ghidra or ilspycmd) is available.

### Phase 2: Detect and Decompile

Use the decompile wrapper script to process the target file. The script auto-detects the binary type and selects the appropriate engine.

**Action**: Run the decompile script.

```powershell
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/scripts/decompile.ps1" [OPTIONS] <file>
```

Options:
- `-Output <dir>` — Custom output directory (default: `<filename>-decompiled`)
- `-Engine auto|ghidra|ilspy` — Decompiler engine (default: `auto`)
- `-NoStrings` — Skip strings extraction (faster)

**Auto-detection logic**:

| Binary Type | Detection | Engine |
|---|---|---|
| .NET assembly (C#/VB.NET/F#) | Imports `mscoree.dll`, has CLI header | `ilspy` |
| Native C/C++ EXE/DLL | Standard PE without .NET metadata | `ghidra` |
| Kernel driver (.sys) | PE with `native` subsystem | `ghidra` |
| Packed/obfuscated | High-entropy `.text` section | Warn user, attempt `ghidra` |

**Engine selection strategy**:

| Situation | Engine |
|---|---|
| .NET assembly (any) | `ilspy` — produces clean C# source |
| Native EXE/DLL | `ghidra` — produces C pseudocode |
| .NET but obfuscated (Dotfuscator, ConfuserEx) | Run `de4dot` first, then `ilspy` |
| Quick overview of imports only | Skip decompilation, use `dumpbin /imports` |
| Mixed-mode .NET (native + managed) | `ghidra` for native, `ilspy` for managed |

**ILSpy output**:
- `<output>/sources/` — Decompiled C# source files with project structure
- `<output>/sources/*.csproj` — Reconstructed project file

**Ghidra output**:
- `<output>/decompiled/` — C pseudocode files per function
- `<output>/imports.txt` — Import table listing
- `<output>/exports.txt` — Export table listing (DLLs)
- `<output>/strings.txt` — Extracted string references

See `${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/references/ghidra-headless-usage.md` and `${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/references/ilspy-usage.md` for the full CLI references.

### Phase 3: Analyze Structure

Navigate the decompiled output to understand the application's architecture.

**Actions**:

1. **Review PE headers** from the decompile output or run separately:
   - Architecture: x86, x64, ARM64
   - Subsystem: console, GUI, driver, native
   - Entry point address
   - Compile timestamp
   - Check for ASLR, DEP, code signing

2. **Survey the import table** — this is the single most revealing artifact:
   - `kernel32.dll` — file I/O, process management, memory
   - `user32.dll` — GUI, window messages, clipboard
   - `advapi32.dll` — registry, services, security
   - `ws2_32.dll` / `winhttp.dll` / `wininet.dll` — networking
   - `crypt32.dll` / `bcrypt.dll` — cryptography
   - `ole32.dll` / `oleaut32.dll` — COM/OLE
   - `mscoree.dll` — .NET runtime
   - Unusual DLLs may indicate specific libraries or custom functionality

3. **Survey the export table** (for DLLs):
   - What functions does this DLL expose?
   - Are exports named or ordinal-only (indicates possible evasion)?

4. **For .NET assemblies**, examine:
   - Namespace structure under `<output>/sources/`
   - Referenced assemblies (NuGet packages used)
   - Look for namespaces containing `Api`, `Http`, `Client`, `Service`, `Data`, `Repository`
   - Identify the DI container setup (Startup.cs, Program.cs)

5. **For native binaries**, examine:
   - Top-level function list from Ghidra output
   - Group functions by calling convention and purpose
   - Identify the main entry point and initialization routines
   - Look for C++ class structures (vtables, RTTI)

6. **Identify the architecture pattern**:
   - **WinForms/WPF**: look for `Form`, `Window`, `UserControl` classes
   - **ASP.NET**: look for `Controller`, `Startup`, `Program` classes
   - **Windows Service**: look for `ServiceBase`, `OnStart`, `OnStop`
   - **Native GUI**: look for `CreateWindowEx`, `RegisterClassEx`, `WndProc`
   - **Console**: look for `Main` with argument parsing

### Phase 4: Trace Call Flows

Follow execution paths from entry points down to API calls.

**Actions**:

1. **Start from entry points**:
   - **Native**: `WinMain`, `wWinMain`, `main`, `DllMain`, `ServiceMain`, `DriverEntry`
   - **.NET**: `static void Main()`, `Program.cs`, `Startup.cs`

2. **Follow the initialization chain**:
   - Native: global constructors → `WinMain` → window creation → message loop
   - .NET: `Main()` → `HostBuilder` → dependency injection → `Startup.ConfigureServices()`

3. **Trace user actions**:
   - **Native GUI**: `WndProc` → `WM_COMMAND` handler → business logic → API calls
   - **WinForms**: button click event → method → service call → HTTP request
   - **.NET Web**: HTTP request → Controller → Service → Repository → external API

4. **Map dependency injection** (.NET):
   - Find `AddScoped`, `AddSingleton`, `AddTransient` registrations
   - Trace interface → implementation bindings
   - Follow `IHttpClientFactory` registrations for named HTTP clients

5. **Handle obfuscated code**:
   - **Native**: stripped symbols — use import calls and string refs as anchors
   - **.NET obfuscated**: run `de4dot` first, then string literals and framework types remain readable
   - **Packed**: detect UPX or custom packers — suggest dynamic analysis or manual unpacking

See `${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/references/call-flow-analysis.md` for detailed techniques.

### Phase 5: Extract and Document APIs

Find all API calls and produce structured documentation.

**Action**: Run the API search script for a broad sweep.

```powershell
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/scripts/find-api-calls.ps1" <output>/sources/
```

Targeted searches:
```powershell
# Only network calls
powershell -ExecutionPolicy Bypass -File "..." <output>/sources/ --network

# Only registry operations
powershell -ExecutionPolicy Bypass -File "..." <output>/sources/ --registry

# Only hardcoded URLs and secrets
powershell -ExecutionPolicy Bypass -File "..." <output>/sources/ --urls

# Only authentication patterns
powershell -ExecutionPolicy Bypass -File "..." <output>/sources/ --auth

# Only process manipulation (injection indicators)
powershell -ExecutionPolicy Bypass -File "..." <output>/sources/ --process
```

Then, for each discovered API call, read the surrounding source code to extract:
- API function name and DLL
- Parameters and their values/sources
- Return value handling
- Where it's called from (the call chain from Phase 4)
- Purpose in the application's workflow

**Document each API interaction** using this format:

```markdown
### `FunctionName` (source DLL)

- **Source**: `filename.c:42` or `Namespace.ClassName` (ClassName.cs:42)
- **Category**: Network / Registry / File I/O / Process / Crypto / COM
- **Parameters**:
  - `param1`: value or source
  - `param2`: value or source
- **Return handling**: checked / ignored / stored in `variable`
- **Called from**: `Main → InitNetwork → HttpClient → WinHttpSendRequest`
- **Purpose**: Sends user credentials to remote server
```

For network endpoints specifically:

```markdown
### `POST https://api.example.com/v1/auth/login`

- **Source**: `NetworkManager.cs:87`
- **Method**: POST (via HttpClient)
- **Headers**: `Authorization: Bearer <token>`, `Content-Type: application/json`
- **Request body**: `{ "username": "string", "password": "string" }`
- **Response type**: `LoginResponse { token: string, userId: int }`
- **Called from**: `LoginForm.btnLogin_Click → AuthService.Login → HttpClient.PostAsync`
```

See `${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/references/api-extraction-patterns.md` for Windows-specific search patterns and the full documentation template.

## Output

At the end of the workflow, deliver:

1. **Decompiled source** in the output directory (C pseudocode or C# source)
2. **PE analysis summary** — architecture, imports, exports, sections, security features
3. **Architecture summary** — app structure, main namespaces/modules, pattern used
4. **API documentation** — all discovered Win32/network/registry/crypto calls in the format above
5. **Call flow map** — key paths from entry point to interesting API calls (especially networking and persistence)

## References

- `${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/references/setup-guide.md` — Installing Java, Ghidra, ILSpy, strings, and optional tools on Windows
- `${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/references/ghidra-headless-usage.md` — Ghidra headless CLI and scripting reference
- `${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/references/ilspy-usage.md` — ilspycmd CLI options and .NET decompilation workflows
- `${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/references/api-extraction-patterns.md` — Windows-specific search patterns and documentation template
- `${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/references/call-flow-analysis.md` — Techniques for tracing call flows in Windows binaries
