# jadx CLI Reference

## Basic Usage

```bash
jadx [options] <input-file>
```

Input can be an `.apk`, `.jar`, `.aar`, `.dex`, or `.zip` file.

## Key Options

| Option | Description |
|---|---|
| `-d <dir>` | Output directory for decompiled sources |
| `--deobf` | Enable deobfuscation — renames obfuscated classes/methods to readable names |
| `--show-bad-code` | Show partially decompiled code instead of error comments |
| `--no-res` | Skip resource decoding — faster when you only need code |
| `--no-src` | Skip source decompilation — only decode resources |
| `--export-gradle` | Generate a Gradle project structure (useful for importing into IDE) |
| `-e` | Same as `--export-gradle` |
| `--threads-count <N>` | Number of processing threads (default: CPU count) |
| `-Xmx<size>` | Set maximum Java heap (e.g., `-Xmx4g` for large APKs) |

## Decompiling Different File Types

### APK (Android Application Package)

```bash
jadx -d output-dir app.apk
```

Produces:
- `output-dir/sources/` — Decompiled Java source files
- `output-dir/resources/` — Decoded resources (AndroidManifest.xml, layouts, drawables, etc.)

### JAR (Java Archive)

```bash
jadx -d output-dir library.jar
```

Useful for analyzing third-party libraries bundled within an APK.

### AAR (Android Archive)

```bash
jadx -d output-dir library.aar
```

AAR files contain both compiled code and Android resources. jadx handles them directly.

## Handling Obfuscated Code

Apps built with ProGuard or R8 produce obfuscated bytecode with single-letter class and method names.

### Strategies

1. **Use `--deobf`** to generate readable replacement names:
   ```bash
   jadx --deobf -d output-dir app.apk
   ```
   jadx creates a mapping file at `output-dir/deobf-mapping.txt` that maps original obfuscated names to generated names.

2. **Use the ProGuard mapping file** if available (sometimes shipped in the APK under `assets/` or obtainable from build artifacts):
   ```bash
   jadx --deobf-map mapping.txt -d output-dir app.apk
   ```

3. **Focus on string constants and API calls** rather than class names when navigating obfuscated code. URL strings, annotation values, and library classes are not obfuscated.

## jadx-gui

For interactive exploration, use the GUI version:

```bash
jadx-gui app.apk
```

Features:
- Full-text search across all decompiled sources
- Click-through navigation (jump to definition)
- Deobfuscation with live renaming
- Smali view alongside Java

jadx-gui is included in the same distribution as the CLI tool.

## Common Workflows

### Code-only decompilation (fastest)

```bash
jadx --no-res --show-bad-code -d output app.apk
```

### Full decompilation with deobfuscation

```bash
jadx --deobf --show-bad-code -d output app.apk
```

### Export as Gradle project for IDE import

```bash
jadx -e -d output app.apk
# Then open output/ in Android Studio or IntelliJ
```

### Decompile a specific DEX from a multi-dex APK

Extract the APK (it's a ZIP), then target individual DEX files:

```bash
unzip app.apk -d extracted/
jadx -d output extracted/classes2.dex
```
