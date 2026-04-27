#!/usr/bin/env bash
# merge-splits.sh — Merge XAPK split APKs into the decoded base APK directory
#
# Produces a single-APK-ready directory by merging native libraries,
# resources (best-effort), and cleaning the manifest of split-related attributes.
#
# Exit codes:
#   0 — success (splits merged)
#   1 — error (invalid input, missing files)
#   2 — not an XAPK (no .xapk-origin/ found)
set -euo pipefail

usage() {
  cat <<EOF
Usage: merge-splits.sh <decoded-dir> [OPTIONS]

Merge XAPK split APK contents into the decoded base APK directory,
producing a directory ready to rebuild as a single merged APK.

Arguments:
  <decoded-dir>   Path to the apktool-decoded APK directory (must contain .xapk-origin/)

Options:
  --abi <abi>         Merge only this ABI (e.g., arm64-v8a, armeabi-v7a, x86_64, x86)
  --all-abis          Merge all ABIs found in splits (larger but universal)
  --skip-resources    Skip merging resource splits (locale, density)
  -h, --help          Show this help message

Output (machine-readable):
  MERGE_ABI:<abi> (<count> native libraries)
  MERGE_RESOURCES:<split> (<count> files)
  SKIPPED_RESOURCES:<split>:<reason>
  FEATURE_SPLIT_WARNING:<split> (feature modules cannot be merged)
  MANIFEST_CLEANED:<attribute>
  MERGE_COMPLETE:<decoded-dir>
EOF
  exit 0
}

# =====================================================================
# Argument parsing
# =====================================================================

DECODED_DIR=""
TARGET_ABI=""
ALL_ABIS=false
SKIP_RESOURCES=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --abi)
      shift
      if [[ $# -eq 0 ]]; then echo "Error: --abi requires an argument" >&2; exit 1; fi
      TARGET_ABI="$1"; shift ;;
    --all-abis)    ALL_ABIS=true; shift ;;
    --skip-resources) SKIP_RESOURCES=true; shift ;;
    -h|--help)     usage ;;
    -*)            echo "Error: Unknown option $1" >&2; usage ;;
    *)             DECODED_DIR="$1"; shift ;;
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

# =====================================================================
# Validate XAPK origin
# =====================================================================

info()  { echo "[INFO] $*"; }
ok()    { echo "[OK] $*"; }
fail()  { echo "[FAIL] $*" >&2; }

XAPK_ORIGIN_DIR="$DECODED_DIR/.xapk-origin"

if [[ ! -f "$XAPK_ORIGIN_DIR/metadata.json" ]]; then
  info "Not an XAPK — no .xapk-origin/metadata.json found. Nothing to merge."
  exit 2
fi

if [[ ! -d "$XAPK_ORIGIN_DIR/splits" ]]; then
  info "No splits directory found in .xapk-origin/. Nothing to merge."
  exit 2
fi

# Count split APKs
split_count=0
for f in "$XAPK_ORIGIN_DIR/splits/"*.apk; do
  [[ -f "$f" ]] && (( split_count++ )) || true
done

if (( split_count == 0 )); then
  info "No split APKs found in .xapk-origin/splits/. Nothing to merge."
  exit 2
fi

echo "=== Merging XAPK Splits ==="
echo "Decoded dir: $DECODED_DIR"
echo "Split APKs found: $split_count"
echo

# =====================================================================
# Step 0: Classify splits (ABI, resource, feature)
# =====================================================================

declare -a abi_splits=()
declare -a resource_splits=()
declare -a feature_splits=()

for split_apk in "$XAPK_ORIGIN_DIR/splits/"*.apk; do
  [[ -f "$split_apk" ]] || continue
  split_name=$(basename "$split_apk")

  # Check if it's an ABI split — filename pattern first, then content-based fallback
  if [[ "$split_name" =~ ^config\.(arm64_v8a|armeabi_v7a|x86|x86_64)\.apk$ ]]; then
    abi_splits+=("$split_apk")
  elif unzip -l "$split_apk" 2>/dev/null | grep -qE '\blib/[a-z0-9_-]+/.*\.so'; then
    abi_splits+=("$split_apk")
  # Check if it's a feature split (contains classes.dex or AndroidManifest.xml with split name)
  elif unzip -l "$split_apk" 2>/dev/null | grep -qE "(classes[0-9]*\.dex|^.*AndroidManifest\.xml)" && \
       ! [[ "$split_name" == config.* ]]; then
    feature_splits+=("$split_apk")
  else
    # Config split (locale, density, etc.)
    resource_splits+=("$split_apk")
  fi
