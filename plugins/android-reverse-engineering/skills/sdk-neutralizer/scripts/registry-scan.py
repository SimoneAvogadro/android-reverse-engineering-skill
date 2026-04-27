#!/usr/bin/env python3
"""registry-scan.py — Scan decoded APK against SDK registry for neutralization targets.

Loads SDK registry JSONs, scans smali directories for matching packages,
and generates targets-file + manifest-components-file for neutralize.sh.
Also discovers unknown SDK packages not covered by the registry.

Requires Python 3.6+. No external dependencies.

Exit codes:
  0 — success (matches found)
  1 — error (invalid input, missing files)
  2 — no matches found
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from fnmatch import fnmatch
from pathlib import Path


# =====================================================================
# Constants
# =====================================================================

# Category mapping for --category filter
ADS_CATEGORIES = {"ads", "ads_mediation"}
TRACKER_CATEGORIES = {"analytics", "attribution", "crash_reporting", "social"}

# Known non-SDK library packages to exclude from unknown discovery
KNOWN_LIBRARY_PACKAGES = {
    "android", "androidx", "kotlin", "kotlinx",
    "com/google/protobuf", "com/google/gson", "com/google/common",
    "com/google/android/material", "com/google/android/play",
    "com/google/android/exoplayer", "com/google/android/exoplayer2",
    "com/google/android/datatransport", "com/google/android/recaptcha",
    "com/google/crypto", "com/google/flatbuffers",
    "com/squareup/okhttp3", "com/squareup/okhttp", "com/squareup/moshi",
    "com/squareup/wire", "com/squareup/picasso",
    "okhttp3", "okio",
    "retrofit2", "retrofit",
    "com/jakewharton",
    "dagger", "com/google/dagger",
    "javax/inject", "javax/annotation",
    "io/reactivex", "io/reactivex/rxjava3",
    "com/bumptech/glide",
    "com/airbnb/lottie",
    "org/json", "org/intellij", "org/jetbrains",
    "org/apache",
    "com/google/firebase/components", "com/google/firebase/inject",
    "com/google/firebase/encoders", "com/google/firebase/installations",
    "com/google/firebase/sessions", "com/google/firebase/messaging",
    "com/google/firebase/datatransport",
    "com/google/android/gms/base", "com/google/android/gms/common",
    "com/google/android/gms/tasks", "com/google/android/gms/flags",
    "com/google/android/gms/dynamic", "com/google/android/gms/dynamite",
    "com/google/android/gms/security", "com/google/android/gms/cloudmessaging",
    "com/google/android/gms/phenotype",
    "com/google/android/ump",
    "bolts",
    "com/github",
}

# Minimum class count to consider a package as a potential SDK
MIN_CLASSES_FOR_UNKNOWN = 10

# Minimum package depth (segments) to consider as SDK (not obfuscated)
MIN_PACKAGE_DEPTH = 3


# =====================================================================
# Registry loading
# =====================================================================

def load_registry(registry_dir):
    """Load all SDK JSON files from registry directory."""
    sdks = []
    registry_path = Path(registry_dir)

    if not registry_path.is_dir():
        print(f"Error: Registry directory not found: {registry_dir}", file=sys.stderr)
        sys.exit(1)

    for json_file in sorted(registry_path.glob("*.json")):
        if json_file.name.startswith("_"):
            continue
        try:
            with open(json_file, "r", encoding="utf-8") as f:
                sdk = json.load(f)
            sdks.append(sdk)
        except (json.JSONDecodeError, IOError) as e:
            print(f"Warning: Skipping {json_file.name}: {e}", file=sys.stderr)

    return sdks


def filter_sdks_by_category(sdks, category):
    """Filter SDKs by category: ads, trackers, or all."""
    if category == "all":
        return sdks
    elif category == "ads":
        return [s for s in sdks if s.get("category") in ADS_CATEGORIES]
    elif category == "trackers":
        return [s for s in sdks if s.get("category") in TRACKER_CATEGORIES]
    return sdks


# =====================================================================
# Smali scanning
# =====================================================================

def find_smali_dirs(decoded_dir):
    """Find all smali directories (multidex support)."""
    decoded = Path(decoded_dir)
    dirs = sorted(decoded.glob("smali*"))
    return [d for d in dirs if d.is_dir()]


def get_app_package(decoded_dir):
    """Extract app package from AndroidManifest.xml."""
    manifest = Path(decoded_dir) / "AndroidManifest.xml"
    if not manifest.exists():
        return None
    try:
        content = manifest.read_text(encoding="utf-8")
        match = re.search(r'<manifest[^>]+package="([^"]+)"', content)
        if match:
            return match.group(1).replace(".", "/")
    except IOError:
        pass
    return None


def scan_packages(smali_dirs):
    """Scan smali directories and return a map of package -> class count."""
    package_classes = defaultdict(int)

    for smali_dir in smali_dirs:
        for smali_file in smali_dir.rglob("*.smali"):
            rel = smali_file.relative_to(smali_dir)
            parts = rel.parts[:-1]  # directory parts = package
            if parts:
                package = "/".join(parts)
                package_classes[package] += 1

    return package_classes


def check_package_exists(smali_dirs, package_dot):
    """Check if a dot-separated package exists in any smali directory."""
    package_path = package_dot.replace(".", "/")
    for smali_dir in smali_dirs:
        pkg_dir = smali_dir / package_path
        if pkg_dir.is_dir():
            return True
    return False


def find_sdk_matches(sdks, smali_dirs):
    """Match registry SDKs against smali directories. Returns list of (sdk, matched_packages)."""
    matches = []
    for sdk in sdks:
        matched_pkgs = []
        for pkg in sdk.get("packages", []):
            if check_package_exists(smali_dirs, pkg):
                matched_pkgs.append(pkg)
        if matched_pkgs:
            matches.append((sdk, matched_pkgs))
    return matches


# =====================================================================
# Target generation
# =====================================================================

def java_to_smali_class(java_class):
    """Convert Java class name to smali path: com.example.Foo -> com/example/Foo"""
    return java_class.replace(".", "/")


def generate_targets(sdk, depth):
    """Generate targets-file lines for a matched SDK at given depth level.

    Depth 1: entry_points only
    Depth 2: entry_points + ad_operations
    Depth 3: entry_points + ad_operations + deep_patterns
    """
    lines = []
    targets = sdk.get("targets", {})
    protected = sdk.get("protected_patterns", [])
    sdk_name = sdk.get("display_name", sdk.get("sdk_id", "Unknown"))

    # Collect protected method patterns
    protected_methods = set()
    for pp in protected:
        pattern = pp.get("pattern", "")
        # Extract method name from patterns like "*.getActivity()*"
        m = re.search(r'\*\.(\w+)\(', pattern)
        if m:
            protected_methods.add(m.group(1))

    # Level 1: entry_points
    for class_target in targets.get("entry_points", []):
        cls = java_to_smali_class(class_target["class"])
        for method in class_target.get("methods", []):
            method_name = method["name"]
            if method_name in protected_methods:
                continue
            lines.append(f"# [{sdk_name}] entry_point")
            lines.append(f"{cls}:{method_name}")

    # Level 2: ad_operations
    if depth >= 2:
        for class_target in targets.get("ad_operations", []):
            cls = java_to_smali_class(class_target["class"])
            for method in class_target.get("methods", []):
                method_name = method["name"]
                if method_name in protected_methods:
                    continue
                lines.append(f"# [{sdk_name}] ad_operation")
                lines.append(f"{cls}:{method_name}")

    # Level 3: deep_patterns (package wildcards)
    if depth >= 3:
        for dp in targets.get("deep_patterns", []):
            glob_pattern = dp["package_glob"]
            # Convert "com.example.pkg.**" -> "com/example/pkg/**:*"
            pkg_path = glob_pattern.replace(".", "/").rstrip("*").rstrip("/")
            lines.append(f"# [{sdk_name}] deep_pattern: {dp.get('rule', 'stub_all_void')}")
            lines.append(f"{pkg_path}/**:*")

    return lines


def generate_manifest_components(sdk):
    """Generate manifest-components-file lines for a matched SDK."""
    lines = []
    sdk_name = sdk.get("display_name", sdk.get("sdk_id", "Unknown"))
    for comp in sdk.get("manifest_components", []):
        cls = comp["class"]
        lines.append(f"{cls}|{sdk_name}")
    return lines


# =====================================================================
# Unknown package discovery
# =====================================================================

def is_obfuscated_package(package):
    """Check if a package looks obfuscated (single-letter segments, too short)."""
    parts = package.split("/")
    # Single-letter segments are obfuscated (a/, b/c/, etc.)
    if all(len(p) <= 2 for p in parts):
        return True
    # First two segments are single letters
    if len(parts) >= 2 and len(parts[0]) <= 1 and len(parts[1]) <= 1:
        return True
    return False


def is_known_library(package):
    """Check if a package matches known non-SDK libraries."""
    for known in KNOWN_LIBRARY_PACKAGES:
        if package == known or package.startswith(known + "/"):
            return True
    return False


def find_unknown_packages(package_classes, matched_sdk_packages, app_package):
    """Find packages that might be unknown SDKs.

    Filters:
    - Exclude matched SDK packages
    - Exclude app package
    - Exclude known libraries (androidx, kotlin, okhttp, etc.)
    - Exclude obfuscated packages (single-letter names)
    - Minimum class count threshold
    - Minimum package depth (3+ segments)
    """
    # Build set of all matched SDK root packages (as paths)
    sdk_roots = set()
    for pkg_dot in matched_sdk_packages:
        sdk_roots.add(pkg_dot.replace(".", "/"))

    unknowns = []

    # Aggregate class counts at the 3-segment level for better grouping
    aggregated = defaultdict(int)
    for pkg, count in package_classes.items():
        parts = pkg.split("/")
        if len(parts) >= 3:
            root = "/".join(parts[:3])
        else:
            root = pkg
        aggregated[root] += count

    for package, class_count in sorted(aggregated.items(), key=lambda x: -x[1]):
        # Check minimum class count
        if class_count < MIN_CLASSES_FOR_UNKNOWN:
            continue

        # Check package depth
        parts = package.split("/")
        if len(parts) < MIN_PACKAGE_DEPTH:
            continue

        # Skip obfuscated
        if is_obfuscated_package(package):
            continue

        # Skip known libraries
        if is_known_library(package):
            continue

        # Skip app package
        if app_package and (package == app_package or package.startswith(app_package + "/")):
            continue

        # Skip matched SDK packages
        is_matched = False
        for sdk_root in sdk_roots:
            if package == sdk_root or package.startswith(sdk_root + "/"):
                is_matched = True
                break
        if is_matched:
            continue

        unknowns.append((package, class_count))

    return unknowns


# =====================================================================
# Report generation
# =====================================================================

def generate_report(matches, unknowns, depth, category):
    """Generate JSON report of scan results."""
    report = {
        "scan_config": {
            "depth": depth,
            "category": category,
        },
        "matched_sdks": [],
        "unknown_packages": [],
    }

    for sdk, matched_pkgs in matches:
        targets = sdk.get("targets", {})
        n_entry = sum(len(ct.get("methods", [])) for ct in targets.get("entry_points", []))
        n_ops = sum(len(ct.get("methods", [])) for ct in targets.get("ad_operations", []))
        n_deep = len(targets.get("deep_patterns", []))
        n_manifest = len(sdk.get("manifest_components", []))

        # Count targets at current depth
        n_targets = n_entry
        if depth >= 2:
            n_targets += n_ops
        if depth >= 3:
            n_targets += n_deep

        report["matched_sdks"].append({
            "sdk_id": sdk["sdk_id"],
            "display_name": sdk["display_name"],
            "category": sdk["category"],
            "matched_packages": matched_pkgs,
            "targets_count": n_targets,
            "manifest_components_count": n_manifest,
            "depth_breakdown": {
                "entry_points": n_entry,
                "ad_operations": n_ops,
                "deep_patterns": n_deep,
            },
        })

    for package, class_count in unknowns:
        report["unknown_packages"].append({
            "package": package,
            "class_count": class_count,
        })

    return report


# =====================================================================
# Main
# =====================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Scan decoded APK against SDK registry for neutralization targets."
    )
    parser.add_argument("decoded_dir", help="Path to apktool-decoded APK directory")
    parser.add_argument(
        "--registry", required=True,
        help="Path to SDK registry directory containing JSON files"
    )
    parser.add_argument(
        "--depth", type=int, choices=[1, 2, 3], default=1,
        help="Neutralization depth: 1=entry_points, 2=+ad_operations, 3=+deep_patterns (default: 1)"
    )
    parser.add_argument(
        "--category", choices=["ads", "trackers", "all"], default="all",
        help="Filter SDKs by category (default: all)"
    )
    parser.add_argument(
        "--output-dir",
        help="Output directory for generated files (default: decoded-dir)"
    )

    args = parser.parse_args()

    decoded_dir = args.decoded_dir
    output_dir = args.output_dir or decoded_dir

    # Validate decoded directory
    if not os.path.isdir(decoded_dir):
        print(f"Error: Directory not found: {decoded_dir}", file=sys.stderr)
        sys.exit(1)

    # Find smali directories
    smali_dirs = find_smali_dirs(decoded_dir)
    if not smali_dirs:
        print(f"Error: No smali/ directory found in {decoded_dir}", file=sys.stderr)
        sys.exit(1)

    # Load and filter registry
    sdks = load_registry(args.registry)
    if not sdks:
        print("Error: No SDK entries loaded from registry", file=sys.stderr)
        sys.exit(1)

    sdks = filter_sdks_by_category(sdks, args.category)

    # Scan for package existence
    package_classes = scan_packages(smali_dirs)
    app_package = get_app_package(decoded_dir)

    # Find SDK matches
    matches = find_sdk_matches(sdks, smali_dirs)

    # Collect all matched SDK packages for unknown discovery
    all_matched_packages = set()
    for sdk, matched_pkgs in matches:
        for pkg in sdk.get("packages", []):
            all_matched_packages.add(pkg)

    # Generate targets file
    targets_lines = []
    targets_lines.append("# Auto-generated by registry-scan.py")
    targets_lines.append(f"# Depth: {args.depth} | Category: {args.category}")
    targets_lines.append("")

    for sdk, matched_pkgs in matches:
        sdk_targets = generate_targets(sdk, args.depth)
        if sdk_targets:
            targets_lines.extend(sdk_targets)
            targets_lines.append("")

    # Generate manifest components file
    manifest_lines = []
    for sdk, matched_pkgs in matches:
        manifest_lines.extend(generate_manifest_components(sdk))

    # Find unknown packages
    unknowns = find_unknown_packages(package_classes, all_matched_packages, app_package)

    # Generate report
    report = generate_report(matches, unknowns, args.depth, args.category)

    # Write output files
    os.makedirs(output_dir, exist_ok=True)

    targets_path = os.path.join(output_dir, "registry-targets.txt")
    with open(targets_path, "w", encoding="utf-8") as f:
        f.write("\n".join(targets_lines) + "\n")

    manifest_path = os.path.join(output_dir, "registry-manifest.txt")
    with open(manifest_path, "w", encoding="utf-8") as f:
        f.write("\n".join(manifest_lines) + "\n")

    report_path = os.path.join(output_dir, "registry-report.json")
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
        f.write("\n")

    # Machine-readable stdout
    for sdk, matched_pkgs in matches:
        targets = sdk.get("targets", {})
        n_entry = sum(len(ct.get("methods", [])) for ct in targets.get("entry_points", []))
        n_ops = sum(len(ct.get("methods", [])) for ct in targets.get("ad_operations", []))
        n_deep = len(targets.get("deep_patterns", []))
        n_targets = n_entry
        if args.depth >= 2:
            n_targets += n_ops
        if args.depth >= 3:
            n_targets += n_deep
        print(f"MATCHED:{sdk['sdk_id']}:{sdk['display_name']}:{sdk['category']}:{n_targets}")

    for package, class_count in unknowns:
        print(f"UNKNOWN_PACKAGE:{package}:{class_count}")

    print(f"REGISTRY_TARGETS:{targets_path}")
    print(f"REGISTRY_MANIFEST:{manifest_path}")

    if not matches:
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
