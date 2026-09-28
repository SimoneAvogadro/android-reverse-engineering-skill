#!/usr/bin/env bash
# decode-apk.sh — Decode an APK or a split bundle (XAPK/APKM/APKS) into smali using apktool
#
# .apk input is decoded directly. Split bundles (.xapk/.apkm/.apks, or a
# directory of split APKs) are first merged into ONE APK with APKEditor, then
# decoded, so resources that live only in config splits (density, locale, ABI)
# are kept instead of turning into @null references.
#
# Portable: bash 3.2+ (macOS) and BSD/GNU userland.
#
# Exit codes:
#   0 — success
#   1 — error (invalid input, unknown option, missing tools, merge/decode failed)
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

usage() {
  cat <<EOF
Usage: decode-apk.sh <file|dir> [OPTIONS]

Decode an APK, or a split APK bundle, into smali and resources using apktool.

Split bundles (.xapk, .apkm, .apks, or a directory containing base.apk plus
split APKs) are merged into a single APK with APKEditor BEFORE decoding.
The rebuild (rebuild-apk.sh) then produces one installable APK.
Merge details are written to <decoded-dir>/.merged-from-splits.json.

Arguments:
  <file|dir>          Path to .apk, .xapk, .apkm, .apks, or a split-APK directory

Options:
  -o, --output <dir>  Output directory (default: <basename>-decoded)
  -f, --force         Overwrite output directory if it exists (default)
  --no-force          Do not overwrite existing output directory
  --keep-splits       DEPRECATED legacy mode (XAPK/APKM/APKS files only):
                      decode the base APK alone and keep the splits in
                      .xapk-origin/ so rebuild-apk.sh reassembles an XAPK.
                      Resources that exist only in splits become @null in the
                      decoded base (e.g. AppCompat drawables) and the app may
                      crash at inflation. Will be removed.
  -h, --help          Show this help message

Environment:
  APKEDITOR_JAR       Path to APKEditor.jar (default: ~/.local/share/apkeditor/APKEditor.jar,
                      then an 'apkeditor' launcher on PATH)

Output:
  DECODED_DIR:<path>
  MERGED_FROM_SPLITS:<path>/.merged-from-splits.json   (split bundle input)
  OBB_WARNING:<name>                                    (OBB files are never merged)
  DEPRECATION_WARNING:keep-splits                       (--keep-splits only)
  XAPK_ORIGIN:<path>                                    (--keep-splits only)
All paths are absolute. The output directory is replaced only after a successful
decode (the new tree is decoded next to it, then swapped in).
EOF
  exit "${1:-0}"
}

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)
INSTALL_DEP="$(cd "$SCRIPT_DIR/../../android-reverse-engineering/scripts" 2>/dev/null && pwd -P)/install-dep.sh"

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


# Absolute path without GNU realpath (macOS < 13 lacks it)
abs_path() {
  if [[ -d "$1" ]]; then
    (cd "$1" && pwd -P)
  else
    printf '%s/%s\n' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"
  fi
}

# Minimal JSON string escaping (backslash and double quote)
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# =====================================================================
# Argument parsing
# =====================================================================

INPUT_FILE=""
OUTPUT_DIR=""
FORCE=true
KEEP_SPLITS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      shift
      if [[ $# -eq 0 ]]; then echo "Error: --output requires a directory argument" >&2; exit 1; fi
      OUTPUT_DIR="$1"; shift ;;
    -f|--force)    FORCE=true; shift ;;
    --no-force)    FORCE=false; shift ;;
    --keep-splits) KEEP_SPLITS=true; shift ;;
    -h|--help)     usage ;;
    -*)            echo "Error: Unknown option $1" >&2; usage 1 >&2 ;;
    *)             INPUT_FILE="$1"; shift ;;
  esac
done

if [[ -z "$INPUT_FILE" ]]; then
  echo "Error: No input file specified." >&2
  usage 1 >&2
fi

if [[ ! -e "$INPUT_FILE" ]]; then
  echo "Error: File not found: $INPUT_FILE" >&2
  exit 1
fi

# Check apktool
if ! command -v apktool &>/dev/null; then
  echo "Error: apktool is not installed or not in PATH." >&2
  echo "Run: bash \"$INSTALL_DEP\" apktool" >&2
  exit 1
fi

# Determine input type
INPUT_KIND=""   # apk | bundle | dir
ext_lower=""
if [[ -d "$INPUT_FILE" ]]; then
  INPUT_KIND="dir"
  BASENAME=$(basename "$(abs_path "$INPUT_FILE")")
