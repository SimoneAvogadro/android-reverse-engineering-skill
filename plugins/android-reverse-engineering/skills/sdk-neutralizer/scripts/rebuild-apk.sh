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

# Ensure user-local bin is in PATH (install-dep.sh installs tools there)
if [[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

usage() {
  cat <<EOF
Usage: rebuild-apk.sh <decoded-dir> [OPTIONS]

Rebuild an apktool-decoded APK directory back into a signed APK.
If the decoded dir contains .xapk-origin/ (from decode-apk.sh), automatically
reassembles a complete XAPK with all split APKs re-signed — unless --single-apk
is used or .xapk-origin/.merged exists (from merge-splits.sh), in which case
a single merged APK is produced instead.

Arguments:
  <decoded-dir>   Path to the apktool-decoded APK directory

Options:
  -o, --output <file>     Output path (default: <decoded-dir>-neutralized.apk/.xapk)
  --single-apk            Force output as single .apk even if .xapk-origin/ exists
                          (auto-enabled when .xapk-origin/.merged marker is present)
  --auto-keystore         Auto-detect best keystore: ~/.android/debug.keystore,
                          then previous .neutralizer-debug.keystore, then generate new
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
  KEYSTORE_USED:<path>
  KEYSTORE_SOURCE:debug-standard|debug-previous|debug-generated|custom
  KEYSTORE_ALIAS:<alias>
  SPLIT_SIGNED:<filename>       (XAPK only)
  XAPK_ASSEMBLED:<output-xapk>  (XAPK only)
EOF
  exit 0
}

# =====================================================================
# Argument parsing
# =====================================================================

DECODED_DIR=""
OUTPUT=""
USE_DEBUG_KEY=true
USE_AUTO_KEYSTORE=false
KEYSTORE=""
KEY_ALIAS="key0"
KEY_PASS="android"
STORE_PASS="android"
DO_SIGN=true
DO_ZIPALIGN=true
NO_ZIPALIGN=false
FORCE_NO_RES=false
BUILD_USED_NO_RES=false
SINGLE_APK=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      shift
      if [[ $# -eq 0 ]]; then echo "Error: --output requires a file argument" >&2; exit 1; fi
      OUTPUT="$1"; shift ;;
    --auto-keystore) USE_AUTO_KEYSTORE=true; USE_DEBUG_KEY=false; shift ;;
    --debug-key)     USE_DEBUG_KEY=true; USE_AUTO_KEYSTORE=false; shift ;;
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
    --single-apk)    SINGLE_APK=true; shift ;;
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

# Auto-detect XAPK origin
IS_XAPK=false
XAPK_ORIGIN_DIR="$DECODED_DIR/.xapk-origin"
if [[ -f "$XAPK_ORIGIN_DIR/metadata.json" ]]; then
  IS_XAPK=true
fi

# Auto-detect merged marker from merge-splits.sh
if [[ -f "$XAPK_ORIGIN_DIR/.merged" ]]; then
  SINGLE_APK=true
  echo "[INFO] Detected .xapk-origin/.merged marker — will produce a single merged APK"
fi

# Default output name — .xapk if original was XAPK (and not merging), .apk otherwise
if [[ -z "$OUTPUT" ]]; then
  local_dir="${DECODED_DIR%/}"
  if [[ "$IS_XAPK" == true ]] && [[ "$SINGLE_APK" == false ]]; then
    OUTPUT="${local_dir}-neutralized.xapk"
  else
    OUTPUT="${local_dir}-neutralized.apk"
  fi
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

# XAPK requires apksigner (v2/v3 signatures needed for split APKs on Android 7+)
if [[ "$IS_XAPK" == true ]] && [[ "$DO_SIGN" == true ]] && [[ "$SIGNER" != "apksigner" ]]; then
  fail "XAPK rebuild requires apksigner for APK Signature Scheme v2/v3."
  echo "  jarsigner only supports v1 signatures, which do not work with split APKs on Android 7+." >&2
  echo "  Install apksigner (part of Android SDK build-tools) or use --no-sign." >&2
  exit 1
fi

# XAPK rebuild requires zip
if [[ "$IS_XAPK" == true ]]; then
  if ! command -v zip &>/dev/null; then
    fail "XAPK rebuild requires 'zip' command to assemble the final XAPK."
    echo "  Install zip: apt install zip / brew install zip" >&2
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
  # Remove .smali.bak files that cause apktool warnings during rebuild
  find "$DECODED_DIR" -name "*.smali.bak" -delete 2>/dev/null || true
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
  if [[ "$IS_XAPK" == true ]]; then
    # For unsigned XAPK, just output the base APK — cannot assemble unsigned XAPK
    cp "$ALIGNED_APK" "$OUTPUT"
    ok "Unsigned base APK saved to: $OUTPUT"
    echo "BUILD_OK:$OUTPUT"
    echo
    echo "WARNING: APK is unsigned and cannot be installed without signing."
    echo "         XAPK assembly skipped (split APKs require signing for Android 7+)."
    echo "         Split APKs are preserved in: $XAPK_ORIGIN_DIR/splits/"
  else
    cp "$ALIGNED_APK" "$OUTPUT"
    ok "Unsigned APK saved to: $OUTPUT"
    echo "BUILD_OK:$OUTPUT"
    echo
    echo "WARNING: APK is unsigned and cannot be installed without signing."
  fi
  exit 0
fi

# Resolve keystore
KEYSTORE_SOURCE=""

if [[ "$USE_AUTO_KEYSTORE" == true ]]; then
  # Priority 1: Android SDK standard debug keystore
  ANDROID_DEBUG_KS="$HOME/.android/debug.keystore"
  if [[ -f "$ANDROID_DEBUG_KS" ]]; then
    KEYSTORE="$ANDROID_DEBUG_KS"
    KEY_ALIAS="androiddebugkey"
    KEY_PASS="android"
    STORE_PASS="android"
    KEYSTORE_SOURCE="debug-standard"
    info "Using Android SDK debug keystore: $KEYSTORE"
  fi

  # Priority 2: Previous neutralizer debug keystore
  if [[ -z "$KEYSTORE_SOURCE" ]]; then
    PREV_DEBUG_KS="$DECODED_DIR/.neutralizer-debug.keystore"
    if [[ -f "$PREV_DEBUG_KS" ]]; then
      KEYSTORE="$PREV_DEBUG_KS"
      KEYSTORE_SOURCE="debug-previous"
      info "Using previous neutralizer debug keystore: $KEYSTORE"
    fi
  fi

  # Priority 3: Generate new debug keystore (fallback)
  if [[ -z "$KEYSTORE_SOURCE" ]]; then
    KEYSTORE="$DECODED_DIR/.neutralizer-debug.keystore"
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
    KEYSTORE_SOURCE="debug-generated"
  fi
elif [[ "$USE_DEBUG_KEY" == true ]]; then
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
  KEYSTORE_SOURCE="debug-generated"
else
  # Custom keystore provided via --keystore
  KEYSTORE_SOURCE="custom"
fi

if [[ ! -f "$KEYSTORE" ]]; then
  fail "Keystore not found: $KEYSTORE"
  exit 1
fi

echo "KEYSTORE_USED:$KEYSTORE"
echo "KEYSTORE_SOURCE:$KEYSTORE_SOURCE"
echo "KEYSTORE_ALIAS:$KEY_ALIAS"

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
# Step 5: XAPK assembly (if original was XAPK)
# =====================================================================

if [[ "$IS_XAPK" == true ]] && [[ "$DO_SIGN" == true ]] && [[ "$SINGLE_APK" == false ]]; then
  echo
  echo "=== Assembling XAPK ==="

  XAPK_WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/xapk-rebuild-XXXXXX")
  xapk_cleanup() { rm -rf "$XAPK_WORKDIR"; }
  trap xapk_cleanup EXIT

  # Read base APK name from metadata
  BASE_APK_NAME=$(sed -n 's/.*"base_apk"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$XAPK_ORIGIN_DIR/metadata.json" | head -1)
  if [[ -z "$BASE_APK_NAME" ]]; then
    BASE_APK_NAME="base.apk"
  fi

  # Copy signed base APK
  cp "$OUTPUT" "$XAPK_WORKDIR/$BASE_APK_NAME"
  info "Copied signed base APK as $BASE_APK_NAME"

  # Re-sign and copy each split APK
  if [[ -d "$XAPK_ORIGIN_DIR/splits" ]]; then
    for split_apk in "$XAPK_ORIGIN_DIR/splits/"*.apk; do
      if [[ ! -f "$split_apk" ]]; then continue; fi
      split_name=$(basename "$split_apk")
      info "Signing split: $split_name"
      apksigner sign \
        --ks "$KEYSTORE" \
        --ks-key-alias "$KEY_ALIAS" \
        --ks-pass "pass:$STORE_PASS" \
        --key-pass "pass:$KEY_PASS" \
        --out "$XAPK_WORKDIR/$split_name" \
        "$split_apk"
      echo "SPLIT_SIGNED:$split_name"
    done
  fi

  # Copy manifest.json and icon from .xapk-origin/
  if [[ -f "$XAPK_ORIGIN_DIR/manifest.json" ]]; then
    cp "$XAPK_ORIGIN_DIR/manifest.json" "$XAPK_WORKDIR/"
  fi
  for icon_file in "$XAPK_ORIGIN_DIR"/icon.png "$XAPK_ORIGIN_DIR"/icon.jpg; do
    if [[ -f "$icon_file" ]]; then
      cp "$icon_file" "$XAPK_WORKDIR/"
      break
    fi
  done

  # Assemble XAPK (zip with no compression for APKs)
  # Make output path absolute for the subshell cd
  XAPK_OUTPUT=$(realpath -m "$OUTPUT" 2>/dev/null || echo "$(pwd)/$OUTPUT")
  # Remove the base APK output (it's now inside the XAPK)
  rm -f "$XAPK_OUTPUT" 2>/dev/null || true

  (cd "$XAPK_WORKDIR" && zip -r -0 "$XAPK_OUTPUT" . 2>&1) || {
    fail "Failed to assemble XAPK archive"
    exit 1
  }

  if [[ ! -f "$XAPK_OUTPUT" ]]; then
    fail "XAPK output not found at: $XAPK_OUTPUT"
    exit 1
  fi
  # Update OUTPUT to the absolute path used
  OUTPUT="$XAPK_OUTPUT"

  ok "XAPK assembled: $XAPK_OUTPUT"
  echo "XAPK_ASSEMBLED:$XAPK_OUTPUT"

  # Clean up workdir
  xapk_cleanup
  trap - EXIT
fi

# =====================================================================
# Summary
# =====================================================================

echo
echo "=== Rebuild Complete ==="

if [[ "$IS_XAPK" == true ]] && [[ "$SINGLE_APK" == false ]]; then
  echo "Output XAPK: $OUTPUT"
elif [[ "$IS_XAPK" == true ]] && [[ "$SINGLE_APK" == true ]]; then
  echo "Output APK (merged from XAPK): $OUTPUT"
else
  echo "Output APK: $OUTPUT"
fi

if [[ "$DO_SIGN" == true ]]; then
  SIGN_DESC="$KEYSTORE_SOURCE"
  case "$KEYSTORE_SOURCE" in
    debug-standard)  SIGN_DESC="Android SDK debug key (~/.android/debug.keystore)" ;;
    debug-previous)  SIGN_DESC="previous neutralizer debug key" ;;
    debug-generated) SIGN_DESC="auto-generated debug key" ;;
    custom)          SIGN_DESC="custom keystore ($KEYSTORE)" ;;
  esac
  echo "Signed with: $SIGNER ($SIGN_DESC)"
