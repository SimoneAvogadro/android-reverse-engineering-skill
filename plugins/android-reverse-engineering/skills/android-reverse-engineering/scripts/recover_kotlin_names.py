#!/usr/bin/env python3
"""Rebuild obfuscated -> real Kotlin class-name map from decompiled sources."""
import json
import os
import re
import sys
from collections import defaultdict

RE_DEBUG = re.compile(r'@DebugMetadata\([^)]*?c\s*=\s*"([^"]+)"', re.S)
RE_DTWO = re.compile(r'@Metadata\([^)]*?d2\s*=\s*\{([^}]*)\}', re.S)
RE_LCLASS = re.compile(r'L([A-Za-z][\w/$]+);')
RE_RENAMED = re.compile(r'/\*\s*renamed from:\s*([\w.$]+)\s*\*/')

SKIP_PREFIXES = (
    "kotlin.", "kotlinx.", "androidx.", "android.", "java.", "javax.",
    "com.google.", "com.facebook.", "com.appsflyer.", "com.datadog.",
    "io.ktor.", "io.sentry.", "io.realm.", "okhttp3.", "okio.",
    "com.squareup.", "com.bumptech.", "com.airbnb.", "com.payu.",
    "com.storyteller.", "zendesk.", "io.intercom.", "com.microsoft.",
    "com.tinder.", "com.hotjar.", "com.amplitude.", "com.segment.",
    "com.mixpanel.", "com.onesignal.", "com.stripe.", "com.braintreepayments.",
    "retrofit2.", "dagger.", "javax.inject.", "org.jetbrains.",
)


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("Usage: recover_kotlin_names.py <decompiled-sources-dir> [output-dir]")
        sys.exit(0)

    src = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(src), "mapping")

    if not os.path.isdir(src):
        print(f"not a directory: {src}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(os.path.join(out, "by_package"), exist_ok=True)

    mapping = {}
    file_real = {}
    counts = defaultdict(int)

    for dp, _, files in os.walk(src):
        for f in files:
            if not f.endswith(".java"):
                continue
            path = os.path.join(dp, f)
            rel = os.path.relpath(path, src)
            obf = rel[:-5].replace(os.sep, ".")
            if obf.startswith(SKIP_PREFIXES):
                continue
            try:
                with open(path, "r", errors="replace") as fh:
                    text = fh.read()
            except OSError:
                continue
            real = None

            m = RE_DEBUG.search(text)
            if m:
                real = m.group(1).split("$", 1)[0]
                counts["debug_meta"] += 1

            if not real:
                m = RE_DTWO.search(text)
                if m:
                    for lm in RE_LCLASS.finditer(m.group(1)):
                        cand = lm.group(1).replace("/", ".").split("$", 1)[0]
                        if "." in cand and not cand.startswith(("kotlin.", "java.", "android")):
                            real = cand
                            counts["d2"] += 1
                            break

            if not real:
                m = RE_RENAMED.search(text)
                if m:
                    real = m.group(1)
                    counts["renamed"] += 1

            if real:
                mapping[obf] = real
                file_real[obf] = path

    with open(os.path.join(out, "mapping.tsv"), "w") as fh:
        fh.write("obf_fqn\treal_fqn\tfile\n")
        for k in sorted(mapping):
            fh.write(f"{k}\t{mapping[k]}\t{file_real[k]}\n")

    with open(os.path.join(out, "mapping.json"), "w") as fh:
        json.dump(mapping, fh, indent=2, sort_keys=True)

    by_pkg = defaultdict(list)
    for obf, real in mapping.items():
        pkg = real.rsplit(".", 1)[0] if "." in real else "(default)"
        by_pkg[pkg].append((real, obf, file_real[obf]))

    for pkg, rows in by_pkg.items():
        safe = os.path.basename(pkg).replace(".", "_") or "default"
        with open(os.path.join(out, "by_package", f"{safe}.txt"), "w") as fh:
            for real, obf, p in sorted(rows):
                fh.write(f"{real}\t{obf}\t{p}\n")

    print(f"Recovered {len(mapping)} class names")
    for k, v in counts.items():
        print(f"  via {k}: {v}")
    print(f"Real packages: {len(by_pkg)}")
    print(f"Wrote {out}/mapping.tsv, mapping.json, by_package/")


if __name__ == "__main__":
    main()
