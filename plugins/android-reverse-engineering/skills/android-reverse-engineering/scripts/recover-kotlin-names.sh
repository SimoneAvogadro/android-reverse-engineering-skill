#!/usr/bin/env bash
# recover-kotlin-names.sh: Rebuild a (obfuscated -> real) class-name map
# from Kotlin metadata strings left in decompiled sources.
#
# R8 obfuscates JVM symbols but cannot strip the Kotlin metadata strings;
# the Kotlin runtime (reflection, coroutines) needs them at runtime. Two
# annotations carry the original FQN:
#
#   * @DebugMetadata(c = "<full.qualified.Name>", f = "<File.kt>", ...)
#     emitted for almost every `suspend` function (every coroutine
#     SuspendLambda).
#
#   * @Metadata(... d2 = {"...L<pkg/Class>;..."} ...) listing internal
#     class refs of the file.
#
# Typical recovery on a real-world app: 30-50 % of classes regain their real
# names; usually 100 % of the *Repository / *ViewModel / *UseCase / *Impl
# classes you actually want to read.

set -euo pipefail

usage() {
  cat <<EOF
Usage: recover-kotlin-names.sh <decompiled-sources-dir> [output-dir]

Walks every *.java under <decompiled-sources-dir>, mines @DebugMetadata
and @Metadata annotations, and writes:

  <output-dir>/mapping.tsv   tab-separated  obf_fqn <TAB> real_fqn <TAB> file
  <output-dir>/mapping.json  same data as JSON  { obf_fqn: real_fqn, ... }
  <output-dir>/by_package/   one file per real package, listing
                             real_fqn <TAB> obf_fqn <TAB> file

If [output-dir] is omitted, files are written next to the sources dir.
EOF
  exit 0
}

[[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]] && usage
SRC="$1"
OUT="${2:-$(dirname "$SRC")/mapping}"
[[ ! -d "$SRC" ]] && { echo "not a directory: $SRC" >&2; exit 1; }

mkdir -p "$OUT/by_package"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/recover_kotlin_names.py" "$SRC" "$OUT"
