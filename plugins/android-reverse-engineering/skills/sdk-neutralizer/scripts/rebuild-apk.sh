#!/usr/bin/env bash
# rebuild-apk.sh — Rebuild and sign a decoded APK directory
#
# Pipeline: apktool b → zipalign (optional) → sign → verify
#
# Exit codes:
#   0 — success
#   1 — error (build failed, signing failed)
#   2 — manual action needed (missing tools)
set -euo pipefail

usage() {
  cat <<EOF
Usage: rebuild-apk.sh <decoded-dir> [OPTIONS]

Rebuild an apktool-decoded APK directory back into a signed APK.

Arguments:
  <decoded-dir>   Path to the apktool-decoded APK directory

Options:
  -o, --output <file>     Output APK path (default: <decoded-dir>-neutralized.apk)
  --debug-key             Sign with an auto-generated debug keystore (default)
  --keystore <file>       Path to a custom keystore file
  --key-alias <alias>     Key alias within the keystore (default: key0)
  --key-pass <password>   Key password (default: android)
  --store-pass <password> Keystore password (default: android)
  --no-sign               Skip signing (output unsigned APK)
  --no-res                Skip resource recompilation (apktool b --no-res)
  --zipalign              Run zipalign before signing (recommended, default if available)
  --no-zipalign           Skip zipalign
  -h, --help              Show this help message

Output:
  BUILD_OK:<output-apk>
  BUILD_WARNING:Resources were not recompiled (--no-res fallback)
  SIGN_OK:<output-apk>
  VERIFY_OK:<output-apk>
EOF
  exit 0
}

# =====================================================================
# Argument parsing
# =====================================================================

DECODED_DIR=""
OUTPUT=""
USE_DEBUG_KEY=true
KEYSTORE=""
KEY_ALIAS="key0"
KEY_PASS="android"
STORE_PASS="android"
DO_SIGN=true
DO_ZIPALIGN=true
NO_ZIPALIGN=false
FORCE_NO_RES=false
BUILD_USED_NO_RES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      shift
      if [[ $# -eq 0 ]]; then echo "Error: --output requires a file argument" >&2; exit 1; fi
      OUTPUT="$1"; shift ;;
    --debug-key)     USE_DEBUG_KEY=true; shift ;;
    --keystore)
      shift
      if [[ $# -eq 0 ]]; then echo "Error: --keystore requires a file argument" >&2; exit 1; fi
      KEYSTORE="$1"; USE_DEBUG_KEY=false; shift ;;
    --key-alias)
      shift
      if [[ $# -eq 0 ]]; then echo "Error: --key-alias requires an argument" >&2; exit 1; fi
      KEY_ALIAS="$1"; shift ;;
    --key-pass)
      shift
      if [[ $# -eq 0 ]]; then echo "Error: --key-pass requires an argument" >&2; exit 1; fi
      KEY_PASS="$1"; shift ;;
    --store-pass)
      shift
      if [[ $# -eq 0 ]]; then echo "Error: --store-pass requires an argument" >&2; exit 1; fi
      STORE_PASS="$1"; shift ;;
    --no-sign)       DO_SIGN=false; shift ;;
    --no-res)        FORCE_NO_RES=true; shift ;;
    --zipalign)      DO_ZIPALIGN=true; shift ;;
    --no-zipalign)   NO_ZIPALIGN=true; DO_ZIPALIGN=false; shift ;;
    -h|--help)       usage ;;
    -*)              echo "Error: Unknown option $1" >&2; usage ;;
    *)               DECODED_DIR="$1"; shift ;;
  esac
done

if [[ -z "$DECODED_DIR" ]]; then
  echo "Error: No decoded directory specified." >&2
  usage
fi

if [[ ! -d "$DECODED_DIR" ]]; then
  echo "Error: Directory not found: $DECODED_DIR" >&2
  exit 1
fi

# Default output name
if [[ -z "$OUTPUT" ]]; then
  # Strip trailing slash
  local_dir="${DECODED_DIR%/}"
  OUTPUT="${local_dir}-neutralized.apk"
fi

# =====================================================================
# Tool checks
# =====================================================================

info()  { echo "[INFO] $*"; }
ok()    { echo "[OK] $*"; }
fail()  { echo "[FAIL] $*" >&2; }

if ! command -v apktool &>/dev/null; then
  fail "apktool is not installed. Run: install-dep.sh apktool"
  exit 1
