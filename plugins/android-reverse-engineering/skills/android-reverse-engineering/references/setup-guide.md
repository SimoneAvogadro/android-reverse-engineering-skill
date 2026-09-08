# Setup Guide: Dependencies for Android Reverse Engineering

## Java JDK 17+

jadx requires Java 17 or later.

### Ubuntu / Debian

```bash
sudo apt update
sudo apt install openjdk-17-jdk
```

### Fedora

```bash
sudo dnf install java-17-openjdk-devel
```

### Arch Linux

```bash
sudo pacman -S jdk17-openjdk
```

### macOS (Homebrew)

```bash
brew install openjdk@17
```

After installation on macOS, follow the symlink instructions printed by Homebrew, or add to your shell profile:

```bash
export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"
```

### Windows (winget)

From PowerShell or Command Prompt:

```powershell
winget install --id Microsoft.OpenJDK.17 --accept-source-agreements --accept-package-agreements
```

Microsoft OpenJDK 17 is added to PATH automatically. If `java` is not found afterward, open a new terminal and run the verify step below.

Alternatively, run the skill's install script (uses winget when available):

```powershell
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.ps1 java
```

### Verify

```bash
java -version
# Should show version 17.x or higher
```

---

## jadx

jadx is the Java decompiler used to convert APK/JAR/AAR files to readable Java source.

### Option 1: GitHub Releases (recommended)

1. Go to <https://github.com/skylot/jadx/releases/latest>
2. Download the `jadx-<version>.zip` file (not the source archive)
3. Extract and add to PATH:

```bash
unzip jadx-*.zip -d ~/jadx
export PATH="$HOME/jadx/bin:$PATH"
# Add the export line to your ~/.bashrc or ~/.zshrc for persistence
```

### Option 2: Homebrew (macOS / Linux)

```bash
brew install jadx
```

### Option 3: Build from source

```bash
git clone https://github.com/skylot/jadx.git
cd jadx
./gradlew dist
# Binaries will be in build/jadx/bin/
export PATH="$(pwd)/build/jadx/bin:$PATH"
```

### Verify

```bash
jadx --version
```

---

## Fernflower / Vineflower (optional, recommended)

