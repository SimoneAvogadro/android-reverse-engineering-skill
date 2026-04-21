# Windows Reverse Engineering

Decompile Windows EXE, DLL, SYS, and .NET assemblies using Ghidra (native PE → C pseudocode) and ILSpy (.NET → C# source). Auto-detects binary type and selects the appropriate engine.

## Dependencies

Run the dependency checker before decompiling:
```powershell
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/check-deps.ps1
```

Required (at least one): Java JDK 17+ with Ghidra, OR ilspycmd (.NET SDK).
Optional: strings/strings2, dumpbin (Visual Studio C++ Build Tools), de4dot.

Install missing:
```powershell
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/install-dep.ps1 <dep>
```

If PowerShell execution policy blocks scripts, use: `powershell -ExecutionPolicy Bypass -File <script>`.

## Workflow

1. **Check deps**: `check-deps.ps1` → outputs `INSTALL_REQUIRED:<dep>` for missing tools
2. **Decompile**: `decompile.ps1 <file>` — auto-detects .NET (→ ILSpy) vs native (→ Ghidra)
   - Options: `-Engine auto|ghidra|ilspy`, `-Output <dir>`, `-NoStrings`
3. **Analyze**: Review PE imports/exports, namespace structure, entry points
4. **Trace flows**: Follow WinMain/Main → handlers → business logic → API calls
5. **Extract APIs**: `find-api-calls.ps1 <dir>` with `-Network`, `-Registry`, `-Crypto`, `-Urls`, `-Auth`, `-Process`, `-Persistence`

## Script Locations

All scripts are at: `plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/`
- `check-deps.ps1` — verify dependencies
- `install-dep.ps1` — install a dependency
- `decompile.ps1` — main decompile wrapper
- `find-api-calls.ps1` — API call search
- `ghidra-scripts/ExportDecompiled.py` — Ghidra Jython export

## Reference Documentation

- `plugins/windows-reverse-engineering/skills/windows-reverse-engineering/references/setup-guide.md`
- `plugins/windows-reverse-engineering/skills/windows-reverse-engineering/references/ghidra-headless-usage.md`
- `plugins/windows-reverse-engineering/skills/windows-reverse-engineering/references/ilspy-usage.md`
- `plugins/windows-reverse-engineering/skills/windows-reverse-engineering/references/api-extraction-patterns.md`
- `plugins/windows-reverse-engineering/skills/windows-reverse-engineering/references/call-flow-analysis.md`

## Output Format

Document each API call as:
```markdown
### `FunctionName` (DLL: source.dll)
- **Source**: filename.c:42
- **Category**: Network / Registry / File I/O / Process / Crypto
- **Parameters**: param1: value, param2: value
- **Called from**: Main → InitNetwork → WinHttpSendRequest
- **Purpose**: Description
```
