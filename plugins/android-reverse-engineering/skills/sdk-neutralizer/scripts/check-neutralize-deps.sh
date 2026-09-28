#!/usr/bin/env bash
# check-neutralize-deps.sh — Verify dependencies for SDK neutralization
# Usage: check-neutralize-deps.sh [<input-file>]
#   When <input-file> is a split bundle (.xapk/.apkm/.apks or a directory of
#   split APKs), APKEditor is reported as required; otherwise it is optional.
# Output includes machine-readable INSTALL_REQUIRED: and INSTALL_OPTIONAL: lines,
# plus ZIPALIGN_PAGE_ALIGN:16k|4k|none.
#
# Portable: bash 3.2+ (macOS) and BSD/GNU userland.
set -euo pipefail

case "${1:-}" in
  -h|--help)
    sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  -*)
    echo "Error: Unknown option $1" >&2
    exit 1 ;;
esac

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
INSTALL_DEP="$(cd "$SCRIPT_DIR/../../android-reverse-engineering/scripts" 2>/dev/null && pwd -P)/install-dep.sh"

INPUT_FILE="${1:-}"
SPLIT_INPUT=false
if [[ -n "$INPUT_FILE" ]]; then
  if [[ -d "$INPUT_FILE" ]]; then
    SPLIT_INPUT=true
  else
    case "$(echo "${INPUT_FILE##*.}" | tr '[:upper:]' '[:lower:]')" in
      xapk|apkm|apks) SPLIT_INPUT=true ;;
    esac
  fi
fi

REQUIRED_JAVA_MAJOR=17
missing_required=()
missing_optional=()