else
  ext_lower="${INPUT_FILE##*.}"
  ext_lower=$(echo "$ext_lower" | tr '[:upper:]' '[:lower:]')
  case "$ext_lower" in
    apk)            INPUT_KIND="apk" ;;
    xapk|apkm|apks) INPUT_KIND="bundle" ;;
    *)
      echo "Error: Unsupported file type '.$ext_lower'. Expected .apk, .xapk, .apkm, .apks or a directory of split APKs" >&2
      exit 1
      ;;
  esac
  BASENAME=$(basename "$INPUT_FILE" ".${INPUT_FILE##*.}")
fi
INPUT_FILE_ABS=$(abs_path "$INPUT_FILE")

if [[ "$KEEP_SPLITS" == true ]] && [[ "$INPUT_KIND" != "bundle" ]]; then
  echo "Error: --keep-splits only applies to .xapk/.apkm/.apks files." >&2
  exit 1
fi

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="${BASENAME}-decoded"
fi

if [[ "$FORCE" == false ]] && [[ -e "$OUTPUT_DIR" ]]; then
  echo "Error: Output directory already exists: $OUTPUT_DIR (use -f to overwrite)" >&2
  exit 1
fi
if [[ -e "$OUTPUT_DIR" ]] && [[ ! -d "$OUTPUT_DIR" ]]; then
  echo "Error: Output path exists and is not a directory: $OUTPUT_DIR" >&2
  exit 1
fi

if [[ "$INPUT_KIND" == "bundle" ]] && ! command -v unzip &>/dev/null; then
  echo "Error: unzip is required for split bundles (install: apt install unzip / brew install unzip)." >&2
  exit 1
fi

# Output location: decode next to it, swap in only after success
OUT_PARENT="$(dirname "$OUTPUT_DIR")"
mkdir -p "$OUT_PARENT"
OUT_PARENT_ABS=$(cd "$OUT_PARENT" && pwd -P)
OUTPUT_ABS="$OUT_PARENT_ABS/$(basename "$OUTPUT_DIR")"

APK_TO_DECODE="$INPUT_FILE_ABS"
WORK_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/apk-decode-XXXXXX")
XAPK_TMPDIR=""
DECODE_TMP=""
IS_XAPK=false
MERGED=false

cleanup_tmp() {
  if [[ -n "$WORK_TMPDIR" ]] && [[ -d "$WORK_TMPDIR" ]]; then
    rm -rf "$WORK_TMPDIR"
  fi
  if [[ -n "$XAPK_TMPDIR" ]] && [[ -d "$XAPK_TMPDIR" ]]; then
    rm -rf "$XAPK_TMPDIR"
  fi
  if [[ -n "$DECODE_TMP" ]] && [[ -d "$DECODE_TMP" ]]; then
    rm -rf "$DECODE_TMP"
  fi
}
trap cleanup_tmp EXIT
ensure_utf8_locale "$INPUT_FILE_ABS" "$OUT_PARENT_ABS"
# Every path is absolute from here on: run the tools from an ASCII working
# directory (Java cannot even start in a non-ASCII cwd under LANG=C).
cd "$WORK_TMPDIR"

if [[ "$INPUT_KIND" == "apk" ]] && has_non_ascii "$INPUT_FILE_ABS"; then
  ln -s "$INPUT_FILE_ABS" "$WORK_TMPDIR/input.apk"
  APK_TO_DECODE="$WORK_TMPDIR/input.apk"
fi

# =====================================================================
# Split bundle — merge all splits into one APK with APKEditor
# =====================================================================

split_names=()
obb_names=()
APKEDITOR_CMD=()
APKEDITOR_VERSION=""

