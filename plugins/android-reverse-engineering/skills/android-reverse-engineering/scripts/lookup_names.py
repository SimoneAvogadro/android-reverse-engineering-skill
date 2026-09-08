#!/usr/bin/env python3
"""Query the mapping produced by recover_kotlin_names.py."""
import json
import os
import subprocess
import sys


def main():
    if len(sys.argv) < 3:
        print("Usage: lookup_names.py <mapping-dir> <query>")
        print("       lookup_names.py <mapping-dir> -o <obf-fqn>")
        print("       lookup_names.py <mapping-dir> -p <real-package-substring>")
        print("       lookup_names.py <mapping-dir> --grep <regex> <sources-dir>")
        sys.exit(0)

    dir_path = sys.argv[1]
    args = sys.argv[2:]
    map_path = os.path.join(dir_path, "mapping.json")
    if not os.path.isfile(map_path):
        print(f"no mapping.json in {dir_path}", file=sys.stderr)
        sys.exit(1)

    with open(map_path) as fh:
        mapping = json.load(fh)

    rev = {}
    for o, r in mapping.items():
        rev.setdefault(r, []).append(o)

    def search(q):
        ql = q.lower()
        for r in sorted(rev):
            if ql in r.lower():
                print(r)
                for o in sorted(rev[r]):
                    print(f"    {o}")

    def by_obf(o):
        if o not in mapping:
            print(f"no mapping for {o}", file=sys.stderr)
            sys.exit(1)
        print(f"{o}  ->  {mapping[o]}")
        for s in sorted(rev[mapping[o]]):
            if s != o:
                print(f"    sibling: {s}")

    def by_pkg(p):
        pl = p.lower()
        for r in sorted(rev):
            if pl in r.rsplit(".", 1)[0].lower():
                print(r)
                for o in sorted(rev[r]):
                    print(f"    {o}")

    def grep_annot(pattern, sources):
        if sys.platform == "win32":
            cmd = [
                "powershell", "-NoProfile", "-Command",
                f"Get-ChildItem -Path '{sources}' -Recurse -Include *.java -File | "
                f"Select-String -Pattern '{pattern}' | "
                "ForEach-Object {{ $_.Path + ':' + $_.LineNumber + ':' + $_.Line.Trim() }}"
            ]
            res = subprocess.run(cmd, capture_output=True, text=True)
            lines = res.stdout.splitlines()
        else:
            res = subprocess.run(
                ["grep", "-rEn", "--include=*.java", pattern, sources],
                capture_output=True, text=True)
            lines = res.stdout.splitlines()

        for line in lines:
            try:
                path, lineno, content = line.split(":", 2)
            except ValueError:
                continue
            rel = os.path.relpath(path, sources)
            obf = rel.replace(os.sep, ".")[:-5]
            suffix = f"  // {mapping[obf]}" if obf in mapping else ""
            print(f"{rel}:{lineno}:{content}{suffix}")

    if args[0] == "-o" and len(args) == 2:
        by_obf(args[1])
    elif args[0] == "-p" and len(args) == 2:
        by_pkg(args[1])
    elif args[0] == "--grep" and len(args) == 3:
        grep_annot(args[1], args[2])
    else:
        search(" ".join(args))


if __name__ == "__main__":
    main()
