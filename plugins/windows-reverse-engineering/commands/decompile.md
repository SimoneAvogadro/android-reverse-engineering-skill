---
allowed-tools: Bash, Read, Glob, Grep, Write, Edit
description: Decompile a Windows EXE/DLL/.NET assembly and analyze its structure
user-invocable: true
argument-hint: <path to EXE, DLL, or .NET assembly>
argument: path to EXE, DLL, or .NET assembly file (optional)
---

# /decompile

Decompile a Windows application and perform initial structure analysis.

## Instructions

You are starting the Windows reverse engineering workflow. Follow these steps:

### Step 1: Get the target file

If the user provided a file path as an argument, use that. Otherwise, ask the user for the path to the EXE, DLL, or .NET assembly they want to decompile.

### Step 2: Check PowerShell execution policy

Before running any scripts, ensure PowerShell can execute `.ps1` files. Run:

```powershell
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -eq 'Restricted' -or $policy -eq 'AllSigned') {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    Write-Host "Execution policy updated to RemoteSigned for current user."
}
```

If setting the execution policy fails (e.g., group policy override), fall back to running scripts with:

```powershell
powershell -ExecutionPolicy Bypass -File <script.ps1>
```

### Step 3: Check and install dependencies

Run the dependency check:

```powershell
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/scripts/check-deps.ps1"
```

Parse the output looking for `INSTALL_REQUIRED:` and `INSTALL_OPTIONAL:` lines.

**If required dependencies are missing**, install them one by one:

```powershell
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/scripts/install-dep.ps1" java
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/scripts/install-dep.ps1" ghidra
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/scripts/install-dep.ps1" ilspycmd
```

The install script uses winget, Chocolatey, dotnet tool, or direct GitHub download. If an installer requires admin privileges the user doesn't have, it prints manual instructions (exit code 2). Show those to the user and stop.

**For optional dependencies** (`INSTALL_OPTIONAL:dumpbin`, `INSTALL_OPTIONAL:strings`, etc.), ask the user if they want to install them. Recommend strings for embedded URL/key extraction.

> **Note**: `dumpbin` requires Visual Studio C++ Build Tools. Make the user aware of this requirement if they want to use it.

After any installations, re-run `check-deps.ps1` to verify. Do not proceed until all required dependencies pass.

### Step 4: Decompile

Run the decompile script on the target file:

```powershell
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/scripts/decompile.ps1" <file>
```

The script auto-detects the binary type:
- **.NET assembly** (imports `mscoree.dll`, has CLI header) → decompiles with `ilspycmd` to C# source
- **Native PE** (C/C++ compiled EXE/DLL/SYS) → decompiles with Ghidra headless to C pseudocode

The user can override detection with `-Engine ghidra` or `-Engine ilspy`.

For packed/obfuscated binaries (if the user mentions it or you detect high-entropy sections), note this and suggest manual unpacking before decompilation.

### Step 5: Analyze structure

After decompilation completes:

1. Review the PE header summary from the decompile output (architecture, subsystem, entry point)
2. Review the import table — which DLLs and functions does the binary use?
3. Review the export table (for DLLs) — what does the binary expose?
4. List the top-level source structure (packages/namespaces for .NET, function groups for native)
5. Identify the app's entry point and architecture pattern
6. Report a summary to the user

### Step 6: Offer next steps

Tell the user what they can do next:
- **Trace call flows**: "I can follow the execution flow from the entry point to network/API calls"
- **Extract APIs**: "I can search for all Win32 API calls, network endpoints, registry operations, and hardcoded secrets"
- **Analyze specific functions**: "Point me to a specific function or class to analyze in detail"
- **Re-decompile with a different engine**: If auto-detection chose the wrong engine, offer to re-run

Refer to the full skill documentation in `${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/SKILL.md` for the complete workflow.
