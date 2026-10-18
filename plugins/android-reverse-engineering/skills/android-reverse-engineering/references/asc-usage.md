# ASC (Android Source Code) CLI Reference

[ASC (Android Source Code)](https://github.com/MG1937/ASC) — available as Python [`droidasc`](https://pypi.org/project/droidasc/) and Rust [`rust_ASC`](https://github.com/MG1937/rust_ASC) — is an ultra-fast, stateless Android decompiler front-end designed specifically for **AI agents, automated pipelines, and mobile security researchers**.

Unlike traditional decompilers (such as `jadx`) that spend minutes and gigabytes of RAM inflating the entire APK and building heavy global cross-reference tables on disk, ASC queries compiled DEX artifacts directly as a database in memory with **zero preprocessing overhead**.

---

## When to Use ASC vs jadx vs Fernflower

| Scenario | Recommended Engine | Rationale |
|---|---|---|
| **Large APK (> 50 MB)** | `asc` | Bypasses long JADX preprocessing and out-of-memory crashes. |
| **Instant API/Token xref search** | `asc findrefs` | Searches strings and calls across all DEX entries in ~1.5s without unpacking. |
| **Targeted class inspection** | `asc getclass` | Decompiles an individual class in ~180ms. |
| **Instant manifest analysis** | `asc getmanifest` | Decodes `AndroidManifest.xml` in milliseconds. |
| **Full app code + UI resources** | `jadx` | Handles XML layouts, drawables, and resource string tables natively. |
| **Complex Java generics/lambdas** | `fernflower` | Produces cleaner Java syntax on decompiled JARs. |
| **Fast single-class extraction** | `decompile.sh --engine asc -c <Class>` | Decompiles only the requested class into `sources/`. |

---

## Installation

### Option 1: Python Package (Recommended)

Requires Python 3.10+:

```bash
pip install --upgrade droidasc
```

Or run the dependency installer:
```bash
# Unix (bash)
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh asc

# Windows (PowerShell)
& "plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.ps1" asc
```

### Option 2: High-Performance Rust Native Binary (`rust_ASC`)

The Rust port provides approximately 10x faster execution and multi-threaded APK processing:

```bash
git clone https://github.com/MG1937/rust_ASC.git
cd rust_ASC
cargo build --release
# Executable is in target/release/rust_ASC (or rust_ASC.exe on Windows)
```

Add the binary directory to your system `PATH`.

---

## CLI Commands & Subcommands

Both `droidasc` and `rust_ASC` share a consistent CLI interface:

```bash
droidasc {getclass,listclass,getmanifest,findrefs} [OPTIONS] <apk_path>
```

### 1. `getclass` — Decompile a Specific Class

Extracts the minimal dependency DEX slice in memory and decompiles the class to standard Java source:

```bash
# Decompile and print to stdout
droidasc getclass app.apk Lcom/example/MainActivity;

# Standard dotted class names are supported
droidasc getclass app.apk com.example.MainActivity

# Save decompiled Java output to a file
droidasc getclass app.apk com.example.NetworkClient -o NetworkClient.java

# Multi-threaded execution for faster method extraction
droidasc getclass app.apk com.example.MainActivity --threads 16
```

### 2. `findrefs` — Search Cross-References

Searches all DEX files inside the APK without unzipping or preprocessing:

#### String References (URLs, Endpoints, Secret Keys)
```bash
# Find all code referencing an API host or endpoint substring
droidasc findrefs app.apk string "api.example.com" -o string_refs.txt
```

#### Class / Type References
```bash
# Find where a specific class or SDK type is referenced
droidasc findrefs app.apk type com.example.AuthManager
```

#### Method Invocations
```bash
# Find callers of a method
droidasc findrefs app.apk method onCreate --class com.example.MainActivity
droidasc findrefs app.apk method post --fuzzy-class -o post_calls.txt
```

#### Field References
```bash
# Find where a field or token variable is read/written
droidasc findrefs app.apk field apiKey -o field_refs.txt
```

#### Class Hierarchy (`extends` / `impl`)
```bash
# Find all Activities or ViewModels in the APK
droidasc findrefs app.apk extends android.app.Activity -o activities.txt
droidasc findrefs app.apk extends androidx.lifecycle.ViewModel -o viewmodels.txt

# Find classes implementing an interface
droidasc findrefs app.apk impl okhttp3.Interceptor -o interceptors.txt
```

### 3. `getmanifest` — Decode AndroidManifest.xml

Instantly decodes the binary AXML into standard readable XML:

```bash
droidasc getmanifest app.apk
droidasc getmanifest app.apk -o AndroidManifest.xml
```

### 4. `listclass` — Enumerate Classes

Lists Dalvik class descriptors across all DEX entries:

```bash
# List all classes
droidasc listclass app.apk -o classes.txt

# Filter by package prefix
droidasc listclass app.apk --prefix com.example.app
```

---

## Integration with Skill Scripts

### Full Decompilation with ASC Engine

Run `decompile.sh` or `decompile.ps1` with `--engine asc`:

```bash
# Unix (bash)
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh --engine asc app.apk

# Windows (PowerShell)
& "plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.ps1" -Engine asc app.apk
```

This extracts:
- `output/resources/AndroidManifest.xml` via `getmanifest`
- `output/classes.txt` via `listclass`
- Application code into `output/sources/`

### Targeted Single-Class Decompilation

When analyzing a specific class identified during triage or API tracing:

```bash
# Unix (bash)
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.sh --engine asc --class com.example.api.ApiClient app.apk

# Windows (PowerShell)
& "plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/decompile.ps1" -Engine asc -Class com.example.api.ApiClient app.apk
```

The targeted class is extracted and written directly to `output/sources/com/example/api/ApiClient.java` in ~100–200 milliseconds.

---

## AI Agent Investigation Playbook

When an agent needs to answer questions about an APK:

1. **Check Manifest first**: Run `droidasc getmanifest <apk>` to find the package name, main Activity, exported components, and permissions in < 1 second.
2. **Find API hosts instantly**: Run `droidasc findrefs <apk> string "https://"` or search for known domains without waiting for thousands of classes to decompile.
3. **Inspect callers**: Use `droidasc findrefs <apk> method <methodName>` to trace call sites.
4. **Decompile only target classes**: Use `droidasc getclass <apk> <TargetClass>` to read the code of relevant repositories, ViewModels, and network clients.
