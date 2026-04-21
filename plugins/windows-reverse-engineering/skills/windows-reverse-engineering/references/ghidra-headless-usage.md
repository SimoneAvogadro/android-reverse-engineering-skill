# Ghidra Headless Analyzer CLI Reference

## Overview

Ghidra's Headless Analyzer (`analyzeHeadless.bat` on Windows) runs Ghidra analysis and scripting without the GUI. It imports binaries, performs auto-analysis, and can run custom scripts to export decompiled code.

## Basic Usage

```powershell
& "$env:GHIDRA_INSTALL_DIR\support\analyzeHeadless.bat" <projectDir> <projectName> [OPTIONS]
```

- `<projectDir>` — Directory where the Ghidra project will be created
- `<projectName>` — Name of the Ghidra project

## Key Options

| Option | Description |
|---|---|
| `-import <file>` | Import a binary file into the project |
| `-process <file>` | Process an already-imported file |
| `-postScript <script>` | Run a script after analysis completes |
| `-preScript <script>` | Run a script before analysis |
| `-scriptPath <dir>` | Directory containing your scripts |
| `-deleteProject` | Delete the project after processing |
| `-noanalysis` | Skip auto-analysis (useful if re-running scripts only) |
| `-processor <langID>` | Override architecture detection (e.g., `x86:LE:64:default`) |
| `-analysisTimeoutPerFile <seconds>` | Timeout for analysis per file |
| `-scriptlog <file>` | Write script output to a log file |
| `-overwrite` | Overwrite existing files in the project |
| `-recursive` | Import all files from a directory recursively |

## Common Workflows

### Decompile to C pseudocode (full workflow)

```powershell
$projectDir = "C:\GhidraProjects"
$projectName = "MyProject"
$scriptPath = "${CLAUDE_PLUGIN_ROOT}\skills\windows-reverse-engineering\scripts\ghidra-scripts"

& "$env:GHIDRA_INSTALL_DIR\support\analyzeHeadless.bat" `
    $projectDir $projectName `
    -import "C:\targets\app.exe" `
    -scriptPath $scriptPath `
    -postScript "ExportDecompiled.py" `
    -deleteProject
```

### Batch import multiple files

```powershell
& "$env:GHIDRA_INSTALL_DIR\support\analyzeHeadless.bat" `
    $projectDir $projectName `
    -import "C:\targets\" `
    -recursive `
    -scriptPath $scriptPath `
    -postScript "ExportDecompiled.py"
```

### Re-run script without re-analyzing

```powershell
& "$env:GHIDRA_INSTALL_DIR\support\analyzeHeadless.bat" `
    $projectDir $projectName `
    -process "app.exe" `
    -noanalysis `
    -scriptPath $scriptPath `
    -postScript "ExportDecompiled.py"
```

## Custom Export Scripts

This skill includes `ExportDecompiled.py`, a Jython script that:

1. Decompiles all functions to C pseudocode files
2. Exports the import table
3. Exports the export table (for DLLs)
4. Exports all string references

The script is located at:
```
${CLAUDE_PLUGIN_ROOT}/skills/windows-reverse-engineering/scripts/ghidra-scripts/ExportDecompiled.py
```

### Writing Custom Ghidra Scripts

Ghidra scripts use **Jython (Python 2.7)** with access to the Ghidra API:

```python
# @category Export
# @description Example: list all functions and their addresses

fm = currentProgram.getFunctionManager()
functions = fm.getFunctions(True)  # True = forward iteration

for func in functions:
    print("{} @ {}".format(func.getName(), func.getEntryPoint()))
```

Key Ghidra API classes:
- `currentProgram` — the loaded binary
- `currentProgram.getFunctionManager()` — access functions
- `currentProgram.getMemory()` — access memory/sections
- `currentProgram.getSymbolTable()` — access symbols
- `currentProgram.getListing()` — access instructions
- `DecompInterface` — decompile functions to C

## Architecture Detection

Ghidra auto-detects the processor for most PE files. Override when needed:

| Architecture | Processor ID |
|---|---|
| x86 32-bit | `x86:LE:32:default` |
| x86 64-bit | `x86:LE:64:default` |
| ARM 32-bit | `ARM:LE:32:v8` |
| ARM64 | `AARCH64:LE:64:v8A` |

## Memory Tuning

For large binaries (>50MB), increase the Java heap:

1. Edit `$env:GHIDRA_INSTALL_DIR\support\analyzeHeadless.bat`
2. Find the `MAXMEM` variable
3. Change from default to: `set MAXMEM=4G` (or more)

Or set via environment variable:
```powershell
$env:_JAVA_OPTIONS = "-Xmx4g"
```

## Output Directory

The `ExportDecompiled.py` script outputs to a directory next to the input file (or as specified by script arguments):

```
<output>/
├── decompiled/          # C pseudocode per function
│   ├── main.c
│   ├── WinMain.c
│   ├── sub_401000.c
│   └── ...
├── imports.txt          # DLL imports listing
├── exports.txt          # DLL exports listing (if DLL)
├── strings.txt          # String references
└── summary.txt          # Analysis summary
```

## Troubleshooting

| Problem | Solution |
|---|---|
| `GHIDRA_INSTALL_DIR not set` | Set environment variable to Ghidra directory |
| `Java not found` | Install Java 17+ and ensure it's in PATH |
| `OutOfMemoryError` | Increase `MAXMEM` in analyzeHeadless.bat |
| Script errors | Use `-scriptlog <file>` to capture script output |
| Wrong architecture detected | Use `-processor <langID>` to override |
| Analysis hangs | Use `-analysisTimeoutPerFile 300` to set a 5-minute timeout |