done

info "ABI splits: ${#abi_splits[@]}"
info "Resource splits: ${#resource_splits[@]}"
info "Feature splits: ${#feature_splits[@]}"
echo

# Warn about feature splits — cannot be merged
if (( ${#feature_splits[@]} > 0 )); then
  for fs in "${feature_splits[@]}"; do
    fname=$(basename "$fs")
    echo "FEATURE_SPLIT_WARNING:$fname (feature modules cannot be merged — contains DEX code and own manifest)"
  done
  echo
fi

# =====================================================================
# Step 1: Merge native libraries (ABI splits)
# =====================================================================

echo "=== Step 1: Merge Native Libraries ==="

if (( ${#abi_splits[@]} == 0 )); then
  info "No ABI splits found — skipping native library merge."
else
  # Detect available ABIs
  declare -A abi_to_split=()
  for split_apk in "${abi_splits[@]}"; do
    # Extract ABI name from the lib/ structure inside the APK
    while IFS= read -r abi_name; do
      abi_to_split["$abi_name"]="$split_apk"
    done < <(unzip -l "$split_apk" 2>/dev/null | grep -oP 'lib/\K[^/]+(?=/)' | sort -u)
  done

  info "Available ABIs: ${!abi_to_split[*]}"

  # Determine which ABIs to merge
  declare -a abis_to_merge=()

  if [[ -n "$TARGET_ABI" ]]; then
    # User specified a specific ABI
    if [[ -z "${abi_to_split[$TARGET_ABI]:-}" ]]; then
      fail "Requested ABI '$TARGET_ABI' not found in splits. Available: ${!abi_to_split[*]}"
      exit 1
    fi
    abis_to_merge=("$TARGET_ABI")
  elif [[ "$ALL_ABIS" == true ]]; then
    # Merge all ABIs
    abis_to_merge=("${!abi_to_split[@]}")
  else
    # Default: pick most common ABI by priority
    for preferred in arm64-v8a armeabi-v7a x86_64 x86; do
      if [[ -n "${abi_to_split[$preferred]:-}" ]]; then
        abis_to_merge=("$preferred")
        break
      fi
    done
    # Fallback: pick the first available
    if (( ${#abis_to_merge[@]} == 0 )); then
      for abi in "${!abi_to_split[@]}"; do
        abis_to_merge=("$abi")
        break
      done
    fi
  fi

  info "Merging ABIs: ${abis_to_merge[*]}"

  # Create lib/ directory in decoded dir if it doesn't exist
  mkdir -p "$DECODED_DIR/lib"

  TMPDIR_NATIVE=$(mktemp -d "${TMPDIR:-/tmp}/merge-native-XXXXXX")
  cleanup_native() { rm -rf "$TMPDIR_NATIVE"; }
  trap cleanup_native EXIT

  for abi in "${abis_to_merge[@]}"; do
    split_apk="${abi_to_split[$abi]}"
    split_name=$(basename "$split_apk")

    info "Extracting native libs from $split_name (ABI: $abi)..."

    # Extract lib/ contents
    rm -rf "$TMPDIR_NATIVE/"*
    unzip -qo "$split_apk" "lib/*" -d "$TMPDIR_NATIVE" 2>/dev/null || true

    if [[ -d "$TMPDIR_NATIVE/lib/$abi" ]]; then
      # Copy to decoded dir
      mkdir -p "$DECODED_DIR/lib/$abi"
      lib_count=0
      for so_file in "$TMPDIR_NATIVE/lib/$abi/"*; do
        [[ -f "$so_file" ]] || continue
        cp "$so_file" "$DECODED_DIR/lib/$abi/"
        (( lib_count++ )) || true
      done
      ok "Merged $lib_count native libraries for $abi"
      echo "MERGE_ABI:$abi ($lib_count native libraries)"
    else
      info "No native libs found for ABI $abi in $split_name"
    fi
  done

  cleanup_native
  trap - EXIT
fi

echo

# =====================================================================
# Step 2: Merge resources (locale/density splits) — best-effort
# =====================================================================

echo "=== Step 2: Merge Resources (best-effort) ==="

if [[ "$SKIP_RESOURCES" == true ]]; then
  info "Resource merge skipped (--skip-resources)."
  for rs in "${resource_splits[@]}"; do
    fname=$(basename "$rs")
    echo "SKIPPED_RESOURCES:$fname:user-requested"
  done
elif (( ${#resource_splits[@]} == 0 )); then
  info "No resource splits found — skipping."
else
  TMPDIR_RES=$(mktemp -d "${TMPDIR:-/tmp}/merge-res-XXXXXX")
  cleanup_res() { rm -rf "$TMPDIR_RES"; }
  trap cleanup_res EXIT

  for split_apk in "${resource_splits[@]}"; do
    split_name=$(basename "$split_apk")

    # Extract everything except META-INF/ and resources.arsc (cannot merge compiled resources)
    rm -rf "$TMPDIR_RES/"*
    unzip -qo "$split_apk" -d "$TMPDIR_RES" -x "META-INF/*" "resources.arsc" 2>/dev/null || true

    # Count extracted files (excluding directories)
    file_count=0
    while IFS= read -r -d '' f; do
      (( file_count++ )) || true
    done < <(find "$TMPDIR_RES" -type f -print0 2>/dev/null)

    if (( file_count == 0 )); then
      echo "SKIPPED_RESOURCES:$split_name:no-extractable-files"
      continue
    fi

    # Copy res/ contents if present
    res_copied=0
    if [[ -d "$TMPDIR_RES/res" ]]; then
      # Copy resource directories (values-*, drawable-*, etc.)
      for res_subdir in "$TMPDIR_RES/res/"*; do
        [[ -d "$res_subdir" ]] || continue
        subdir_name=$(basename "$res_subdir")
        mkdir -p "$DECODED_DIR/res/$subdir_name"
        for res_file in "$res_subdir/"*; do
          [[ -f "$res_file" ]] || continue
          # Don't overwrite existing resources from the base APK
          target="$DECODED_DIR/res/$subdir_name/$(basename "$res_file")"
          if [[ ! -f "$target" ]]; then
            cp "$res_file" "$target"
            (( res_copied++ )) || true
          fi
        done
      done
    fi

    # Copy assets/ contents if present
    assets_copied=0
    if [[ -d "$TMPDIR_RES/assets" ]]; then
      mkdir -p "$DECODED_DIR/assets"
      while IFS= read -r -d '' asset_file; do
        rel_path="${asset_file#$TMPDIR_RES/assets/}"
        target="$DECODED_DIR/assets/$rel_path"
        if [[ ! -f "$target" ]]; then
          mkdir -p "$(dirname "$target")"
          cp "$asset_file" "$target"
          (( assets_copied++ )) || true
        fi
      done < <(find "$TMPDIR_RES/assets" -type f -print0 2>/dev/null)
    fi

    total_copied=$(( res_copied + assets_copied ))
    if (( total_copied > 0 )); then
      ok "Merged $total_copied files from $split_name"
      echo "MERGE_RESOURCES:$split_name ($total_copied files)"
    else
      echo "SKIPPED_RESOURCES:$split_name:all-files-already-exist-in-base"
    fi
  done

  cleanup_res
  trap - EXIT
fi

echo

# =====================================================================
# Step 3: Patch AndroidManifest.xml
# =====================================================================

echo "=== Step 3: Patch AndroidManifest.xml ==="

MANIFEST="$DECODED_DIR/AndroidManifest.xml"

if [[ ! -f "$MANIFEST" ]]; then
  fail "AndroidManifest.xml not found in $DECODED_DIR"
  exit 1
fi

# 3a: Remove android:isSplitRequired="true" → set to "false"
if grep -q 'android:isSplitRequired="true"' "$MANIFEST"; then
  sed -i 's/android:isSplitRequired="true"/android:isSplitRequired="false"/g' "$MANIFEST"
  ok "Patched: isSplitRequired=true → false"
  echo "MANIFEST_CLEANED:isSplitRequired"
fi

# 3b: Remove split-related <meta-data> elements
# Each pattern removes the entire <meta-data ... /> tag (single-line or multi-line)
declare -a meta_names=(
  "com.android.vending.splits.required"
  "com.android.vending.splits"
  "com.android.vending.derived.apk.id"
  "com.android.stamp.source"
  "com.android.stamp.type"
)

for meta_name in "${meta_names[@]}"; do
  if grep -q "android:name=\"$meta_name\"" "$MANIFEST"; then
    # Remove single-line <meta-data ... />
    sed -i "/<meta-data[^>]*android:name=\"$meta_name\"[^>]*\/>/d" "$MANIFEST"
    # Remove multi-line <meta-data ... > ... </meta-data> (rare but handle it)
    # Use a simple approach: remove lines containing the meta-data name within meta-data blocks
    sed -i "/<meta-data[^>]*android:name=\"$meta_name\"/,/<\/meta-data>/d" "$MANIFEST"
    ok "Removed: <meta-data android:name=\"$meta_name\">"
    echo "MANIFEST_CLEANED:$meta_name"
  fi
done

# 3c: Remove hasFragileUserData if present (split-related cleanup)
if grep -q 'android:hasFragileUserData' "$MANIFEST"; then
  sed -i 's/ *android:hasFragileUserData="[^"]*"//g' "$MANIFEST"
  info "Removed: android:hasFragileUserData (split-related)"
fi

# 3d: Fix extractNativeLibs — change false to true when we have merged native libs
if [[ -d "$DECODED_DIR/lib" ]] && [[ -n "$(ls -A "$DECODED_DIR/lib/" 2>/dev/null)" ]]; then
  if grep -q 'android:extractNativeLibs="false"' "$MANIFEST"; then
    sed -i 's/android:extractNativeLibs="false"/android:extractNativeLibs="true"/g' "$MANIFEST"
    ok "Patched: extractNativeLibs=false → true (required for merged native libs)"
    echo "MANIFEST_CLEANED:extractNativeLibs→true"
  elif ! grep -q 'android:extractNativeLibs' "$MANIFEST"; then
    # Add extractNativeLibs="true" to the <application> tag
    sed -i 's/<application/<application android:extractNativeLibs="true"/' "$MANIFEST"
    ok "Added: extractNativeLibs=true to <application>"
    echo "MANIFEST_CLEANED:extractNativeLibs→true (added)"
  fi
fi

# 3e: Remove android:splitTypes attribute if present
if grep -q 'android:splitTypes=' "$MANIFEST"; then
  sed -i 's/ *android:splitTypes="[^"]*"//g' "$MANIFEST"
  ok "Removed: android:splitTypes"
  echo "MANIFEST_CLEANED:splitTypes"
fi

# 3f: Remove android:requiredSplitTypes attribute if present
if grep -q 'android:requiredSplitTypes=' "$MANIFEST"; then
  sed -i 's/ *android:requiredSplitTypes="[^"]*"//g' "$MANIFEST"
  ok "Removed: android:requiredSplitTypes"
  echo "MANIFEST_CLEANED:requiredSplitTypes"
fi

echo

# =====================================================================
# Step 4: Create merge marker
# =====================================================================

echo "=== Step 4: Finalize ==="

# Create .merged marker so rebuild-apk.sh knows to produce a single APK
touch "$XAPK_ORIGIN_DIR/.merged"
ok "Created merge marker: $XAPK_ORIGIN_DIR/.merged"

# Write merge metadata
merged_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
{
  echo "{"
  echo "  \"merged_timestamp\": \"$merged_ts\","
  echo "  \"abi_splits_merged\": ${#abi_splits[@]},"
  echo "  \"resource_splits_merged\": ${#resource_splits[@]},"
  echo "  \"feature_splits_skipped\": ${#feature_splits[@]},"
  echo "  \"skip_resources\": $SKIP_RESOURCES"
  echo "}"
} > "$XAPK_ORIGIN_DIR/.merged-metadata.json"

echo
echo "=== Merge Complete ==="

# Summary
echo
echo "Merged splits into: $DECODED_DIR"
if (( ${#feature_splits[@]} > 0 )); then
  echo
  echo "WARNING: ${#feature_splits[@]} feature module split(s) could NOT be merged."
  echo "         Feature modules contain their own DEX code and manifest entries."
  echo "         The merged APK may be missing functionality from these modules."
  for fs in "${feature_splits[@]}"; do
    echo "         - $(basename "$fs")"
  done
fi

echo
echo "MERGE_COMPLETE:$DECODED_DIR"
echo
echo "Next: rebuild with --single-apk flag or let rebuild-apk.sh auto-detect the .merged marker."
echo "  rebuild-apk.sh $DECODED_DIR --auto-keystore"

exit 0