Fernflower is the JetBrains Java decompiler. It produces better output than jadx on complex Java constructs, lambdas, and generics. [Vineflower](https://github.com/Vineflower/vineflower) is the actively maintained community fork with published releases; prefer it over upstream Fernflower.

### Option 1: Vineflower from GitHub Releases (recommended)

1. Go to <https://github.com/Vineflower/vineflower/releases/latest>
2. Download `vineflower-<version>.jar`
3. Place it and set the environment variable:

```bash
mkdir -p ~/vineflower
mv vineflower-*.jar ~/vineflower/vineflower.jar
export FERNFLOWER_JAR_PATH="$HOME/vineflower/vineflower.jar"
# Add the export to ~/.bashrc or ~/.zshrc for persistence
```

### Option 2: Build Fernflower from source

```bash
git clone https://github.com/JetBrains/fernflower.git
cd fernflower
./gradlew jar
# Produces: build/libs/fernflower.jar
export FERNFLOWER_JAR_PATH="$(pwd)/build/libs/fernflower.jar"
```

### Option 3: Homebrew (Vineflower)

```bash
brew install vineflower
```

### Verify

```bash
java -jar "$FERNFLOWER_JAR_PATH" --version
```

> **Note**: Fernflower only works on JVM bytecode (JAR, class files). For APK/DEX files, you also need **dex2jar** (see below) as an intermediate conversion step.

---

## dex2jar (optional, needed for Fernflower on APK files)

Converts Android DEX bytecode to standard Java JAR files.

### GitHub Releases

1. Go to <https://github.com/ThexXTURBOXx/dex2jar/releases/latest>
2. Download and extract:

```bash
unzip dex-tools-*.zip -d ~/dex2jar
export PATH="$HOME/dex2jar:$PATH"
```

### Homebrew

```bash
brew install dex2jar
```

### Verify

```bash
d2j-dex2jar --help
```

### Usage

```bash
# Convert APK (or DEX) to JAR
d2j-dex2jar -f -o output.jar app.apk

# Then decompile with Fernflower
java -jar vineflower.jar output.jar decompiled/
```

---

## Optional Tools

### apktool

Useful for decoding resources (XML layouts, drawables) that jadx sometimes handles poorly.

```bash
# Ubuntu/Debian
sudo apt install apktool

# macOS
brew install apktool

# Manual: https://apktool.org/docs/install
```

### adb (Android Debug Bridge)

Useful for pulling APKs directly from a connected Android device.

```bash
# Ubuntu/Debian
sudo apt install adb

# macOS
brew install android-platform-tools
```

Pull an APK from a device:

```bash
# List installed packages
adb shell pm list packages | grep <keyword>

# Get APK path
adb shell pm path com.example.app

# Pull the APK
adb pull /data/app/com.example.app-xxxx/base.apk ./app.apk
```

---

## Linux / macOS (bash)

On Linux and macOS, use the `*.sh` scripts in `scripts/`. Tools must be on **PATH** before running the skill (or in standard fallback locations; see `check-deps.sh`).

### Verify dependencies

```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.sh
```

### Auto-install (optional)

```bash
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh jadx
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh vineflower
bash plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.sh dex2jar
```

The install script detects the OS and package manager, installs without sudo when possible (downloads to `~/.local/share/`, symlinks in `~/.local/bin/`), or uses apt/dnf/pacman/brew when necessary.

---

## Windows (PowerShell)

On Windows, use the `*.ps1` scripts in `scripts/`. Tools must be on **PATH** before running the skill (or in standard fallback locations; see `check-deps.ps1`).

### Required PATH entries

| Tool | What to add to PATH |
|------|---------------------|
| Java JDK 17+ | Java `bin` directory (often already on PATH after install) |
| jadx | `jadx\bin` directory (contains `jadx.bat`) |
| dex2jar (optional) | dex-tools root directory (contains `d2j-dex2jar.bat`) |

For Vineflower, set an environment variable instead of PATH:

```powershell
$env:FERNFLOWER_JAR_PATH = 'C:\path\to\vineflower.jar'
```

### Verify dependencies

```powershell
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.ps1
```

### Auto-install (optional)

```powershell
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.ps1 jadx
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.ps1 vineflower
& plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/install-dep.ps1 dex2jar
```

The install script uses `winget`, `scoop`, or `choco` when available, or downloads to `%USERPROFILE%\.local\share\`.

### Cursor IDE

This repository includes a project skill at `.cursor/skills/android-reverse-engineering/`. Invoke it via `@android-reverse-engineering` or natural-language triggers (e.g. "decompile this APK"). The skill reuses scripts and references under `plugins/android-reverse-engineering/skills/android-reverse-engineering/`; no duplication. Use the bash scripts on Linux/macOS and the PowerShell scripts on Windows.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `jadx: command not found` | Ensure the jadx `bin/` directory is in your `$PATH` |
| `Error: Could not find or load main class` | Java is missing or wrong version; verify with `java -version` |
| jadx runs out of memory on large APKs | Increase heap: `jadx -Xmx4g -d output app.apk` or set `JAVA_OPTS="-Xmx4g"` |
| Decompiled code has many `// Error` comments | Try `--show-bad-code` to see partial output, or use `--deobf` for obfuscated apps |
| Fernflower hangs on a method | Use `-mpm=60` to set a 60-second timeout per method |
| Fernflower JAR not found | Set `FERNFLOWER_JAR_PATH` env variable to the full path of the JAR |
| dex2jar fails with `ZipException` | The APK may have a non-standard ZIP structure; try `jadx` instead |
