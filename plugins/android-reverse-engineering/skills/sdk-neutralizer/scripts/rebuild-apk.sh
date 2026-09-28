#!/usr/bin/env bash
# rebuild-apk.sh — Rebuild and sign a decoded APK directory
#
# Pipeline: apktool b → zipalign (page-aligns stored .so) → sign → verify
#           (signature + ZIP alignment) → move into place
#
# The output is always a single APK. Only directories decoded with the
# deprecated `decode-apk.sh --keep-splits` (.xapk-origin/) are reassembled
# into an XAPK.
#
# Portable: bash 3.2+ (macOS) and BSD/GNU userland.
#
# Exit codes:
#   0 — success
#   1 — error (unknown option, missing tool, build/sign failure, misaligned output)
set -euo pipefail

# Ensure user-local bin is in PATH (install-dep.sh installs tools there)
if [[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

# Resolve user-supplied environment paths up front: the tools later run from a
# temporary working directory, where relative paths would no longer resolve.
abs_existing() {
  if [[ -d "$1" ]]; then
    (cd "$1" && pwd -P)
  elif [[ -e "$1" ]]; then
    printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"
  else
    case "$1" in
      /*) printf '%s\n' "$1" ;;
      *)  printf '%s/%s\n' "$(pwd -P)" "$1" ;;   # not created yet: anchor to the caller's dir
    esac
  fi
}
for env_var in APKEDITOR_JAR ANDROID_HOME ANDROID_SDK_ROOT TMPDIR XDG_CONFIG_HOME; do
  env_val="${!env_var:-}"
  if [[ -n "$env_val" ]]; then
    export "$env_var=$(abs_existing "$env_val")"
  fi
done

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
INSTALL_DEP="$(cd "$SCRIPT_DIR/../../android-reverse-engineering/scripts" 2>/dev/null && pwd -P)/install-dep.sh"

# Stable, user-level debug key: every build signed with it can be installed
# over the previous one (a per-directory key could not).
USER_KS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/android-re"
USER_KS="$USER_KS_DIR/neutralizer-debug.keystore"

usage() {
  cat <<EOF
Usage: rebuild-apk.sh <decoded-dir> [OPTIONS]

Rebuild an apktool-decoded APK directory into a signed, installable APK.
Split bundles are merged by decode-apk.sh (APKEditor) before decoding, so the
result is always one APK. Stored native libraries (.so) are page-aligned
(zipalign -P 16 when supported, otherwise -p) and all stored entries are
checked after signing.

Directories decoded with the deprecated 'decode-apk.sh --keep-splits'
(.xapk-origin/) are reassembled into an XAPK instead (deprecated, will be removed).

Arguments:
  <decoded-dir>   Path to the apktool-decoded APK directory

Options:
  -o, --output <file>     Output path (default: <decoded-dir>-neutralized.apk)
  --auto-keystore         Sign with the stable user-level neutralizer debug key,
                          created once and then reused:
                          $USER_KS
  --debug-key             Same as --auto-keystore (the default)
  --keystore <file>       Custom keystore, e.g. ~/.android/debug.keystore with
                          --key-alias androiddebugkey (takes precedence)
  --key-alias <alias>     Key alias within the keystore (default: key0)
  --key-pass <password>   Key password (default: android)
  --store-pass <password> Keystore password (default: android)
  --no-sign               Skip signing (output unsigned APK)
  --zipalign              Run zipalign (default)
  --no-zipalign           Skip zipalign
  -h, --help              Show this help message

Tools: zipalign and apksigner are taken from Android SDK build-tools
(\$ANDROID_HOME, \$ANDROID_SDK_ROOT, ~/Android/Sdk, ~/Library/Android/sdk,
~/.local/share/android-sdk) or PATH. Install: install-dep.sh build-tools.

Output:
  BUILD_OK:<apk>
  ZIPALIGN_OK:16k|4k
  KEYSTORE_USED:<path>
  KEYSTORE_SOURCE:debug-user|debug-generated|custom
  KEYSTORE_ALIAS:<alias>
  SIGN_OK:<output-apk>
  VERIFY_OK:<output-apk>
  ALIGN_OK:<n>:16k|4k|none|n/a  (n = stored .so files; the stored .so page alignment)
  ALIGN_WARNING:not-16k         (stored .so only 4 KB aligned: 16 KB-page devices refuse it)
  ALIGN_WARNING:so-not-page-aligned (stored .so not page-aligned; accepted only because
                                 extractNativeLibs is not "false" — the installer extracts them)
  ALIGN_FAIL:<entry>            (misaligned stored entry, max 20 lines — exit 1; the
                                 APK is left as <output>.misaligned, never at <output>)
  ABI_WARNING:32bit-only:<abis> (no arm64-v8a/x86_64 native code)
  DEPRECATION_WARNING:xapk-output, SPLIT_SIGNED:<file>, XAPK_ASSEMBLED:<xapk>
                                (--keep-splits directories only)
EOF
  exit "${1:-0}"
}

# =====================================================================
# Argument parsing
# =====================================================================

DECODED_DIR=""
OUTPUT=""
USE_DEBUG_KEY=false
USE_AUTO_KEYSTORE=false
KEYSTORE=""
KEY_ALIAS="key0"
KEY_PASS="android"
STORE_PASS="android"
DO_SIGN=true
DO_ZIPALIGN=true
SINGLE_APK_FLAG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      shift
      if [[ $# -eq 0 ]]; then echo "Error: --output requires a file argument" >&2; exit 1; fi
      OUTPUT="$1"; shift ;;
    --auto-keystore) USE_AUTO_KEYSTORE=true; shift ;;
    --debug-key)     USE_DEBUG_KEY=true; shift ;;
    --keystore)
      shift
      if [[ $# -eq 0 ]]; then echo "Error: --keystore requires a file argument" >&2; exit 1; fi
      KEYSTORE="$1"; shift ;;
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
    --single-apk)    SINGLE_APK_FLAG=true; shift ;;
    --no-sign)       DO_SIGN=false; shift ;;
    --no-res)
      echo "Error: --no-res was removed." >&2
      echo "  apktool 2.10 'b' has no such option (it is a decode flag), so it silently" >&2
      echo "  rebuilt everything again. A real resource-less rebuild would ship the original" >&2
      echo "  binary manifest and drop the disabled manifest components. Fix the reported" >&2
      echo "  resource error instead (split bundles: decode without --keep-splits)." >&2
      exit 1 ;;
    --zipalign)      DO_ZIPALIGN=true; shift ;;
    --no-zipalign)   DO_ZIPALIGN=false; shift ;;
    -h|--help)       usage ;;
    -*)              echo "Error: Unknown option $1" >&2; usage 1 >&2 ;;
    *)               DECODED_DIR="$1"; shift ;;
  esac
done

if [[ -z "$DECODED_DIR" ]]; then
  echo "Error: No decoded directory specified." >&2
  usage 1 >&2
fi

if [[ ! -d "$DECODED_DIR" ]]; then
  echo "Error: Directory not found: $DECODED_DIR" >&2
  exit 1
fi

# Keystore: --keystore (custom) wins; --auto-keystore / --debug-key (default) both use
# the stable user-level neutralizer key, so every build installs over the previous one.
KEYSTORE_MODE="debug"
if [[ -n "$KEYSTORE" ]]; then
  KEYSTORE_MODE="custom"
fi

info()  { echo "[INFO] $*"; }
ok()    { echo "[OK] $*"; }
warn()  { echo "[WARN] $*" >&2; }
fail()  { echo "[FAIL] $*" >&2; }

# Non-ASCII detection (byte-wise, independent of the current locale)
has_non_ascii() { local LC_ALL=C; case "$1" in *[!\ -~]*) return 0 ;; esac; return 1; }
# Non-ASCII paths only work when Java runs with a UTF-8 locale (it encodes file
# names with the locale charset; LANG=C breaks them, even through symlinks).
# If needed, switch the tools to an installed UTF-8 locale, or fail clearly.
ensure_utf8_locale() {
  local p need=false l avail
  for p in "$@"; do
    if has_non_ascii "$p"; then need=true; fi
  done
  [[ "$need" == true ]] || return 0
  case "$(locale charmap 2>/dev/null || true)" in
    UTF-8|utf-8|UTF8|utf8) return 0 ;;
  esac
  avail=$(locale -a 2>/dev/null || true)
  for l in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    case $'\n'"$avail"$'\n' in
      *$'\n'"$l"$'\n'*)
        export LC_ALL="$l"
        echo "[INFO] Non-ASCII path with a non-UTF-8 locale: running the tools with LC_ALL=$l"
        return 0 ;;
    esac
  done
  echo "Error: a path contains non-ASCII characters but no UTF-8 locale is available," >&2
  echo "       so Java cannot open it. Set LANG to a UTF-8 locale or use an ASCII path." >&2
  exit 1
}


DECODED_ABS=$(cd "$DECODED_DIR" && pwd -P)

# Legacy XAPK origin (decode-apk.sh --keep-splits)
IS_XAPK=false
XAPK_ORIGIN_DIR="$DECODED_ABS/.xapk-origin"
if [[ -f "$XAPK_ORIGIN_DIR/metadata.json" ]]; then
  IS_XAPK=true
  if [[ "$SINGLE_APK_FLAG" == true ]]; then
    fail "--single-apk cannot turn a --keep-splits directory into one APK (the splits were never merged)."
    echo "  Decode the bundle again without --keep-splits: decode-apk.sh merges the splits with APKEditor." >&2
    exit 1
  fi
  echo "DEPRECATION_WARNING:xapk-output"
  warn "XAPK output (from decode-apk.sh --keep-splits) is deprecated and will be removed."
  warn "The decoded base lacks split-only resources (@null references) and may crash."
  warn "Decode the bundle again without --keep-splits to get a single merged APK."
elif [[ "$SINGLE_APK_FLAG" == true ]]; then
  info "--single-apk is the default now (flag ignored)."
fi

MERGE_META="$DECODED_ABS/.merged-from-splits.json"

# Default output name — .xapk only for legacy --keep-splits directories
if [[ -z "$OUTPUT" ]]; then
  if [[ "$IS_XAPK" == true ]]; then
    OUTPUT="${DECODED_ABS}-neutralized.xapk"
  else
    OUTPUT="${DECODED_ABS}-neutralized.apk"
  fi
fi
mkdir -p "$(dirname "$OUTPUT")"
OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd -P)/$(basename "$OUTPUT")"

# =====================================================================
# Tool checks
# =====================================================================

for tool in apktool java; do
  if ! command -v "$tool" &>/dev/null; then
    fail "$tool is not installed. Run: bash \"$INSTALL_DEP\" $tool"
    exit 1
  fi
done
if ! command -v unzip &>/dev/null; then
  fail "unzip is not installed (install: apt install unzip / brew install unzip)."
  exit 1
fi

latest_build_tools_dir() {
  local sdk="$1" v
  [[ -n "$sdk" ]] && [[ -d "$sdk/build-tools" ]] || return 1
  v=$(ls -1 "$sdk/build-tools" 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
  [[ -n "$v" ]] && [[ -d "$sdk/build-tools/$v" ]] || return 1
  echo "$sdk/build-tools/$v"
}
SDK_ROOTS=("${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "$HOME/.local/share/android-sdk")

# zipalign: PATH, then SDK build-tools; prefer one that supports -P (16 KB pages)
ZIPALIGN_CMD=""
ZIPALIGN_PAGE=""     # 16k | 4k
za_candidates=()
if command -v zipalign &>/dev/null; then
  za_candidates+=("$(command -v zipalign)")
fi
for sdk in "${SDK_ROOTS[@]}"; do
  bt=$(latest_build_tools_dir "$sdk" || true)
  if [[ -n "$bt" ]] && [[ -x "$bt/zipalign" ]]; then za_candidates+=("$bt/zipalign"); fi
done
if [[ ${#za_candidates[@]} -gt 0 ]]; then
  for za in "${za_candidates[@]}"; do
    za_usage=$("$za" 2>&1 || true)
    case "$za_usage" in
      *"-P <pagesize"*) ZIPALIGN_CMD="$za"; ZIPALIGN_PAGE="16k"; break ;;
    esac
    if [[ -z "$ZIPALIGN_CMD" ]]; then ZIPALIGN_CMD="$za"; ZIPALIGN_PAGE="4k"; fi
  done
fi

# apksigner: SDK build-tools first (current versions), then PATH
APKSIGNER_CMD=""
for sdk in "${SDK_ROOTS[@]}"; do
  bt=$(latest_build_tools_dir "$sdk" || true)
  if [[ -n "$bt" ]] && [[ -x "$bt/apksigner" ]]; then APKSIGNER_CMD="$bt/apksigner"; break; fi
done
if [[ -z "$APKSIGNER_CMD" ]] && command -v apksigner &>/dev/null; then
  APKSIGNER_CMD=$(command -v apksigner)
fi

TARGET_SDK=$(sed -n "s/^[[:space:]]*targetSdkVersion:[[:space:]]*'\{0,1\}\([0-9]*\).*/\1/p" "$DECODED_ABS/apktool.yml" 2>/dev/null | sed -n 1p || true)

SIGNER=""
if [[ "$DO_SIGN" == true ]]; then
  if [[ -n "$APKSIGNER_CMD" ]]; then
    SIGNER="apksigner"
  elif command -v jarsigner &>/dev/null; then
    if [[ -n "$TARGET_SDK" ]] && (( TARGET_SDK >= 30 )); then
      fail "apksigner not found and this app targets SDK $TARGET_SDK: Android 11+ refuses v1-only (jarsigner) signatures."
      echo "  Install Android build-tools: bash \"$INSTALL_DEP\" build-tools --accept-android-sdk-license" >&2
      exit 1
    fi
    SIGNER="jarsigner"
    warn "**************************************************************************"
    warn "apksigner not found — signing with jarsigner (v1 signature ONLY)."
    warn "targetSdk: ${TARGET_SDK:-unknown}. Installs fail if it is 30 or higher."
    warn "Install Android build-tools: bash \"$INSTALL_DEP\" build-tools --accept-android-sdk-license"
    warn "**************************************************************************"
  else
    fail "Neither apksigner nor jarsigner found."
    echo "  Install Android build-tools: bash \"$INSTALL_DEP\" build-tools --accept-android-sdk-license (or use --no-sign)" >&2
    exit 1
  fi
fi

# XAPK requires apksigner (v2/v3 signatures needed for split APKs on Android 7+)
if [[ "$IS_XAPK" == true ]] && [[ "$DO_SIGN" == true ]] && [[ "$SIGNER" != "apksigner" ]]; then
  fail "XAPK rebuild requires apksigner for APK Signature Scheme v2/v3."
  exit 1
fi
if [[ "$IS_XAPK" == true ]] && ! command -v zip &>/dev/null; then
  fail "XAPK rebuild requires 'zip' command to assemble the final XAPK."
  echo "  Install zip: apt install zip / brew install zip" >&2
  exit 1
fi

# zipalign <in> <out>: 4-byte alignment + page-aligned stored .so files
run_zipalign() {
  if [[ "$ZIPALIGN_PAGE" == "16k" ]]; then
    "$ZIPALIGN_CMD" -f -P 16 4 "$1" "$2"
  else
    "$ZIPALIGN_CMD" -f -p 4 "$1" "$2"
  fi
}

if [[ -n "$KEYSTORE" ]] && [[ -f "$KEYSTORE" ]]; then
  KEYSTORE="$(cd "$(dirname "$KEYSTORE")" && pwd -P)/$(basename "$KEYSTORE")"
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/apk-rebuild-XXXXXX")
cleanup_work() { rm -rf "$WORK"; }
trap cleanup_work EXIT
# Every path is absolute from here on: run the tools from an ASCII working
# directory (Java cannot even start in a non-ASCII cwd under LANG=C).
cd "$WORK"

# Intermediate files live in $WORK; the result is moved into place at the end.
ensure_utf8_locale "$DECODED_ABS" "$USER_KS_DIR" "${KEYSTORE:-}"
SRC_DIR="$DECODED_ABS"

# =====================================================================
# Step 1: Build APK with apktool
# =====================================================================

echo "=== Rebuilding APK ==="
echo "Source: $DECODED_ABS"
echo "Output: $OUTPUT"
echo

info "Running apktool build..."
# Remove .smali.bak files that cause apktool warnings during rebuild
find "$DECODED_ABS" -name "*.smali.bak" -delete 2>/dev/null || true
BUILT_APK="$WORK/built.apk"
if ! apktool b "$SRC_DIR" -o "$BUILT_APK" 2>&1 || [[ ! -f "$BUILT_APK" ]]; then
  fail "apktool build failed."
  echo "Tip: If this is a framework error, try: rm -f ~/.local/share/apktool/framework/1.apk" >&2
  echo "Tip: Resource errors on a split bundle decoded with --keep-splits are expected (@null);" >&2
  echo "     decode it again without --keep-splits." >&2
  exit 1
fi
ok "APK built: $BUILT_APK"
echo "BUILD_OK:$BUILT_APK"

# Stored (uncompressed) .so + extractNativeLibs="false": the installer maps the
# libraries straight from the APK, so they must be page-aligned.
STORED_SO=$(unzip -v "$BUILT_APK" 2>/dev/null | awk '$2 == "Stored" && $NF ~ /^lib\/.*\.so$/ {n++} END {print n+0}')
NEED_PAGE_ALIGN=false
if [[ "$STORED_SO" -gt 0 ]] && grep -q 'android:extractNativeLibs="false"' "$DECODED_ABS/AndroidManifest.xml" 2>/dev/null; then
  NEED_PAGE_ALIGN=true
fi
if [[ "$NEED_PAGE_ALIGN" == true ]] && [[ -z "$ZIPALIGN_CMD" ]]; then
  fail "zipalign is required: $STORED_SO stored native librar(y/ies) with extractNativeLibs=\"false\" must be page-aligned."
  echo "  Install Android build-tools: bash \"$INSTALL_DEP\" build-tools --accept-android-sdk-license" >&2
  exit 1
fi
if [[ "$DO_ZIPALIGN" == true ]] && [[ -z "$ZIPALIGN_CMD" ]]; then
  warn "zipalign not found — skipping alignment (no stored native libraries need it)."
  DO_ZIPALIGN=false
fi
if [[ "$DO_ZIPALIGN" == false ]] && [[ "$NEED_PAGE_ALIGN" == true ]]; then
  warn "--no-zipalign with $STORED_SO stored native librar(y/ies): the alignment check below decides."
fi

# =====================================================================
# Step 2: Zipalign (before apksigner; jarsigner breaks alignment, so it
#         is aligned after signing instead — see Step 3)
# =====================================================================

ALIGNED_APK="$BUILT_APK"
if [[ "$DO_ZIPALIGN" == true ]] && [[ "$SIGNER" != "jarsigner" ]]; then
  if [[ "$ZIPALIGN_PAGE" == "16k" ]]; then
    info "Running zipalign -P 16 (16 KB page alignment for stored native libraries)..."
  else
    info "Running zipalign -p (4 KB page alignment; this zipalign has no -P 16)..."
  fi
  ALIGNED_APK="$WORK/aligned.apk"
  if ! run_zipalign "$BUILT_APK" "$ALIGNED_APK"; then
    fail "zipalign failed."
    exit 1
  fi
  ok "Zipaligned ($ZIPALIGN_CMD)"
  echo "ZIPALIGN_OK:$ZIPALIGN_PAGE"
fi

# =====================================================================
# Alignment and ABI checks
# =====================================================================

# check_alignment <apk>: every stored entry 4-byte aligned, stored lib/*.so
# page-aligned. Prints ALIGN_OK / ALIGN_WARNING / ALIGN_FAIL; returns 1 on failure.
# A misaligned .so is fatal only when extractNativeLibs="false" (NEED_PAGE_ALIGN).
ALIGN_FAIL_MAX=20
check_alignment() {
  local apk="$1" res="" mode=""
  if command -v python3 &>/dev/null; then
    mode="python"
    res=$(python3 - "$apk" <<'PYEOF'
import struct, sys, zipfile
so = 0
not16 = 0
with open(sys.argv[1], "rb") as fh, zipfile.ZipFile(sys.argv[1]) as zf:
    for i in zf.infolist():
        if i.compress_type != zipfile.ZIP_STORED:
            continue
        fh.seek(i.header_offset)
        h = fh.read(30)
        n, e = struct.unpack("<HH", h[26:30])
        off = i.header_offset + 30 + n + e
        if i.filename.startswith("lib/") and i.filename.endswith(".so"):
            so += 1
            if off % 4096:
                print("BADSO " + i.filename)
            elif off % 16384:
                not16 += 1
        elif off % 4:
            print("BAD4 " + i.filename)
print("SO %d" % so)
print("NOT16 %d" % not16)
PYEOF
) || mode=""
  fi
  if [[ -z "$mode" ]] && [[ -n "$ZIPALIGN_CMD" ]]; then
    mode="zipalign"
    local out line name
    out=$("$ZIPALIGN_CMD" -c -v -p 4 "$apk" 2>&1 || true)
    res=""
    while IFS= read -r line; do
      case "$line" in
        *"(BAD"*)
          name=$(echo "$line" | sed -n 's/^[[:space:]]*[0-9][0-9]*[[:space:]]\(.*\) (BAD.*$/\1/p')
          case "$name" in
            lib/*.so) res="$res"$'\n'"BADSO $name" ;;
            *)        res="$res"$'\n'"BAD4 $name" ;;
          esac ;;
      esac
    done <<< "$out"
    res="$res"$'\n'"SO $(unzip -v "$apk" 2>/dev/null | awk '$2 == "Stored" && $NF ~ /^lib\/.*\.so$/ {n++} END {print n+0}')"
    if [[ "$ZIPALIGN_PAGE" == "16k" ]] && "$ZIPALIGN_CMD" -c -P 16 4 "$apk" >/dev/null 2>&1; then
      res="$res"$'\n'"NOT16 0"
    else
      res="$res"$'\n'"NOT16 unknown"
    fi
  fi
  if [[ -z "$mode" ]]; then
    warn "Cannot verify ZIP alignment (no python3, no zipalign)."
    return 0
  fi

  local so_count=0 not16=0 bad4=0 badso=0 shown=0 fatal=false kind entry
  while IFS=' ' read -r kind entry; do
    case "$kind" in
      SO)    so_count="$entry" ;;
      NOT16) not16="$entry" ;;
      BAD4)  bad4=$((bad4 + 1)) ;;
      BADSO) badso=$((badso + 1)) ;;
    esac
  done <<< "$res"
  if (( bad4 > 0 )); then fatal=true; fi
  if (( badso > 0 )) && [[ "$NEED_PAGE_ALIGN" == true ]]; then fatal=true; fi

  if (( bad4 + badso > 0 )); then
    if [[ "$fatal" == true ]]; then
      fail "Misaligned stored entries ($badso native libraries, $bad4 other) — the installer will reject this APK:"
    else
      warn "$badso stored native librar(y/ies) not page-aligned (extractNativeLibs is not \"false\", so the installer extracts them)."
    fi
    local want
    for want in BADSO BAD4; do   # native libraries first
      while IFS=' ' read -r kind entry; do
        if [[ "$kind" == "$want" ]]; then
          if (( shown < ALIGN_FAIL_MAX )); then
            echo "  $entry" >&2
            if [[ "$fatal" == true ]]; then echo "ALIGN_FAIL:$entry"; fi
          fi
          shown=$((shown + 1))
        fi
      done <<< "$res"
    done
    if (( shown > ALIGN_FAIL_MAX )); then
      echo "  ... and $((shown - ALIGN_FAIL_MAX)) more" >&2
    fi
    if [[ "$fatal" == true ]]; then return 1; fi
  fi

  if [[ "$so_count" -eq 0 ]]; then
    ok "All stored entries aligned (no stored native libraries)"
    echo "ALIGN_OK:0:n/a"
  elif (( badso > 0 )); then
    # Not fatal (extractNativeLibs is not "false"), but not page-aligned either
    echo "ALIGN_OK:$so_count:none"
    echo "ALIGN_WARNING:so-not-page-aligned"
  elif [[ "$not16" == "0" ]]; then
    ok "All stored entries aligned; $so_count native librar(y/ies) 16 KB page-aligned"
    echo "ALIGN_OK:$so_count:16k"
  else
    ok "All stored entries aligned; $so_count native librar(y/ies) 4 KB page-aligned"
    echo "ALIGN_OK:$so_count:4k"
    warn "Native libraries are not 16 KB aligned: devices with 16 KB pages will refuse the APK."
    echo "ALIGN_WARNING:not-16k"
  fi
  return 0
}

# 64-bit-only phones (e.g. Galaxy S25, Pixel 7 and later) refuse APKs whose
# native code is 32-bit only.
check_abis() {
  local apk="$1" abis
  abis=$(unzip -Z1 "$apk" 2>/dev/null | sed -n 's#^lib/\([^/]*\)/.*#\1#p' | sort -u | tr '\n' ',' | sed 's/,$//')
  if [[ -z "$abis" ]]; then
    return 0
  fi
  info "Native ABIs: $abis"
  case ",$abis," in
    *,arm64-v8a,*|*,x86_64,*) ;;
    *)
      warn "The APK contains only 32-bit native code ($abis)."
      echo "       Many recent phones (e.g. Galaxy S25, Pixel 7 and later) are 64-bit only and" >&2
      echo "       will refuse to install it. Use an arm64-v8a build of the app if one exists." >&2
      echo "ABI_WARNING:32bit-only:$abis"
      ;;
  esac
}

# Move a finished file into place; a failed alignment check parks it as .misaligned
place_output() {
  local src="$1" dest="$2"
  mv -f "$src" "$dest"
  if [[ -f "$src.idsig" ]]; then
    mv -f "$src.idsig" "$dest.idsig"
  else
    rm -f "$dest.idsig"
  fi
}

# =====================================================================
# Step 3: Sign APK
# =====================================================================

if [[ "$DO_SIGN" == false ]]; then
  if ! check_alignment "$ALIGNED_APK"; then
    place_output "$ALIGNED_APK" "$OUTPUT.misaligned"
    echo "  Output left for inspection only — do not install it: $OUTPUT.misaligned" >&2
    exit 1
  fi
  check_abis "$ALIGNED_APK"
  place_output "$ALIGNED_APK" "$OUTPUT"
  if [[ "$IS_XAPK" == true ]]; then
    ok "Unsigned base APK saved to: $OUTPUT"
    echo "BUILD_OK:$OUTPUT"
    echo
    echo "WARNING: APK is unsigned and cannot be installed without signing."
    echo "         XAPK assembly skipped (split APKs require signing for Android 7+)."
    echo "         Split APKs are preserved in: $XAPK_ORIGIN_DIR/splits/"
  else
    ok "Unsigned APK saved to: $OUTPUT"
    echo "BUILD_OK:$OUTPUT"
    echo
    echo "WARNING: APK is unsigned and cannot be installed without signing."
  fi
  exit 0
fi

# Create (once, race-safe) or reuse the user-level neutralizer debug keystore
use_user_keystore() {
  KEYSTORE="$USER_KS"
  KEY_ALIAS="key0"
  KEY_PASS="android"
  STORE_PASS="android"
  if [[ -f "$USER_KS" ]]; then
    KEYSTORE_SOURCE="debug-user"
    info "Using the user-level neutralizer debug keystore: $USER_KS"
    return 0
  fi
  (umask 077; mkdir -p "$USER_KS_DIR")
  local tmp_name=".neutralizer-debug.keystore.tmp.$$"
  rm -f "$USER_KS_DIR/$tmp_name"
  info "Generating the user-level neutralizer debug keystore (reused by later builds)..."
  if ! (umask 077; keytool -genkeypair \
      -keystore "$USER_KS_DIR/$tmp_name" \
      -alias "$KEY_ALIAS" \
      -keyalg RSA \
      -keysize 2048 \
      -validity 10000 \
      -storepass "$STORE_PASS" \
      -keypass "$KEY_PASS" \
      -dname "CN=SDK Neutralizer Debug Key, OU=Debug, O=Debug, L=Unknown, ST=Unknown, C=US" \
      >/dev/null 2>&1); then
    rm -f "$USER_KS_DIR/$tmp_name"
    fail "keytool could not generate $USER_KS"
    exit 1
  fi
  # Atomic publish: ln fails if another build created the key first
  if ln "$USER_KS_DIR/$tmp_name" "$USER_KS" 2>/dev/null; then
    KEYSTORE_SOURCE="debug-generated"
    ok "Debug keystore generated: $USER_KS"
  elif [[ ! -e "$USER_KS" ]] && mv -n "$USER_KS_DIR/$tmp_name" "$USER_KS" 2>/dev/null && [[ ! -e "$USER_KS_DIR/$tmp_name" ]]; then
    KEYSTORE_SOURCE="debug-generated"   # filesystem without hard links
    ok "Debug keystore generated: $USER_KS"
  else
    KEYSTORE_SOURCE="debug-user"
    info "Another build created the user-level keystore first — using it: $USER_KS"
  fi
  rm -f "$USER_KS_DIR/$tmp_name"
}

KEYSTORE_SOURCE=""
case "$KEYSTORE_MODE" in
  debug)  use_user_keystore ;;
  custom) KEYSTORE_SOURCE="custom" ;;
esac

if [[ ! -f "$KEYSTORE" ]]; then
  fail "Keystore not found: $KEYSTORE"
  exit 1
fi
KEYSTORE_JAVA="$KEYSTORE"

echo "KEYSTORE_USED:$KEYSTORE"
echo "KEYSTORE_SOURCE:$KEYSTORE_SOURCE"
echo "KEYSTORE_ALIAS:$KEY_ALIAS"

info "Signing APK with $SIGNER..."
FINAL_APK="$WORK/final.apk"

if [[ "$SIGNER" == "apksigner" ]]; then
  if ! "$APKSIGNER_CMD" sign \
      --ks "$KEYSTORE_JAVA" \
      --ks-key-alias "$KEY_ALIAS" \
      --ks-pass "pass:$STORE_PASS" \
      --key-pass "pass:$KEY_PASS" \
      --out "$FINAL_APK" \
      "$ALIGNED_APK"; then
    fail "apksigner sign failed."
    exit 1
  fi
else
  if ! jarsigner \
      -keystore "$KEYSTORE_JAVA" \
      -storepass "$STORE_PASS" \
      -keypass "$KEY_PASS" \
      -signedjar "$WORK/signed.apk" \
      "$ALIGNED_APK" \
      "$KEY_ALIAS"; then
    fail "jarsigner failed."
    exit 1
  fi
  # jarsigner rewrites the archive: align afterwards
  if [[ "$DO_ZIPALIGN" == true ]]; then
    info "Running zipalign after jarsigner..."
    run_zipalign "$WORK/signed.apk" "$FINAL_APK"
    echo "ZIPALIGN_OK:$ZIPALIGN_PAGE"
  else
    mv -f "$WORK/signed.apk" "$FINAL_APK"
  fi
fi

if [[ ! -f "$FINAL_APK" ]]; then
  fail "Signed APK not found."
  exit 1
fi

# =====================================================================
# Step 4: Verify signature and alignment, then move into place
# =====================================================================

info "Verifying signature..."
VERIFIED=false
if [[ "$SIGNER" == "apksigner" ]]; then
  if "$APKSIGNER_CMD" verify "$FINAL_APK" >/dev/null 2>&1; then
    ok "Signature verified (apksigner)"
    VERIFIED=true
  else
    warn "Signature verification returned warnings (may still be installable)"
  fi
else
  if jarsigner -verify "$FINAL_APK" >/dev/null 2>&1; then
    ok "Signature verified (jarsigner)"
    VERIFIED=true
  else
    warn "Signature verification returned warnings (may still be installable)"
  fi
fi

if ! check_alignment "$FINAL_APK"; then
  place_output "$FINAL_APK" "$OUTPUT.misaligned"
  echo "  Output left for inspection only — do not install it: $OUTPUT.misaligned" >&2
  exit 1
fi
check_abis "$FINAL_APK"

place_output "$FINAL_APK" "$OUTPUT"
rm -f "$OUTPUT.misaligned" "$OUTPUT.misaligned.idsig"
ok "APK signed: $OUTPUT"
echo "SIGN_OK:$OUTPUT"
if [[ "$VERIFIED" == true ]]; then
  echo "VERIFY_OK:$OUTPUT"
fi

# =====================================================================
# Step 5: XAPK assembly (deprecated --keep-splits directories only)
# =====================================================================

if [[ "$IS_XAPK" == true ]]; then
  echo
  echo "=== Assembling XAPK (deprecated) ==="

  XAPK_WORKDIR="$WORK/xapk"
  mkdir -p "$XAPK_WORKDIR"

  # Read base APK name from metadata
  BASE_APK_NAME=$(sed -n 's/.*"base_apk"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$XAPK_ORIGIN_DIR/metadata.json" | sed -n 1p)
  if [[ -z "$BASE_APK_NAME" ]]; then
    BASE_APK_NAME="base.apk"
  fi

  # The signed base APK moves inside the XAPK
  mv -f "$OUTPUT" "$XAPK_WORKDIR/$BASE_APK_NAME"
  rm -f "$OUTPUT.idsig"
  info "Added signed base APK as $BASE_APK_NAME"

  # Align, re-sign and check each split APK
  if [[ -d "$XAPK_ORIGIN_DIR/splits" ]]; then
    for split_apk in "$XAPK_ORIGIN_DIR/splits/"*.apk; do
      if [[ ! -f "$split_apk" ]]; then continue; fi
      split_name=$(basename "$split_apk")
      split_in="$WORK/split-src.apk"
      cp "$split_apk" "$split_in"
      if [[ "$DO_ZIPALIGN" == true ]]; then
        run_zipalign "$WORK/split-src.apk" "$WORK/split-in.apk"
        split_in="$WORK/split-in.apk"
      fi
      info "Signing split: $split_name"
      "$APKSIGNER_CMD" sign \
        --ks "$KEYSTORE_JAVA" \
        --ks-key-alias "$KEY_ALIAS" \
        --ks-pass "pass:$STORE_PASS" \
        --key-pass "pass:$KEY_PASS" \
        --out "$WORK/split-signed.apk" \
        "$split_in"
      if ! check_alignment "$WORK/split-signed.apk"; then
        fail "Split $split_name is misaligned after signing — XAPK not assembled."
        exit 1
      fi
      mv -f "$WORK/split-signed.apk" "$XAPK_WORKDIR/$split_name"
      rm -f "$WORK/split-signed.apk.idsig" "$WORK/split-src.apk" "$WORK/split-in.apk"
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

  # Assemble XAPK (zip with no compression), then move it into place
  (cd "$XAPK_WORKDIR" && zip -q -r -0 "$WORK/out.xapk" . 2>&1) || {
    fail "Failed to assemble XAPK archive"
    exit 1
  }
  mv -f "$WORK/out.xapk" "$OUTPUT"
  rm -f "$OUTPUT.idsig"

  ok "XAPK assembled: $OUTPUT"
  echo "XAPK_ASSEMBLED:$OUTPUT"
fi

# =====================================================================
# Summary
# =====================================================================

echo
echo "=== Rebuild Complete ==="

if [[ "$IS_XAPK" == true ]]; then
  echo "Output XAPK (deprecated format): $OUTPUT"
elif [[ -f "$MERGE_META" ]]; then
  echo "Output APK (split bundle merged with APKEditor): $OUTPUT"
else
  echo "Output APK: $OUTPUT"
fi

SIGN_DESC="$KEYSTORE_SOURCE"
case "$KEYSTORE_SOURCE" in
  debug-user)      SIGN_DESC="user-level neutralizer debug key ($KEYSTORE)" ;;
  debug-generated) SIGN_DESC="new user-level neutralizer debug key ($KEYSTORE)" ;;
  custom)          SIGN_DESC="custom keystore ($KEYSTORE)" ;;
esac
echo "Signed with: $SIGNER ($SIGN_DESC)"

OUTPUT_SIZE=$(wc -c < "$OUTPUT" | tr -d ' ')
echo "Output size: $OUTPUT_SIZE bytes"

echo
echo "WARNING: Play Integrity / SafetyNet will FAIL — expected for enterprise sideloading."
if [[ "$IS_XAPK" == true ]]; then
  echo "Install via: adb install-multiple <base.apk> <split1.apk> <split2.apk> ..."
  echo "         or: unzip the XAPK and run: adb install-multiple *.apk"
else
  echo "Install via: adb install \"$OUTPUT\""
fi

exit 0
