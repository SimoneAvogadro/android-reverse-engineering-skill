---
name: android-reverse-engineering
description: Decompiles Android APK, XAPK, JAR, and AAR files using jadx or Fernflower/Vineflower. Reverse engineers Android apps, extracts HTTP API endpoints (Retrofit, OkHttp, Ktor, Apollo, Volley), recovers Kotlin class names from R8 obfuscation, and traces call flows from UI to network layer. Use when the user wants to decompile, analyze, or reverse engineer Android packages, find API endpoints, or follow call flows. Triggers include jadx, fernflower, vineflower, decompile APK, reverse engineer Android, extract API, 反编译APK, 安卓逆向, 提取API.
---

# Android Reverse Engineering (Cursor)

Skill root (repo-relative):

`plugins/android-reverse-engineering/skills/android-reverse-engineering/`

Scripts: `plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/`
References: `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/`

> **Claude Code equivalent:** `${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/` maps to the skill root above.

## Platform scripts

Detect the user's OS and pick the matching script suffix:

- **Linux / macOS:** use `bash plugins/.../scripts/*.sh`
- **Windows:** use `& plugins/.../scripts/*.ps1`

Detect via `$env:OS` (Windows), `uname` (Darwin/Linux), or the user's shell. Do not use PowerShell scripts on macOS/Linux unless the user explicitly prefers Git Bash with `.ps1` (rare).

### Prerequisites

Tools must be on **PATH** (or standard fallback locations). Required: **Java JDK 17+**, **jadx**. Optional but recommended: Vineflower/Fernflower (`FERNFLOWER_JAR_PATH` for a JAR), dex2jar.

**Before any decompile work**, run the dependency checker and do not proceed if required tools are missing:

```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.sh
```

On Windows (PowerShell):

```powershell
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.ps1
```

Output includes machine-readable lines: `INSTALL_REQUIRED:<dep>`, `INSTALL_OPTIONAL:<dep>`. Exit code `1` means required tools are missing.

Install missing tools (optional; user may prefer manual PATH setup):

```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh <dep>
```

On Windows (PowerShell):

```powershell
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.ps1 <dep>
```

See `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/setup-guide.md` for installation details.

## Workflow

Full workflow documentation: `plugins/android-reverse-engineering/skills/android-reverse-engineering/SKILL.md`

### Phase 0: Fingerprint (recommended first)

```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/fingerprint.sh <file.apk|file.xapk>
```

On Windows (PowerShell):

```powershell
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/fingerprint.ps1 <file.apk|file.xapk>
```

If Flutter / React Native / Cordova / Xamarin is detected, stop; Java decompilation is not the right path.

### Phase 1: Verify dependencies

```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.sh
```

On Windows (PowerShell):

```powershell
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.ps1
```

### Phase 2: Decompile

```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh [OPTIONS] <file>
```

On Windows (PowerShell):

```powershell
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.ps1 [OPTIONS] <file>
```

Options: `-o`/`-Output <dir>`, `--deobf`/`-Deobf`, `--no-res`/`-NoRes`, `--engine`/`-Engine jadx|fernflower|both`

### Phase 3: Analyze structure

Read `AndroidManifest.xml`, survey `sources/`, grep `BuildConfig.java` files, identify architecture pattern.

### Phase 3.5: Recover Kotlin names (obfuscated Kotlin apps)

```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/recover-kotlin-names.sh <output>/sources <output>/mapping
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/lookup-name.sh <output>/mapping --grep '"/api/' <output>/sources
```

On Windows (PowerShell):

```powershell
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/recover-kotlin-names.ps1 <output>/sources <output>/mapping
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/lookup-name.ps1 <output>/mapping --grep '"/api/' <output>/sources
```

### Phase 4: Trace call flows

See `references/call-flow-analysis.md`.

### Phase 5: Extract APIs

```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.sh <output>/sources/
```

On Windows (PowerShell):

```powershell
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/find-api-calls.ps1 <output>/sources/
```

Targeted flags: `--retrofit`/`-Retrofit`, `--okhttp`/`-OkHttp`, `--ktor`/`-Ktor`, `--apollo`/`-Apollo`, `--volley`/`-Volley`, `--urls`/`-Urls`, `--paths`/`-Paths`, `--auth`/`-Auth`

Produce Tier 1 inventory table for all endpoints; Tier 2 detail only for high-value endpoints (auth, payments, user-requested).

## References

- `references/setup-guide.md`: tool installation
- `references/jadx-usage.md`: jadx CLI
- `references/fernflower-usage.md`: Fernflower/Vineflower CLI
- `references/api-extraction-patterns.md`: search patterns
- `references/kotlin-name-recovery.md`: R8 name recovery
- `references/call-flow-analysis.md`: tracing techniques

## Output deliverables

1. Decompiled source in output directory
2. Architecture summary
3. API documentation (Tier 1 table + Tier 2 for key endpoints)
4. Call flow map (auth and main features)
