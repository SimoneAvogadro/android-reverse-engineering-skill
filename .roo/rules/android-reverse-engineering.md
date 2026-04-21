# Android Reverse Engineering

Decompile Android APK, XAPK, JAR, and AAR files using jadx and Fernflower/Vineflower. Extract Retrofit endpoints, OkHttp calls, hardcoded URLs, and authentication patterns.

## Dependencies

Run the dependency checker before decompiling:
```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.sh
```

Required: Java JDK 17+, jadx.
Optional: Fernflower/Vineflower, dex2jar, apktool.

Install missing:
```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh <dep>
```

## Workflow

1. **Check deps**: `check-deps.sh` → outputs `INSTALL_REQUIRED:<dep>` for missing tools
2. **Decompile**: `decompile.sh <file>` with `--engine jadx|fernflower|both`, `--deobf`
3. **Analyze**: Review AndroidManifest.xml, package structure, architecture patterns
4. **Trace flows**: Follow Activity → ViewModel → Repository → Retrofit/OkHttp → HTTP
5. **Extract APIs**: `find-api-calls.sh <dir>` with `--retrofit`, `--okhttp`, `--urls`, `--auth`

## Script Locations

All scripts are at: `plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/`
- `check-deps.sh` — verify dependencies
- `install-dep.sh` — install a dependency
- `decompile.sh` — main decompile wrapper
- `find-api-calls.sh` — API call search

## Reference Documentation

- `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/setup-guide.md`
- `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/jadx-usage.md`
- `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/fernflower-usage.md`
- `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/api-extraction-patterns.md`
- `plugins/android-reverse-engineering/skills/android-reverse-engineering/references/call-flow-analysis.md`

## Output Format

Document each API endpoint as:
```markdown
### `METHOD /api/endpoint`
- **Source**: ClassName.java:42
- **Retrofit**: @POST("/api/endpoint")
- **Headers**: Authorization: Bearer {token}
- **Body**: { "key": "value" }
- **Called from**: Activity → ViewModel → Repository → ApiService
```
