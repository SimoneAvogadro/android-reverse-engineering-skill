#!/usr/bin/env bash
# lookup-name.sh: Query the mapping produced by recover-kotlin-names.sh.
#
# Modes:
#   lookup-name.sh <mapping-dir> <substring>      search by real-FQN substring
#   lookup-name.sh <mapping-dir> -o <obf>         resolve obf -> real
#   lookup-name.sh <mapping-dir> -p <pkg>         list a real package
#   lookup-name.sh <mapping-dir> --grep <regex> <sources-dir>
#       grep decompiled sources and annotate each hit with the real class name

set -euo pipefail

usage() {
  cat <<EOF
Usage: lookup-name.sh <mapping-dir> <query>
       lookup-name.sh <mapping-dir> -o <obf-fqn>
       lookup-name.sh <mapping-dir> -p <real-package-substring>
       lookup-name.sh <mapping-dir> --grep <regex> <sources-dir>

<mapping-dir> is the directory produced by recover-kotlin-names.sh
(must contain mapping.json).
EOF
  exit 0
}

[[ $# -lt 2 ]] && usage
DIR="$1"; shift
[[ ! -f "$DIR/mapping.json" ]] && { echo "no mapping.json in $DIR" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/lookup_names.py" "$DIR" "$@"
