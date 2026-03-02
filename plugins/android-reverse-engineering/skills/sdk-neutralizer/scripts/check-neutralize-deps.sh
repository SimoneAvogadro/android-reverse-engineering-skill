#!/usr/bin/env bash
# check-neutralize-deps.sh — Verify dependencies for SDK neutralization
# Output includes machine-readable INSTALL_REQUIRED: and INSTALL_OPTIONAL: lines.
set -euo pipefail

REQUIRED_JAVA_MAJOR=17
missing_required=()
missing_optional=()

echo "=== SDK Neutralizer: Dependency Check ==="
echo

# --- Java 17+ (required) ---
if command -v java &>/dev/null; then
  java_version_output=$(java -version 2>&1 | head -1)
  java_version=$(echo "$java_version_output" | sed -n 's/.*"\([0-9]*\)\..*/\1/p')
  if [[ -z "$java_version" ]]; then
    java_version=$(echo "$java_version_output" | grep -oP '\d+' | head -1)
  fi
  if [[ "$java_version" == "1" ]]; then
    java_version=$(echo "$java_version_output" | sed -n 's/.*"1\.\([0-9]*\)\..*/\1/p')
  fi

  if [[ -n "$java_version" ]] && (( java_version >= REQUIRED_JAVA_MAJOR )); then
    echo "[OK] Java $java_version detected"
  else
    echo "[WARN] Java detected but version $java_version is below $REQUIRED_JAVA_MAJOR"
    missing_required+=("java")
  fi
else
  echo "[MISSING] Java is not installed or not in PATH"
  missing_required+=("java")
fi

# --- apktool (required, minimum 2.9.0) ---
APKTOOL_MIN_MAJOR=2
APKTOOL_MIN_MINOR=9
APKTOOL_MIN_PATCH=0

if command -v apktool &>/dev/null; then
  apktool_version_raw=$(apktool --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
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
      missing_required+=("apktool")
    fi
  else
    echo "[OK] apktool detected (could not parse version — assuming compatible)"
  fi
else
  echo "[MISSING] apktool is not installed or not in PATH (required for decode/rebuild)"
  missing_required+=("apktool")
fi

# --- apksigner or jarsigner (at least one required) ---
signer_found=false
if command -v apksigner &>/dev/null; then
  echo "[OK] apksigner detected"
  signer_found=true
elif command -v jarsigner &>/dev/null; then
  echo "[OK] jarsigner detected (fallback signer)"
  signer_found=true
fi
if [[ "$signer_found" == false ]]; then
  echo "[MISSING] Neither apksigner nor jarsigner found (at least one required for signing)"
  missing_required+=("apksigner")
fi

# --- keytool (required for debug key generation) ---
if command -v keytool &>/dev/null; then
  echo "[OK] keytool detected (part of JDK)"
else
  echo "[MISSING] keytool not found (required for debug key generation, part of JDK)"
  missing_required+=("java")
fi

# --- zipalign (optional, improves APK performance) ---
if command -v zipalign &>/dev/null; then
  echo "[OK] zipalign detected (optional)"
else
  # Check Android SDK build-tools
  za_found=false
  for sdk_dir in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
    if [[ -n "$sdk_dir" ]] && [[ -d "$sdk_dir/build-tools" ]]; then
      latest_bt=$(ls -1 "$sdk_dir/build-tools" 2>/dev/null | sort -V | tail -1)
      if [[ -n "$latest_bt" ]] && [[ -f "$sdk_dir/build-tools/$latest_bt/zipalign" ]]; then
        echo "[OK] zipalign found in Android SDK build-tools ($latest_bt)"
        za_found=true
        break
      fi
    fi
  done
  if [[ "$za_found" == false ]]; then
    echo "[MISSING] zipalign not found (optional — improves APK alignment for performance)"
    missing_optional+=("zipalign")
  fi
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
  echo "Run install-dep.sh <name> to install, or see references/neutralization-guide.md."
  exit 1
else
  if [[ ${#missing_optional[@]} -gt 0 ]]; then
    echo "Required dependencies OK. ${#missing_optional[@]} optional dependency/ies missing."
  else
    echo "All dependencies are installed. Ready to neutralize."
  fi
  exit 0
fi