fi

if ! command -v java &>/dev/null; then
  fail "java is not installed. Run: install-dep.sh java"
  exit 1
fi

# Determine signing tool
SIGNER=""
if [[ "$DO_SIGN" == true ]]; then
  if command -v apksigner &>/dev/null; then
    SIGNER="apksigner"
  elif command -v jarsigner &>/dev/null; then
    SIGNER="jarsigner"
  else
    fail "Neither apksigner nor jarsigner found. Install apksigner or use --no-sign."
    exit 1
  fi
fi

# Check zipalign availability
ZIPALIGN_CMD=""
if [[ "$DO_ZIPALIGN" == true ]] && [[ "$NO_ZIPALIGN" == false ]]; then
  if command -v zipalign &>/dev/null; then
    ZIPALIGN_CMD="zipalign"
  else
    # Check Android SDK
    for sdk_dir in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
      if [[ -n "$sdk_dir" ]] && [[ -d "$sdk_dir/build-tools" ]]; then
        latest_bt=$(ls -1 "$sdk_dir/build-tools" 2>/dev/null | sort -V | tail -1)
        if [[ -n "$latest_bt" ]] && [[ -f "$sdk_dir/build-tools/$latest_bt/zipalign" ]]; then
          ZIPALIGN_CMD="$sdk_dir/build-tools/$latest_bt/zipalign"
          break
        fi
      fi
    done
    if [[ -z "$ZIPALIGN_CMD" ]]; then
      info "zipalign not found — skipping alignment (APK will still work)"
      DO_ZIPALIGN=false
    fi
  fi
fi

# =====================================================================
# Step 1: Build APK with apktool
# =====================================================================

echo "=== Rebuilding APK ==="
echo "Source: $DECODED_DIR"
echo "Output: $OUTPUT"
echo

info "Running apktool build..."
BUILT_APK="$DECODED_DIR/dist/$(basename "$DECODED_DIR").apk"

build_apk() {
  local no_res_flag="${1:-}"
  # Clean previous build artifacts
  rm -rf "$DECODED_DIR/dist/" 2>/dev/null || true
  if apktool b $no_res_flag "$DECODED_DIR" 2>&1; then
    return 0
  fi
  return 1
}

if [[ "$FORCE_NO_RES" == true ]]; then
  # User explicitly requested --no-res
  if ! build_apk "--no-res"; then
    fail "apktool build failed (with --no-res)."
    echo "Tip: If this is a framework error, try: rm -f ~/.local/share/apktool/framework/1.apk"
    exit 1
  fi
  BUILD_USED_NO_RES=true
else
  # First attempt: normal build
  if ! build_apk ""; then
    info "Build failed — retrying with --no-res (skipping resource recompilation)..."
    if ! build_apk "--no-res"; then
      fail "apktool build failed (both normal and --no-res)."
      echo "Tip: If this is a framework error, try: rm -f ~/.local/share/apktool/framework/1.apk"
      exit 1
    fi
    BUILD_USED_NO_RES=true
  fi
fi

# apktool outputs to dist/ inside the decoded dir
if [[ ! -f "$BUILT_APK" ]]; then
  # Try finding any APK in dist/
  BUILT_APK=$(find "$DECODED_DIR/dist/" -name "*.apk" -type f | head -1)
  if [[ -z "$BUILT_APK" ]] || [[ ! -f "$BUILT_APK" ]]; then
    fail "Built APK not found in $DECODED_DIR/dist/"
    exit 1
  fi
fi

ok "APK built: $BUILT_APK"
echo "BUILD_OK:$BUILT_APK"
if [[ "$BUILD_USED_NO_RES" == true ]]; then
  echo "BUILD_WARNING:Resources were not recompiled (--no-res fallback)"
fi

# =====================================================================
# Step 2: Zipalign (optional)
# =====================================================================

ALIGNED_APK="$BUILT_APK"
if [[ "$DO_ZIPALIGN" == true ]] && [[ -n "$ZIPALIGN_CMD" ]]; then
  info "Running zipalign..."
  ALIGNED_APK="${BUILT_APK%.apk}-aligned.apk"
  if "$ZIPALIGN_CMD" -f 4 "$BUILT_APK" "$ALIGNED_APK"; then
    ok "Zipaligned: $ALIGNED_APK"
    # Remove unaligned APK
    rm -f "$BUILT_APK"
  else
    info "Zipalign failed — continuing with unaligned APK"
    ALIGNED_APK="$BUILT_APK"
  fi
