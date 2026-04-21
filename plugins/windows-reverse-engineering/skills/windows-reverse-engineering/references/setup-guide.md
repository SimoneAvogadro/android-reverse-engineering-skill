# Setup Guide: Dependencies for Windows Reverse Engineering

## Java JDK 17+

Ghidra requires Java 17 or later.

### winget (recommended)

```powershell
winget install Microsoft.OpenJDK.17
```

### Chocolatey

```powershell
choco install openjdk17
```

### Manual (Adoptium)

1. Go to <https://adoptium.net/temurin/releases/?version=17>
2. Download the `.msi` installer for your architecture (x64 or ARM64)
3. Run the installer — it adds Java to PATH automatically

### Verify

```powershell
java -version
# Should show version 17.x or higher
```

---

## Ghidra

Ghidra is the NSA's open-source reverse engineering framework. It decompiles native PE binaries to C pseudocode.

### GitHub Releases (recommended)

1. Go to <https://github.com/NationalSecurityAgency/ghidra/releases/latest>
2. Download `ghidra_<version>_PUBLIC_<date>.zip`
3. Extract to a permanent location (e.g., `C:\Tools\Ghidra`)
4. Set the environment variable:

```powershell
# Set for current user permanently
[System.Environment]::SetEnvironmentVariable('GHIDRA_INSTALL_DIR', 'C:\Tools\Ghidra\ghidra_<version>_PUBLIC', 'User')

# Set for current session
$env:GHIDRA_INSTALL_DIR = 'C:\Tools\Ghidra\ghidra_<version>_PUBLIC'
```

### Chocolatey

```powershell
choco install ghidra
```

### Verify

```powershell
# Check the environment variable
$env:GHIDRA_INSTALL_DIR

# Check the headless analyzer
& "$env:GHIDRA_INSTALL_DIR\support\analyzeHeadless.bat" -help
```

> **Note**: On first run, Ghidra may prompt for agreement. The headless analyzer works without a GUI but requires a writable project directory.

---

## ilspycmd (.NET Decompiler)

ilspycmd is the command-line interface for ILSpy, the open-source .NET decompiler. It decompiles .NET assemblies to C# source.

### Prerequisites

Install the .NET SDK (6.0 or later):

```powershell
# Via winget
winget install Microsoft.DotNet.SDK.8

# Via Chocolatey
choco install dotnet-sdk
```

### Install ilspycmd

```powershell
dotnet tool install -g ilspycmd
```

This installs `ilspycmd` as a global .NET tool. The tool is automatically added to PATH.

### Verify

```powershell
ilspycmd --version
```

### Usage

```powershell
# Decompile entire assembly to C# project
ilspycmd -p -o output_dir MyApp.exe

# Decompile to individual C# files (no project)
ilspycmd -o output_dir MyApp.dll
```

---

## strings / strings2 (optional, recommended)

Extract readable ASCII and Unicode strings from binaries. Essential for finding hardcoded URLs, API keys, and error messages.

### SysInternals strings (Microsoft)

```powershell
# Via winget
winget install Microsoft.Sysinternals.Strings

# Or download directly
# https://learn.microsoft.com/en-us/sysinternals/downloads/strings
```

### strings2 (recommended — finds both ASCII and Unicode)

1. Download from <https://github.com/glmcdona/strings2/releases>
2. Extract to a directory in your PATH (e.g., `C:\Tools\strings2\`)
3. Add to PATH:

```powershell
[System.Environment]::SetEnvironmentVariable('PATH', $env:PATH + ';C:\Tools\strings2', 'User')
```

### Verify

```powershell
strings --help
# or
strings2 --help
```

---

## dumpbin (optional)

dumpbin is a CLI tool for inspecting PE headers, imports, exports, and sections. It ships with Visual Studio C++ Build Tools.

> **Important**: dumpbin requires **Visual Studio C++ Build Tools** to be installed. This is a large download (~2-4 GB). If you don't have Visual Studio, consider using Ghidra's PE analysis instead — it extracts the same information.

### Install Visual Studio C++ Build Tools

1. Download from <https://visualstudio.microsoft.com/visual-cpp-build-tools/>
2. In the installer, select **"Desktop development with C++"**
3. Install (requires admin)

### Find dumpbin

After installation, dumpbin is typically at:
```
C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\<version>\bin\Hostx64\x64\dumpbin.exe
```

To use it, open a **Developer Command Prompt** or **Developer PowerShell**, which adds dumpbin to PATH automatically.

### Verify

```powershell
# From Developer Command Prompt / PowerShell
dumpbin /?
```

### Usage

```powershell
# Show imports
dumpbin /imports MyApp.exe

# Show exports
dumpbin /exports MyLib.dll

# Show headers
dumpbin /headers MyApp.exe

# Show all sections
dumpbin /all MyApp.exe
```

---

## de4dot (optional — .NET deobfuscation)

de4dot is an open-source .NET deobfuscator that can clean up obfuscated assemblies before decompilation.

### Download

1. Go to <https://github.com/de4dot/de4dot/releases>
2. Download the latest release ZIP
3. Extract to `C:\Tools\de4dot\`
4. Add to PATH:

```powershell
[System.Environment]::SetEnvironmentVariable('PATH', $env:PATH + ';C:\Tools\de4dot', 'User')
```

### Usage

```powershell
# Deobfuscate a .NET assembly
de4dot ObfuscatedApp.exe -o CleanApp.exe

# Then decompile the clean version
ilspycmd -p -o output_dir CleanApp.exe
```

---

## Optional Tools

### x64dbg

A free, open-source x86/x64 debugger for Windows. Useful for dynamic analysis.

```powershell
# Via Chocolatey
choco install x64dbg.portable

# Or download from https://x64dbg.com/
```

### PE-bear

A portable PE viewer with a GUI for inspecting headers, sections, and overlays.

Download from <https://github.com/hasherezade/pe-bear/releases>

### Radare2

A powerful command-line reverse engineering framework.

```powershell
choco install radare2
```

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `java: command not found` | Install Java 17+ and ensure it's in PATH |
| `GHIDRA_INSTALL_DIR not set` | Set the environment variable to Ghidra's installation directory |
| `analyzeHeadless` fails to start | Ensure Java 17+ is in PATH and `GHIDRA_INSTALL_DIR` is correct |
| `ilspycmd: command not found` | Run `dotnet tool install -g ilspycmd` and restart your terminal |
| `dotnet: command not found` | Install .NET SDK from https://dotnet.microsoft.com/ |
| Ghidra runs out of memory | Set `JAVA_OPTS="-Xmx4g"` or edit `analyzeHeadless.bat` max heap |
| `dumpbin: command not found` | Open Developer Command Prompt, or install VS C++ Build Tools |
| PowerShell blocks script execution | Run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force` |
| ilspycmd fails on obfuscated .NET | Run `de4dot` first to clean the assembly, then retry |
| Ghidra decompiler produces `undefined` | Binary may be packed — try unpacking with UPX or manual analysis |