add_required() {
  local d
  if [[ ${#missing_required[@]} -gt 0 ]]; then
    for d in "${missing_required[@]}"; do [[ "$d" == "$1" ]] && return 0; done
  fi
  missing_required+=("$1")
}
add_optional() {
  local d
  if [[ ${#missing_optional[@]} -gt 0 ]]; then
    for d in "${missing_optional[@]}"; do [[ "$d" == "$1" ]] && return 0; done
  fi
  missing_optional+=("$1")
}

# Ensure user-local bin is in PATH (install-dep.sh installs tools there)
if [[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

# --- Android SDK build-tools lookup (same order as rebuild-apk.sh) ---
latest_build_tools_dir() {
  local sdk="$1" v
  [[ -n "$sdk" ]] && [[ -d "$sdk/build-tools" ]] || return 1
  v=$(ls -1 "$sdk/build-tools" 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
  [[ -n "$v" ]] && [[ -d "$sdk/build-tools/$v" ]] || return 1
  echo "$sdk/build-tools/$v"
}
SDK_ROOTS=("${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "$HOME/.local/share/android-sdk")

echo "=== SDK Neutralizer: Dependency Check ==="
echo

# --- Java 17+ (required) ---
if command -v java &>/dev/null; then
  java_version_output=$(java -version 2>&1 | sed -n 1p)
  java_version=$(echo "$java_version_output" | sed -n 's/.*"\([0-9]*\)\..*/\1/p')
  if [[ -z "$java_version" ]]; then
    java_version=$(echo "$java_version_output" | grep -oE '[0-9]+' | sed -n 1p || true)
  fi
  if [[ "$java_version" == "1" ]]; then
    java_version=$(echo "$java_version_output" | sed -n 's/.*"1\.\([0-9]*\)\..*/\1/p')
  fi

  if [[ -n "$java_version" ]] && (( java_version >= REQUIRED_JAVA_MAJOR )); then
    echo "[OK] Java $java_version detected"
  else
    echo "[WARN] Java detected but version $java_version is below $REQUIRED_JAVA_MAJOR"
    add_required "java"
  fi
else
  echo "[MISSING] Java is not installed or not in PATH"
  add_required "java"
fi

# --- apktool (required, minimum 2.9.0) ---
APKTOOL_MIN_MAJOR=2
APKTOOL_MIN_MINOR=9
APKTOOL_MIN_PATCH=0

if command -v apktool &>/dev/null; then
  apktool_version_raw=$(apktool --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sed -n 1p || true)
  if [[ -n "$apktool_version_raw" ]]; then
    IFS='.' read -r at_major at_minor at_patch <<< "$apktool_version_raw"
    at_major=${at_major:-0}; at_minor=${at_minor:-0}; at_patch=${at_patch:-0}

    version_ok=false
    if (( at_major > APKTOOL_MIN_MAJOR )); then
      version_ok=true
    elif (( at_major == APKTOOL_MIN_MAJOR && at_minor > APKTOOL_MIN_MINOR )); then
      version_ok=true
    elif (( at_major == APKTOOL_MIN_MAJOR && at_minor == APKTOOL_MIN_MINOR && at_patch >= APKTOOL_MIN_PATCH )); then
      version_ok=true
    fi

    if [[ "$version_ok" == true ]]; then
      echo "[OK] apktool $apktool_version_raw detected"
    else
      echo "[WARN] apktool $apktool_version_raw detected but version >= ${APKTOOL_MIN_MAJOR}.${APKTOOL_MIN_MINOR}.${APKTOOL_MIN_PATCH} is required"
      echo "       Older versions fail on modern APKs (new resource types, targetSdk 34+)."
      add_required "apktool"
    fi
  else
    echo "[OK] apktool detected (could not parse version — assuming compatible)"
  fi
else
  echo "[MISSING] apktool is not installed or not in PATH (required for decode/rebuild)"
  add_required "apktool"
fi

# --- unzip (required: split listing, alignment and ABI checks) ---
if command -v unzip &>/dev/null; then
  echo "[OK] unzip detected"
else
  echo "[MISSING] unzip not found (required — install: apt install unzip / brew install unzip)"
  add_required "unzip"
fi

# --- keytool (required for debug key generation) ---
if command -v keytool &>/dev/null; then
  echo "[OK] keytool detected (part of JDK)"
else
  echo "[MISSING] keytool not found (required for debug key generation, part of JDK)"
  add_required "java"
fi

# --- apksigner (required; Android SDK build-tools first, then PATH) ---
apksigner_path=""
for sdk in "${SDK_ROOTS[@]}"; do
  bt=$(latest_build_tools_dir "$sdk" || true)
  if [[ -n "$bt" ]] && [[ -x "$bt/apksigner" ]]; then apksigner_path="$bt/apksigner"; break; fi
done
if [[ -z "$apksigner_path" ]] && command -v apksigner &>/dev/null; then
  apksigner_path=$(command -v apksigner)
fi
if [[ -n "$apksigner_path" ]]; then
  echo "[OK] apksigner detected: $apksigner_path"
elif command -v jarsigner &>/dev/null; then
  echo "[WARN] only jarsigner found: v1 signatures only — APKs targeting SDK 30+ are refused by"
  echo "       rebuild-apk.sh. Install Android build-tools (apksigner + zipalign)."
  add_required "build-tools"
else
  echo "[MISSING] apksigner not found (required for signing — part of Android build-tools)"
  add_required "build-tools"
fi

# --- APKEditor (required for split bundles: merges splits before decoding) ---
apkeditor_desc=""
apkeditor_ver=""
if [[ -n "${APKEDITOR_JAR:-}" ]]; then
  if [[ -f "$APKEDITOR_JAR" ]]; then
    apkeditor_desc="$APKEDITOR_JAR"
    apkeditor_ver=$(java -jar "$APKEDITOR_JAR" -version 2>&1 | sed -n 's/.*APKEditor version \([0-9.]*\).*/\1/p' | sed -n 1p || true)
  else
    echo "[WARN] APKEDITOR_JAR is set but the file does not exist: $APKEDITOR_JAR"
  fi
elif [[ -f "$HOME/.local/share/apkeditor/APKEditor.jar" ]]; then
  apkeditor_desc="$HOME/.local/share/apkeditor/APKEditor.jar"
  apkeditor_ver=$(java -jar "$apkeditor_desc" -version 2>&1 | sed -n 's/.*APKEditor version \([0-9.]*\).*/\1/p' | sed -n 1p || true)
elif command -v apkeditor &>/dev/null; then
  apkeditor_desc="$(command -v apkeditor)"
  apkeditor_ver=$(apkeditor -version 2>&1 | sed -n 's/.*APKEditor version \([0-9.]*\).*/\1/p' | sed -n 1p || true)
fi
if [[ -n "$apkeditor_desc" ]] && [[ -n "$apkeditor_ver" ]]; then
  echo "[OK] APKEditor $apkeditor_ver detected ($apkeditor_desc)"
else
  if [[ -n "$apkeditor_desc" ]]; then
    echo "[WARN] APKEditor at $apkeditor_desc does not run (corrupt JAR or no Java?)"
  fi
  if [[ "$SPLIT_INPUT" == true ]]; then
    echo "[MISSING] APKEditor not usable (required: the input is a split bundle, merged into one APK before decoding)"
    add_required "apkeditor"
  else
    echo "[MISSING] APKEditor not usable (optional for .apk input; required for XAPK/APKM/APKS input)"
    add_optional "apkeditor"
  fi
fi

# --- zipalign (required: page-aligns stored native libraries) ---
# build-tools 35+ zipalign supports -P 16 (16 KB pages); older ones only -p (4 KB).
zipalign_candidates=()
if command -v zipalign &>/dev/null; then
  zipalign_candidates+=("$(command -v zipalign)")
fi
for sdk in "${SDK_ROOTS[@]}"; do
  bt=$(latest_build_tools_dir "$sdk" || true)
  if [[ -n "$bt" ]] && [[ -x "$bt/zipalign" ]]; then
    zipalign_candidates+=("$bt/zipalign")
  fi
done
za_path=""
za_page="none"
if [[ ${#zipalign_candidates[@]} -gt 0 ]]; then
  for za in "${zipalign_candidates[@]}"; do
    za_usage=$("$za" 2>&1 || true)
    case "$za_usage" in
      *"-P <pagesize"*) za_path="$za"; za_page="16k"; break ;;
    esac
    if [[ -z "$za_path" ]]; then za_path="$za"; za_page="4k"; fi
  done
fi
case "$za_page" in
  16k) echo "[OK] zipalign detected: $za_path (supports -P 16 — 16 KB page alignment)" ;;
  4k)  echo "[WARN] zipalign detected: $za_path (only -p — 4 KB page alignment)"
       echo "       Devices with 16 KB pages refuse 4 KB-aligned native libraries;"
       echo "       Android build-tools 35+ zipalign adds -P 16."
       add_optional "build-tools" ;;
  *)   echo "[MISSING] zipalign not found (required — stored native libraries must be page-aligned)"
       add_required "build-tools" ;;
esac
echo "ZIPALIGN_PAGE_ALIGN:$za_page"

# --- zip (optional, only for the deprecated XAPK output of --keep-splits) ---
if command -v zip &>/dev/null; then
  echo "[OK] zip detected (only needed for deprecated XAPK output)"
else
  echo "[MISSING] zip not found (only needed for deprecated XAPK output — install: apt install zip / brew install zip)"
  add_optional "zip"
fi

# --- Python 3.6+ (optional, for registry-scan.py) ---
if command -v python3 &>/dev/null; then
  py_version=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)
  py_major=$(echo "$py_version" | cut -d. -f1)
  py_minor=$(echo "$py_version" | cut -d. -f2)
  if [[ "${py_major:-0}" -ge 3 ]] && [[ "${py_minor:-0}" -ge 6 ]]; then
    echo "[OK] Python $py_version (for registry-scan.py — SDK registry scanning)"
  else
    echo "[WARN] Python $py_version found but 3.6+ required for registry-scan.py"
    echo "       Without Python 3.6+, neutralize.sh falls back to builtin hardcoded targets."
    echo "       Install: apt install python3 / brew install python3"
    add_optional "python3"
  fi
else
  echo "[WARN] python3 not found (optional — required for registry-scan.py SDK registry scanning)"
  echo "       Without python3, neutralize.sh falls back to builtin hardcoded targets."
  echo "       Install: apt install python3 / brew install python3"
  add_optional "python3"
fi

# --- Machine-readable summary ---
echo
if [[ ${#missing_required[@]} -gt 0 ]]; then
  for dep in "${missing_required[@]}"; do
    echo "INSTALL_REQUIRED:$dep"
  done
fi
if [[ ${#missing_optional[@]} -gt 0 ]]; then
  for dep in "${missing_optional[@]}"; do
    echo "INSTALL_OPTIONAL:$dep"
  done
fi

echo
echo "Tip: If apktool decode/build fails with framework errors, try:"
echo "     rm -f ~/.local/share/apktool/framework/1.apk"
echo

if [[ ${#missing_required[@]} -gt 0 ]]; then
  echo "*** ${#missing_required[@]} required dependency/ies missing. ***"
  echo
  echo "Install all neutralizer dependencies at once. 'build-tools' is Google's Android SDK"
  echo "Build-Tools, licensed under https://developer.android.com/studio/terms — the user must"
  echo "accept that license before --accept-android-sdk-license is passed:"
  echo "  bash \"$INSTALL_DEP\" neutralize-all --accept-android-sdk-license"
  echo
  echo "Run it as your own user, never with sudo: if a system package needs sudo and there"
  echo "is no TTY, it prints the exact 'sudo apt-get install ...' command to run first."
  echo
  echo "Or install individually: bash \"$INSTALL_DEP\" <name>"
  exit 1
else
  if [[ ${#missing_optional[@]} -gt 0 ]]; then
    echo "Required dependencies OK. ${#missing_optional[@]} optional dependency/ies missing."
  else
    echo "All dependencies are installed. Ready to neutralize."
  fi
  exit 0
fi
