# Reverse Engineering Skills

This repository provides AI-assisted reverse engineering for Windows and Android binaries.

## Windows RE
- Decompiles EXE/DLL/.NET using Ghidra (native) and ILSpy (.NET)
- Scripts: `plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/`
- Check deps: `powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/check-deps.ps1`
- Decompile: `powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/decompile.ps1 <file>`
- Find APIs: `powershell -ExecutionPolicy Bypass -File plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/find-api-calls.ps1 <dir>`

## Android RE
- Decompiles APK/XAPK/JAR/AAR using jadx and Fernflower
- Scripts: `plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/`
- Check deps: `bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.sh`
- Decompile: `bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh <file>`
- Find APIs: `bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh <dir>`

## Detailed References
- See `plugins/*/skills/*/references/` for setup guides, tool CLI references, API patterns, and call flow analysis techniques.