fi

# =====================================================================
# Step 3: Sign APK
# =====================================================================

if [[ "$DO_SIGN" == false ]]; then
  cp "$ALIGNED_APK" "$OUTPUT"
  ok "Unsigned APK saved to: $OUTPUT"
  echo "BUILD_OK:$OUTPUT"
  echo
  echo "WARNING: APK is unsigned and cannot be installed without signing."
  exit 0
fi

# Generate debug keystore if needed
if [[ "$USE_DEBUG_KEY" == true ]]; then
  KEYSTORE="$DECODED_DIR/.neutralizer-debug.keystore"
  if [[ ! -f "$KEYSTORE" ]]; then
    info "Generating debug keystore..."
    keytool -genkeypair \
      -keystore "$KEYSTORE" \
      -alias "$KEY_ALIAS" \
      -keyalg RSA \
      -keysize 2048 \
      -validity 10000 \
      -storepass "$STORE_PASS" \
      -keypass "$KEY_PASS" \
      -dname "CN=SDK Neutralizer Debug Key, OU=Debug, O=Debug, L=Unknown, ST=Unknown, C=US" \
      2>/dev/null
    ok "Debug keystore generated: $KEYSTORE"
  fi
fi

if [[ ! -f "$KEYSTORE" ]]; then
  fail "Keystore not found: $KEYSTORE"
  exit 1
fi

info "Signing APK with $SIGNER..."

if [[ "$SIGNER" == "apksigner" ]]; then
  apksigner sign \
    --ks "$KEYSTORE" \
    --ks-key-alias "$KEY_ALIAS" \
    --ks-pass "pass:$STORE_PASS" \
    --key-pass "pass:$KEY_PASS" \
    --out "$OUTPUT" \
    "$ALIGNED_APK"
elif [[ "$SIGNER" == "jarsigner" ]]; then
  # jarsigner signs in-place, so copy first
  cp "$ALIGNED_APK" "$OUTPUT"
  jarsigner \
    -keystore "$KEYSTORE" \
    -storepass "$STORE_PASS" \
    -keypass "$KEY_PASS" \
    -signedjar "$OUTPUT" \
    "$ALIGNED_APK" \
    "$KEY_ALIAS"
fi

if [[ ! -f "$OUTPUT" ]]; then
  fail "Signed APK not found at: $OUTPUT"
  exit 1
fi

ok "APK signed: $OUTPUT"
echo "SIGN_OK:$OUTPUT"

# Clean up intermediate files
rm -f "$ALIGNED_APK" 2>/dev/null || true

# =====================================================================
# Step 4: Verify signature
# =====================================================================

info "Verifying signature..."

if [[ "$SIGNER" == "apksigner" ]]; then
  if apksigner verify "$OUTPUT" 2>/dev/null; then
    ok "Signature verified (apksigner)"
    echo "VERIFY_OK:$OUTPUT"
  else
    info "Signature verification returned warnings (may still be installable)"
  fi
elif [[ "$SIGNER" == "jarsigner" ]]; then
  if jarsigner -verify "$OUTPUT" 2>/dev/null; then
    ok "Signature verified (jarsigner)"
    echo "VERIFY_OK:$OUTPUT"
  else
    info "Signature verification returned warnings (may still be installable)"
  fi
fi

# =====================================================================
# Summary
# =====================================================================

echo
echo "=== Rebuild Complete ==="
echo "Output APK: $OUTPUT"
echo "Signed with: $SIGNER ($( [[ "$USE_DEBUG_KEY" == true ]] && echo "debug key" || echo "custom keystore" ))"

APK_SIZE=$(stat -f%z "$OUTPUT" 2>/dev/null || stat -c%s "$OUTPUT" 2>/dev/null || echo "unknown")
echo "APK size: $APK_SIZE bytes"

if [[ "$BUILD_USED_NO_RES" == true ]]; then
  echo
  echo "NOTE: Resources were NOT recompiled (--no-res was used)."
  echo "      The APK uses original resources. Manifest XML changes (e.g., android:enabled)"
  echo "      may not be reflected unless they were applied before decode."
fi

echo
echo "WARNING: Play Integrity / SafetyNet will FAIL — expected for enterprise sideloading."
echo "Install via: adb install $OUTPUT"

exit 0