if [[ "$INPUT_KIND" == "bundle" || "$INPUT_KIND" == "dir" ]] && [[ "$KEEP_SPLITS" == false ]]; then
  # Locate APKEditor: $APKEDITOR_JAR, then the install-dep.sh location, then a launcher on PATH
  if [[ -n "${APKEDITOR_JAR:-}" ]]; then
    if [[ ! -f "$APKEDITOR_JAR" ]]; then
      echo "Error: APKEDITOR_JAR is set but the file does not exist: $APKEDITOR_JAR" >&2
      exit 1
    fi
    APKEDITOR_CMD=(java "-Djava.io.tmpdir=$WORK_TMPDIR" -jar "$APKEDITOR_JAR")
  elif [[ -f "$HOME/.local/share/apkeditor/APKEditor.jar" ]]; then
    APKEDITOR_CMD=(java "-Djava.io.tmpdir=$WORK_TMPDIR" -jar "$HOME/.local/share/apkeditor/APKEditor.jar")
  elif command -v apkeditor &>/dev/null; then
    APKEDITOR_CMD=(apkeditor)
  else
    echo "Error: APKEditor is required to merge split APKs (input: $INPUT_FILE)." >&2
    echo "Run: bash \"$INSTALL_DEP\" apkeditor   (or set APKEDITOR_JAR=/path/to/APKEditor.jar)" >&2
    exit 1
  fi
  APKEDITOR_VERSION=$("${APKEDITOR_CMD[@]}" -version 2>&1 | sed -n 's/.*APKEditor version \([0-9.]*\).*/\1/p' | sed -n 1p || true)

  echo "=== Merging split APKs with APKEditor ${APKEDITOR_VERSION} ==="

  # List split APKs and OBB files (for the metadata file and user feedback)
  if [[ "$INPUT_KIND" == "bundle" ]]; then
    entries=$(unzip -Z1 "$INPUT_FILE_ABS" 2>/dev/null || true)
    while IFS= read -r entry; do
      case "$entry" in
        *.apk|*.APK) split_names+=("$(basename "$entry")") ;;
        *.obb|*.OBB) obb_names+=("$(basename "$entry")") ;;
      esac
    done <<< "$entries"
  else
    while IFS= read -r entry; do
      [[ -n "$entry" ]] && split_names+=("$(basename "$entry")")
    done <<< "$(find "$INPUT_FILE_ABS" -maxdepth 1 -type f \( -name '*.apk' -o -name '*.APK' \) | sort)"
  fi

  if [[ ${#split_names[@]} -eq 0 ]]; then
    echo "Error: No APK files found in $INPUT_FILE" >&2
    exit 1
  fi
  echo "Found ${#split_names[@]} APK(s):"
  for f in "${split_names[@]}"; do
    echo "  - $f"
  done

  # Hand Java an ASCII-only path: a non-UTF-8 locale (LANG=C) breaks
  # non-ASCII file names such as "Block+Craft+3D：Building".
  if [[ "$INPUT_KIND" == "bundle" ]]; then
    merge_input="$WORK_TMPDIR/input.$ext_lower"
  else
    merge_input="$WORK_TMPDIR/input-dir"
  fi
  ln -s "$INPUT_FILE_ABS" "$merge_input"

  echo
  if ! "${APKEDITOR_CMD[@]}" m -i "$merge_input" -o "$WORK_TMPDIR/merged.apk" -f 2>&1; then
    echo "Error: APKEditor merge failed." >&2
    exit 1
  fi
  if [[ ! -f "$WORK_TMPDIR/merged.apk" ]]; then
    echo "Error: APKEditor did not produce a merged APK." >&2
    exit 1
  fi
  echo "Merged ${#split_names[@]} APK(s) into one APK."
  if [[ ${#obb_names[@]} -gt 0 ]]; then
    for f in "${obb_names[@]}"; do
      echo "Warning: OBB file not merged (copy it to the device manually): $f" >&2
      echo "OBB_WARNING:$f"
    done
  fi
  echo

  APK_TO_DECODE="$WORK_TMPDIR/merged.apk"
  MERGED=true
fi

# =====================================================================
# DEPRECATED --keep-splits: extract base APK, preserve splits for XAPK rebuild
# =====================================================================

if [[ "$KEEP_SPLITS" == true ]]; then
  IS_XAPK=true
  echo "DEPRECATION_WARNING:keep-splits"
  echo "Warning: --keep-splits is deprecated and will be removed." >&2
  echo "         Only the base APK is decoded: resources that exist only in the splits" >&2
  echo "         become @null (e.g. AppCompat selector drawables) and the rebuilt app may" >&2
  echo "         crash at inflation. Omit --keep-splits to merge the splits with APKEditor." >&2
  echo
  echo "=== Extracting XAPK archive ==="
  XAPK_TMPDIR="$WORK_TMPDIR/xapk"
  mkdir -p "$XAPK_TMPDIR"
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

# Decode into a sibling temp dir; the existing output is replaced only on success
DECODE_TMP=$(mktemp -d "$OUT_PARENT_ABS/.decode-tmp-XXXXXX")

if ! apktool d -f -o "$DECODE_TMP" "$APK_TO_DECODE" 2>&1; then
  echo "Error: apktool decode failed." >&2
  echo "Tip: If this is a framework error, try: rm -f ~/.local/share/apktool/framework/1.apk" >&2
  exit 1
fi

# =====================================================================
# Verify output
# =====================================================================

has_smali=false
for d in "$DECODE_TMP"/smali*; do
  if [[ -d "$d" ]]; then
    has_smali=true
    break
  fi
done

if [[ "$has_smali" == false ]]; then
  echo "Error: No smali/ directory found in decoded output." >&2
  exit 1
fi

if [[ ! -f "$DECODE_TMP/AndroidManifest.xml" ]]; then
  echo "Warning: AndroidManifest.xml not found in decoded output." >&2
fi

# =====================================================================
# Record merge metadata (split bundle input)
# =====================================================================

if [[ "$MERGED" == true ]]; then
  MERGE_META="$DECODE_TMP/.merged-from-splits.json"
  pkg_name=$(sed -n 's/.*<manifest[^>]* package="\([^"]*\)".*/\1/p' "$DECODE_TMP/AndroidManifest.xml" 2>/dev/null | sed -n 1p || true)
  ver_code=$(sed -n "s/^[[:space:]]*versionCode:[[:space:]]*'\{0,1\}\([0-9]*\).*/\1/p" "$DECODE_TMP/apktool.yml" 2>/dev/null | sed -n 1p || true)
  ver_name=$(sed -n "s/^[[:space:]]*versionName:[[:space:]]*'\{0,1\}\([^']*\)'\{0,1\}[[:space:]]*$/\1/p" "$DECODE_TMP/apktool.yml" 2>/dev/null | sed -n 1p || true)
  splits_json=""
  for f in "${split_names[@]}"; do
    splits_json="${splits_json:+$splits_json, }\"$(json_escape "$f")\""
  done
  obb_json=""
  if [[ ${#obb_names[@]} -gt 0 ]]; then
    for f in "${obb_names[@]}"; do
      obb_json="${obb_json:+$obb_json, }\"$(json_escape "$f")\""
    done
  fi
  decoded_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
  {
    echo "{"
    echo "  \"format\": \"${ext_lower:-directory}\","
    echo "  \"source_file\": \"$(json_escape "$INPUT_FILE_ABS")\","
    echo "  \"package_name\": \"$(json_escape "$pkg_name")\","
    echo "  \"version_code\": \"$(json_escape "$ver_code")\","
    echo "  \"version_name\": \"$(json_escape "$ver_name")\","
    echo "  \"split_apks\": [$splits_json],"
    echo "  \"obb_files_not_merged\": [$obb_json],"
    echo "  \"merged_with\": \"APKEditor\","
    echo "  \"apkeditor_version\": \"$(json_escape "$APKEDITOR_VERSION")\","
    echo "  \"decoded_timestamp\": \"$decoded_ts\""
    echo "}"
  } > "$MERGE_META"
fi


# =====================================================================
# Preserve XAPK structure for rebuild
# =====================================================================

if [[ "$IS_XAPK" == true ]] && [[ -n "$XAPK_TMPDIR" ]]; then
  echo
  echo "=== Preserving XAPK structure ==="

  XAPK_ORIGIN_DIR="$DECODE_TMP/.xapk-origin"
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
    xapk_package_name=$(sed -n 's/.*"package_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$XAPK_ORIGIN_DIR/manifest.json" | sed -n 1p)
    xapk_version_code=$(sed -n 's/.*"version_code"[[:space:]]*:[[:space:]]*"\{0,1\}\([0-9]*\)"\{0,1\}.*/\1/p' "$XAPK_ORIGIN_DIR/manifest.json" | sed -n 1p)
    xapk_version_name=$(sed -n 's/.*"version_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$XAPK_ORIGIN_DIR/manifest.json" | sed -n 1p)
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
  if (( ${#split_apks[@]} > 0 )); then   # bash < 4.4 + set -u: empty "${arr[@]}" is unbound
    for i in "${!split_apks[@]}"; do
      if (( i > 0 )); then splits_json+=", "; fi
      splits_json+="\"${split_apks[$i]}\""
    done
  fi
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
fi

# =====================================================================
# Swap the new tree into place (the old one is deleted only now)
# =====================================================================

if [[ -e "$OUTPUT_ABS" ]]; then
  OLD_TREE=$(mktemp -d "$OUT_PARENT_ABS/.decode-old-XXXXXX")
  rmdir "$OLD_TREE"
  mv "$OUTPUT_ABS" "$OLD_TREE"
  mv "$DECODE_TMP" "$OUTPUT_ABS"
  rm -rf "$OLD_TREE"
else
  mv "$DECODE_TMP" "$OUTPUT_ABS"
fi
DECODE_TMP=""

if [[ "$MERGED" == true ]]; then
  echo
  echo "Merge metadata written: $OUTPUT_ABS/.merged-from-splits.json"
  echo "MERGED_FROM_SPLITS:$OUTPUT_ABS/.merged-from-splits.json"
fi
if [[ "$IS_XAPK" == true ]]; then
  echo
  echo "XAPK structure preserved in: $OUTPUT_ABS/.xapk-origin"
  echo "XAPK_ORIGIN:$OUTPUT_ABS/.xapk-origin"
fi

# Clean up temporary files now that everything is copied
cleanup_tmp
trap - EXIT

echo
echo "Decoded successfully: $OUTPUT_ABS"
echo "DECODED_DIR:$OUTPUT_ABS"
exit 0
