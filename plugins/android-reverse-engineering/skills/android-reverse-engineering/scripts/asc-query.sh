#!/usr/bin/env bash
# asc-query.sh — Rapid on-demand queries using ASC (Android Source Code)
# Allows instant class decompilation, manifest decoding, and xref searches
# without unpacking or pre-indexing the full APK.
set -euo pipefail

usage() {
  cat <<EOF
Usage: asc-query.sh <apk_file> <subcommand> [args...]

Subcommands:
  getclass <class_name> [-o output.java]
      Locate and decompile a single class in ~180ms.
      Example: asc-query.sh app.apk getclass com.example.MainActivity

  findrefs <string|type|method|field|extends|impl> <target> [-o output.txt]
      Find cross-references across all DEX entries in seconds.
      Example: asc-query.sh app.apk findrefs string "https://api"
      Example: asc-query.sh app.apk findrefs extends androidx.lifecycle.ViewModel

  listclass [--prefix <prefix>] [-o output.txt]
      List class descriptors across all DEX entries.
      Example: asc-query.sh app.apk listclass --prefix com.example

  getmanifest [-o AndroidManifest.xml]
      Extract and decode AndroidManifest.xml directly from the APK.
      Example: asc-query.sh app.apk getmanifest
EOF
  exit 0
}

if [[ $# -lt 2 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi

APK_FILE="$1"
shift

if [[ ! -f "$APK_FILE" ]]; then
  echo "Error: File not found: $APK_FILE" >&2
  exit 1
fi

# Locate ASC tool
find_asc() {
  if command -v droidasc &>/dev/null; then
    echo "droidasc"
  elif command -v rust_ASC &>/dev/null; then
    echo "rust_ASC"
  elif python3 -m droidasc --help &>/dev/null; then
    echo "python3 -m droidasc"
  elif python -m droidasc --help &>/dev/null; then
    echo "python -m droidasc"
  else
    return 1
  fi
}

ASC_CMD=""
if ! ASC_CMD=$(find_asc); then
  echo "Error: ASC decompiler is not installed." >&2
  echo "Install via: pip install droidasc or run install-dep.sh asc" >&2
  exit 1
fi

SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
  getclass|listclass|getmanifest|findrefs)
    $ASC_CMD "$SUBCOMMAND" "$APK_FILE" "$@"
    ;;
  *)
    echo "Error: Unknown subcommand '$SUBCOMMAND'." >&2
    usage
    ;;
esac
