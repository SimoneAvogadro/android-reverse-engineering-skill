---
description: 'Windows reverse engineering with Ghidra and ILSpy — decompile EXE/DLL/.NET, extract Win32 APIs, trace call flows'
applyTo: '**/*.{exe,dll,sys}'
---

# Windows Reverse Engineering

Decompile Windows binaries using Ghidra (native PE → C pseudocode) or ILSpy (.NET → C# source).

## Commands

```powershell
# Check dependencies
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/check-deps.ps1

# Install missing dependency
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/install-dep.ps1 <dep>
# Available: java, ghidra, ilspycmd, dotnet-sdk, strings, dumpbin, de4dot

# Decompile (auto-detects .NET vs native)
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/decompile.ps1 target.exe
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/decompile.ps1 -Engine ilspy MyDotNet.dll

# Find API calls in decompiled output
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/find-api-calls.ps1 output/sources/
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/find-api-calls.ps1 output/sources/ -Network
powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/find-api-calls.ps1 output/sources/ -Urls
```

## Workflow

1. Verify dependencies → `check-deps.ps1`
2. Decompile → `decompile.ps1` (auto-detects engine)
3. Analyze PE structure (imports, exports, headers)
4. Trace call flows from entry points to API calls
5. Extract and document APIs → `find-api-calls.ps1`

## References

See `plugins/windows-reverse-engineering/skills/windows-reverse-engineering/references/` for detailed guides.