fi

OUTPUT_SIZE=$(stat -f%z "$OUTPUT" 2>/dev/null || stat -c%s "$OUTPUT" 2>/dev/null || echo "unknown")
echo "Output size: $OUTPUT_SIZE bytes"

if [[ "$BUILD_USED_NO_RES" == true ]]; then
  echo
  echo "NOTE: Resources were NOT recompiled (--no-res was used)."
  echo "      The APK uses original resources. Manifest XML changes (e.g., android:enabled)"
  echo "      may not be reflected unless they were applied before decode."
fi

echo
echo "WARNING: Play Integrity / SafetyNet will FAIL — expected for enterprise sideloading."
if [[ "$IS_XAPK" == true ]] && [[ "$SINGLE_APK" == false ]]; then
  echo "Install via: adb install-multiple <base.apk> <split1.apk> <split2.apk> ..."
  echo "         or: unzip the XAPK and run: adb install-multiple *.apk"
elif [[ "$IS_XAPK" == true ]] && [[ "$SINGLE_APK" == true ]]; then
  echo "Install via: adb install $OUTPUT"
  echo
  echo "NOTE: This is a merged single APK from an XAPK split bundle."
  echo "      Some locale/density-specific resources may use defaults."
  echo "      Test thoroughly on target devices."
else
  echo "Install via: adb install $OUTPUT"
fi

exit 0
