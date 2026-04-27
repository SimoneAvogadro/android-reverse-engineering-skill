#!/usr/bin/env bash
# decode-apk.sh — Decode an APK or XAPK into smali using apktool
#
# Handles both .apk (direct decode) and .xapk (extract base APK, then decode).
#
# Exit codes:
#   0 — success
#   1 — error (invalid input, missing tools, decode failed)
set -euo pipefail

# Ensure user-local bin is in PATH (install-dep.sh installs tools there)
if [[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

usage() {
  cat <<EOF
Usage: decode-apk.sh <file> [OPTIONS]

Decode an APK or XAPK file into smali and resources using apktool.

For XAPK files, extracts the base APK and decodes it. Split APKs and
XAPK metadata are preserved in .xapk-origin/ inside the decoded directory
so that rebuild-apk.sh can reassemble a complete XAPK.

Arguments:
  <file>              Path to .apk or .xapk file

Options:
  -o, --output <dir>  Output directory (default: <basename>-decoded)
  -f, --force         Overwrite output directory if it exists (default)
  --no-force          Do not overwrite existing output directory
  -h, --help          Show this help message

Output:
  DECODED_DIR:<path>
  XAPK_ORIGIN:<path>   (only for XAPK input)
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
# XAPK handling — extract base APK, preserve structure for rebuild
# =====================================================================

APK_TO_DECODE="$INPUT_FILE_ABS"
XAPK_TMPDIR=""
IS_XAPK=false

cleanup_xapk() {
  if [[ -n "$XAPK_TMPDIR" ]] && [[ -d "$XAPK_TMPDIR" ]]; then
    rm -rf "$XAPK_TMPDIR"
  fi
}

if [[ "$ext_lower" == "xapk" ]]; then
  IS_XAPK=true
  echo "=== Extracting XAPK archive ==="
  XAPK_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/xapk-decode-XXXXXX")
  trap cleanup_xapk EXIT
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
    rm -rf "$XAPK_TMPDIR"
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
    rm -rf "$XAPK_TMPDIR"
    exit 1
  fi

  BASE_APK_NAME=$(basename "$base_apk")
  echo
  echo "Selected base APK: $BASE_APK_NAME"

  # List split APKs
  split_apks=()
  for f in "${all_apks[@]}"; do
    if [[ "$f" != "$base_apk" ]]; then
      split_apks+=("$(basename "$f")")
      echo "  [split] $(basename "$f")"
    fi
  done
  if (( ${#split_apks[@]} > 0 )); then
    echo "${#split_apks[@]} split APK(s) preserved in .xapk-origin/splits/ for rebuild."
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

# =====================================================================
# Preserve XAPK structure for rebuild
# =====================================================================

if [[ "$IS_XAPK" == true ]] && [[ -n "$XAPK_TMPDIR" ]]; then
  echo
  echo "=== Preserving XAPK structure ==="

  XAPK_ORIGIN_DIR="$OUTPUT_DIR/.xapk-origin"
  mkdir -p "$XAPK_ORIGIN_DIR/splits"

  # Copy manifest.json from XAPK
  if [[ -f "$XAPK_TMPDIR/manifest.json" ]]; then
    cp "$XAPK_TMPDIR/manifest.json" "$XAPK_ORIGIN_DIR/manifest.json"
    echo "  Copied manifest.json"
  fi

  # Copy icon if present
  for icon_file in "$XAPK_TMPDIR"/icon.png "$XAPK_TMPDIR"/icon.jpg; do
    if [[ -f "$icon_file" ]]; then
      cp "$icon_file" "$XAPK_ORIGIN_DIR/"
      echo "  Copied $(basename "$icon_file")"
      break
    fi
  done

  # Copy split APKs
  for f in "${all_apks[@]}"; do
    if [[ "$f" != "$base_apk" ]]; then
      cp "$f" "$XAPK_ORIGIN_DIR/splits/"
      echo "  Copied split: $(basename "$f")"
    fi
  done

  # Extract metadata from XAPK manifest.json using sed (no jq dependency)
  xapk_package_name=""
  xapk_version_code=""
  xapk_version_name=""
  if [[ -f "$XAPK_ORIGIN_DIR/manifest.json" ]]; then
    xapk_package_name=$(sed -n 's/.*"package_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$XAPK_ORIGIN_DIR/manifest.json" | head -1)
    xapk_version_code=$(sed -n 's/.*"version_code"[[:space:]]*:[[:space:]]*"\{0,1\}\([0-9]*\)"\{0,1\}.*/\1/p' "$XAPK_ORIGIN_DIR/manifest.json" | head -1)
    xapk_version_name=$(sed -n 's/.*"version_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$XAPK_ORIGIN_DIR/manifest.json" | head -1)
  fi

  # Detect OBB files (registered but NOT copied — can be gigabytes)
  obb_json="[]"
  obb_entries=()
  while IFS= read -r -d '' obb_file; do
    obb_name=$(basename "$obb_file")
    obb_size=$(stat -c%s "$obb_file" 2>/dev/null || stat -f%z "$obb_file" 2>/dev/null || echo 0)
    obb_entries+=("{\"name\": \"$obb_name\", \"size_bytes\": $obb_size}")
  done < <(find "$XAPK_TMPDIR" -name "*.obb" -print0 2>/dev/null)
  if (( ${#obb_entries[@]} > 0 )); then
    obb_json="["
    for i in "${!obb_entries[@]}"; do
      if (( i > 0 )); then obb_json+=", "; fi
      obb_json+="${obb_entries[$i]}"
    done
    obb_json+="]"
    echo "  OBB files detected (not copied — registered in metadata only):"
    for entry in "${obb_entries[@]}"; do echo "    $entry"; done
  fi

  # Build split_apks JSON array
  splits_json="["
  for i in "${!split_apks[@]}"; do
    if (( i > 0 )); then splits_json+=", "; fi
    splits_json+="\"${split_apks[$i]}\""
  done
  splits_json+="]"

  # Write metadata.json
  decoded_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
  printf '{\n  "format": "xapk",\n  "original_file": "%s",\n  "package_name": "%s",\n  "version_code": "%s",\n  "version_name": "%s",\n  "base_apk": "%s",\n  "split_apks": %s,\n  "obb_files": %s,\n  "decoded_timestamp": "%s"\n}\n' \
    "$INPUT_FILE_ABS" \
    "$xapk_package_name" \
    "$xapk_version_code" \
    "$xapk_version_name" \
    "$BASE_APK_NAME" \
    "$splits_json" \
    "$obb_json" \
    "$decoded_ts" \
    > "$XAPK_ORIGIN_DIR/metadata.json"
  echo "  Wrote metadata.json"

  echo
  echo "XAPK structure preserved in: $XAPK_ORIGIN_DIR"
  echo "XAPK_ORIGIN:$XAPK_ORIGIN_DIR"
fi

# Clean up XAPK tmpdir now that everything is copied
cleanup_xapk
# Set trap to no-op since we already cleaned up
trap - EXIT

echo
echo "Decoded successfully: $OUTPUT_DIR"
echo "DECODED_DIR:$OUTPUT_DIR"
exit 0
