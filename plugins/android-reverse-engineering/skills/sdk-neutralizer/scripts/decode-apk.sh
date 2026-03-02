#!/usr/bin/env bash
# decode-apk.sh — Decode an APK or XAPK into smali using apktool
#
# Handles both .apk (direct decode) and .xapk (extract base APK, then decode).
#
# Exit codes:
#   0 — success
#   1 — error (invalid input, missing tools, decode failed)
set -euo pipefail

usage() {
  cat <<EOF
Usage: decode-apk.sh <file> [OPTIONS]

Decode an APK or XAPK file into smali and resources using apktool.

For XAPK files, extracts the base APK from the archive and decodes it.
Split APKs (config.*.apk) are skipped with a warning.

Arguments:
  <file>              Path to .apk or .xapk file

Options:
  -o, --output <dir>  Output directory (default: <basename>-decoded)
  -f, --force         Overwrite output directory if it exists (default)
  --no-force          Do not overwrite existing output directory
  -h, --help          Show this help message

Output:
  DECODED_DIR:<path>
EOF
  exit 0
}

# =====================================================================
# Argument parsing
# =====================================================================

INPUT_FILE=""
OUTPUT_DIR=""
FORCE=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      shift
      if [[ $# -eq 0 ]]; then echo "Error: --output requires a directory argument" >&2; exit 1; fi
      OUTPUT_DIR="$1"; shift ;;
    -f|--force)    FORCE=true; shift ;;
    --no-force)    FORCE=false; shift ;;
    -h|--help)     usage ;;
    -*)            echo "Error: Unknown option $1" >&2; usage ;;
    *)             INPUT_FILE="$1"; shift ;;
  esac
done

if [[ -z "$INPUT_FILE" ]]; then
  echo "Error: No input file specified." >&2
  usage
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: File not found: $INPUT_FILE" >&2
  exit 1
fi

# Check apktool
if ! command -v apktool &>/dev/null; then
  echo "Error: apktool is not installed or not in PATH." >&2
  echo "Run: install-dep.sh apktool" >&2
  exit 1
fi

# Determine file type
ext_lower="${INPUT_FILE##*.}"
ext_lower=$(echo "$ext_lower" | tr '[:upper:]' '[:lower:]')

case "$ext_lower" in
  apk|xapk) ;;
  *)
    echo "Error: Unsupported file type '.$ext_lower'. Expected .apk or .xapk" >&2
    exit 1
    ;;
esac

BASENAME=$(basename "$INPUT_FILE" ".$ext_lower")
INPUT_FILE_ABS=$(realpath "$INPUT_FILE")

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="${BASENAME}-decoded"
fi

# =====================================================================
# XAPK handling — extract base APK
# =====================================================================

APK_TO_DECODE="$INPUT_FILE_ABS"
XAPK_TMPDIR=""

cleanup_xapk() {
  if [[ -n "$XAPK_TMPDIR" ]] && [[ -d "$XAPK_TMPDIR" ]]; then
    rm -rf "$XAPK_TMPDIR"
  fi
}
trap cleanup_xapk EXIT

if [[ "$ext_lower" == "xapk" ]]; then
  echo "=== Extracting XAPK archive ==="
  XAPK_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/xapk-decode-XXXXXX")
  unzip -qo "$INPUT_FILE_ABS" -d "$XAPK_TMPDIR"

  # Show manifest.json if present
  if [[ -f "$XAPK_TMPDIR/manifest.json" ]]; then
    echo "XAPK manifest found."
  fi

  # Collect all APK files
  all_apks=()
  while IFS= read -r -d '' apk_file; do
    all_apks+=("$apk_file")
  done < <(find "$XAPK_TMPDIR" -name "*.apk" -print0 | sort -z)

  if [[ ${#all_apks[@]} -eq 0 ]]; then
    echo "Error: No APK files found inside XAPK archive." >&2
    exit 1
  fi

  echo "Found ${#all_apks[@]} APK(s) inside XAPK:"
  for f in "${all_apks[@]}"; do
    echo "  - $(basename "$f")"
  done

  # Select base APK: prefer "base.apk" by name
  base_apk=""
  for f in "${all_apks[@]}"; do
    if [[ "$(basename "$f")" == "base.apk" ]]; then
      base_apk="$f"
      break
    fi
  done

  # Fallback: largest APK excluding config.*.apk
  if [[ -z "$base_apk" ]]; then
    largest_size=0
    for f in "${all_apks[@]}"; do
      fname=$(basename "$f")
      # Skip config splits
      if [[ "$fname" == config.* ]]; then
        continue
      fi
      fsize=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo 0)
      if (( fsize > largest_size )); then
        largest_size=$fsize
        base_apk="$f"
      fi
    done
  fi

  if [[ -z "$base_apk" ]]; then
    echo "Error: Could not identify a base APK inside the XAPK." >&2
    exit 1
  fi

  echo
  echo "Selected base APK: $(basename "$base_apk")"

  # Warn about skipped splits
  skipped=0
  for f in "${all_apks[@]}"; do
    if [[ "$f" != "$base_apk" ]]; then
      echo "  [skipped] $(basename "$f")"
      skipped=$((skipped + 1))
    fi
  done
  if (( skipped > 0 )); then
    echo "Warning: $skipped split APK(s) skipped. Only the base APK is decoded."
    echo "         Split APKs contain config-specific resources (density, locale, ABI)."
  fi
  echo

  APK_TO_DECODE="$base_apk"
fi

# =====================================================================
# Decode with apktool
# =====================================================================

echo "=== Decoding APK with apktool ==="

APKTOOL_ARGS=()
if [[ "$FORCE" == true ]]; then
  APKTOOL_ARGS+=("-f")
fi
APKTOOL_ARGS+=("-o" "$OUTPUT_DIR")
APKTOOL_ARGS+=("$APK_TO_DECODE")

if ! apktool d "${APKTOOL_ARGS[@]}" 2>&1; then
  echo "Error: apktool decode failed." >&2
  echo "Tip: If this is a framework error, try: rm -f ~/.local/share/apktool/framework/1.apk" >&2
  exit 1
fi

# =====================================================================
# Verify output
# =====================================================================

has_smali=false
for d in "$OUTPUT_DIR"/smali*; do
  if [[ -d "$d" ]]; then
    has_smali=true
    break
  fi
done

if [[ "$has_smali" == false ]]; then
  echo "Error: No smali/ directory found in decoded output." >&2
  exit 1
fi

if [[ ! -f "$OUTPUT_DIR/AndroidManifest.xml" ]]; then
  echo "Warning: AndroidManifest.xml not found in decoded output." >&2
fi

echo
echo "Decoded successfully: $OUTPUT_DIR"
echo "DECODED_DIR:$OUTPUT_DIR"
exit 0
