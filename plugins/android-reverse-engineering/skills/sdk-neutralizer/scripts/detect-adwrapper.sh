#!/usr/bin/env bash
# detect-adwrapper.sh — Heuristically detect a PUBLISHER'S IN-HOUSE ad/analytics
# mediation wrapper in an apktool-decoded APK: the app-owned layer that calls the
# network ad SDKs (or serves house/WebView ads) on the app's behalf.
#
# Why this exists: registry-scan.py neutralizes each KNOWN third-party network SDK
# (AdMob, AppLovin, IronSource, ...). But some publishers ship their own wrapper
# (e.g. Rovio's com.rovio.beacon in Bad Piggies, Guru's guru.ads.fusion) that
# drives those SDKs AND can serve direct WebView/MRAID "house" interstitials with
# NO third-party SDK involved. Neutralizing every network SDK does not stop that
# house-ad path. This detector spots such a wrapper so the user is told the
# network-SDK neutralization may be incomplete, and is pointed at the discovery
# workflow (SKILL.md Phases 3b/3c) or a dedicated registry entry.
#
# DETECTION ONLY: nothing in the decoded directory is modified; nothing is
# removed, disabled or bypassed. Output is informational and the script always
# exits 0 (unless its arguments are invalid).
#
# Heuristic (a namespace is flagged when it is app-owned code — NOT a known
# third-party SDK or common library — that either references MULTIPLE ad-network
# packages while carrying ad-shaped classes, OR ships its own WebView+MRAID ad
# path):
#   signals per candidate package:
#     adclasses  — classes named like *Ads*/*AdManager*/*Mediation*/*Interstitial*
#                  /*Rewarded*/*Banner*/*AdView*/...
#     analytics  — classes named like *Tracking*/*Analytics*/*Attribution*/*Beacon*
#     networks   — how many distinct known ad-network packages the code references
#                  (com/applovin, com/google/android/gms/ads, com/unity3d,
#                   com/ironsource, com/mbridge, com/vungle, com/adcolony,
#                   com/facebook/ads, ...)
#     webview    — WebView-based ad classes present
#     mraid      — MRAID (rich-media ad) code present  (webview+mraid = house-ad path)
#     vendor     — the package shares the app's own top-2 package segments
#   FLAG when: networks >= 2  OR  (webview AND mraid).   (Not on an "Ads" name alone.)
#   confidence:
#     high   — (vendor AND networks>=2) OR (vendor AND webview+mraid)
#              OR (networks>=2 AND webview+mraid)
#     medium — networks>=2 (no vendor, no house-ad path)  OR (webview+mraid + ad classes)
#     low    — a weaker webview+mraid-only match
#
# Known third-party SDKs are excluded using the registry (registry/*.json
# `packages`), EXCEPT entries flagged "in_house_wrapper": true (those are exactly
# what we look for — a flagged candidate that already has such an entry is
# annotated registry=<sdk_id>), plus a built-in list of common libraries and
# ad-tech infrastructure (OMID, SafeDK, mediation-safety layers, ...).
#
# Portable: bash 3.2+ (macOS) and BSD/GNU userland. No grep -P, no sed -i,
# no associative arrays.
#
# Exit codes:
#   0 — check completed (whatever it found: the result is informational)
#   1 — error (invalid input, unknown option)
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P)

usage() {
  cat <<EOF
Usage: detect-adwrapper.sh <decoded-dir> [OPTIONS]

Heuristically detect a publisher's in-house ad/analytics mediation wrapper in a
directory decoded by decode-apk.sh (apktool output). Detection only: nothing is
modified.

Arguments:
  <decoded-dir>       Directory containing AndroidManifest.xml and smali*/

Options:
  --registry <dir>    SDK registry directory (default: <script-dir>/../registry).
                      Used to exclude known third-party SDK packages.
  -h, --help          Show this help message

Output:
  ADWRAPPER_DETECTED:<package>:<high|medium|low>:<evidence,...>
  ADWRAPPER_SUMMARY:<none|candidate>

  evidence keys: adclasses=N,networks=<a+b+..>,webview=<yes|no>,mraid=<yes|no>,
                 analytics=<yes|no>,vendor=<yes|no>[,registry=<sdk_id>]

Exit codes: 0 = check completed (informational), 1 = error
EOF
  exit "${1:-0}"
}

DECODED_DIR=""
REGISTRY_DIR="$SCRIPT_DIR/../registry"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)  usage ;;
    --registry) shift; REGISTRY_DIR="${1:-}"; shift || true ;;
    -*)         echo "Error: Unknown option $1" >&2; usage 1 >&2 ;;
    *)
      if [[ -n "$DECODED_DIR" ]]; then
        echo "Error: only one decoded directory can be given" >&2
        exit 1
      fi
      DECODED_DIR="$1"; shift ;;
  esac
done

if [[ -z "$DECODED_DIR" ]]; then
  echo "Error: No decoded directory specified." >&2
  usage 1 >&2
fi
if [[ ! -d "$DECODED_DIR" ]]; then
  echo "Error: Not a directory: $DECODED_DIR" >&2
  exit 1
fi
DECODED_DIR=$(cd "$DECODED_DIR" && pwd -P)
MANIFEST="$DECODED_DIR/AndroidManifest.xml"
if [[ ! -f "$MANIFEST" ]]; then
  echo "Error: $DECODED_DIR has no AndroidManifest.xml (not an apktool-decoded directory?)" >&2
  exit 1
fi

# =====================================================================
# Known ad-network / analytics SDK package roots.
# "root|label" — label is what appears in networks=<...> evidence. These roots
# are BOTH the reference-signal set (a wrapper references several of them) AND
# part of the candidate exclusion set (a network SDK is not an in-house wrapper).
# =====================================================================
NETWORK_ROOTS='com/applovin|applovin
com/google/android/gms/ads|admob
com/google/ads|admob
com/unity3d|unity
com/ironsource|ironsource
com/mbridge|mintegral
com/vungle|vungle
com/adcolony|adcolony
com/facebook/ads|meta
com/chartboost|chartboost
com/inmobi|inmobi
com/bytedance|pangle
com/fyber|fyber
com/smaato|smaato
com/tapjoy|tapjoy
com/mopub|mopub
com/pubmatic|pubmatic
com/moloco|moloco
com/mobilefuse|mobilefuse
io/bidmachine|bidmachine
net/pubnative|pubnative
com/amazon/device/ads|amazon
com/yandex/mobile/ads|yandex
com/ogury|ogury
io/presage|ogury'

# Common libraries + ad-tech infrastructure / mediation-safety layers that are
# NOT publisher-owned wrappers (excluded as candidates). Third-party network and
# analytics SDKs come additionally from the registry (see below).
COMMON_ROOTS='android
androidx
kotlin
kotlinx
com/google
com/squareup
okhttp3
okio
retrofit2
retrofit
com/jakewharton
dagger
javax
io/reactivex
com/bumptech
com/airbnb
org/json
org/intellij
org/jetbrains
org/apache
org/chromium
org/checkerframework
org/slf4j
bolts
com/github
com/facebook
com/amazon
com/iab/omid
com/safedk
sg/bigo
com/bykv
com/explorestack
gatewayprotocol
com/five_corp
com/gameanalytics
com/localytics
com/singular
com/nefta
com/tiktok
com/microsoft
io/ktor
io/branch
io/appmetrica
coil
zendesk
cz/msebera
com/caverock
com/yahoo
com/moat
com/adjust
com/appsflyer
com/mixpanel
com/braze
com/clevertap
com/yandex
j$'

# =====================================================================
# Registry: build the third-party-SDK exclusion list, and remember which
# packages belong to in_house_wrapper entries (so they are NOT excluded and can
# be annotated registry=<sdk_id>).
# =====================================================================
REG_EXCL=""       # newline list of slash-packages (third-party SDKs to exclude)
INHOUSE_MAP=""    # newline "slashpkg|sdk_id" for in_house_wrapper entries
if [[ -d "$REGISTRY_DIR" ]]; then
  for f in "$REGISTRY_DIR"/*.json; do
    [[ -e "$f" ]] || continue
    case "$(basename "$f")" in _*) continue ;; esac
    sdk_id=$(grep -oE '"sdk_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" | head -1 \
             | sed -e 's/.*"sdk_id"[[:space:]]*:[[:space:]]*"//' -e 's/"$//')
    [[ -z "$sdk_id" ]] && sdk_id=$(basename "$f" .json)
    inhouse=no
    if grep -qE '"in_house_wrapper"[[:space:]]*:[[:space:]]*true' "$f"; then inhouse=yes; fi
    # package strings look like "com.rovio.beacon"; take dotted packages only
    while IFS= read -r pkg; do
      [[ -z "$pkg" ]] && continue
      slp=$(printf '%s' "$pkg" | sed 's#\.#/#g')
      if [[ "$inhouse" == yes ]]; then
        INHOUSE_MAP="${INHOUSE_MAP}${slp}|${sdk_id}"$'\n'
      else
        REG_EXCL="${REG_EXCL}${slp}"$'\n'
      fi
    done < <(grep -oE '"[a-z][a-z0-9_]+(\.[a-z0-9_]+)+"' "$f" \
             | tr -d '"' | grep -E '^(com|io|net|org|sg|guru|de|fr|jp)\.')
  done
fi

# Full exclusion set (one per line, unique)
EXCL=$(
  printf '%s\n' "$NETWORK_ROOTS" | sed 's/|.*//'
  printf '%s\n' "$COMMON_ROOTS"
  printf '%s\n' "$REG_EXCL"
)
EXCL=$(printf '%s\n' "$EXCL" | LC_ALL=C sort -u | grep -v '^$' || true)

# is_excluded PKG : true if PKG is (a child of / equal to / an ancestor of) any
# excluded root. The ancestor test handles depth-3 candidate roots that sit
# above a deeper registry package (e.g. com/yandex/mobile vs com.yandex.mobile.ads).
is_excluded() {
  local pkg="$1" e
  while IFS= read -r e; do
    [[ -z "$e" ]] && continue
    case "$pkg" in "$e"|"$e"/*) return 0 ;; esac
    case "$e" in "$pkg"/*) return 0 ;; esac
  done <<EOF
$EXCL
EOF
  return 1
}

# inhouse_id PKG : echo the sdk_id of an in_house_wrapper registry entry whose
# package equals or contains PKG (or vice versa), else empty.
inhouse_id() {
  local pkg="$1" line p id
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    p="${line%%|*}"; id="${line#*|}"
    case "$pkg" in "$p"|"$p"/*) echo "$id"; return 0 ;; esac
    case "$p" in "$pkg"/*) echo "$id"; return 0 ;; esac
  done <<EOF
$INHOUSE_MAP
EOF
  return 0
}

# =====================================================================
# App package + vendor root (top 2 segments)
# =====================================================================
APP_PKG=$(grep -oE '<manifest[^>]+package="[^"]*"' "$MANIFEST" | head -1 \
          | sed -e 's/.*package="//' -e 's/"$//' || true)
APP_SL=$(printf '%s' "$APP_PKG" | sed 's#\.#/#g')
VROOT=$(printf '%s' "$APP_SL" | awk -F/ '{ if (NF>=2) print $1"/"$2; else print $0 }')

# =====================================================================
# smali dirs
# =====================================================================
SMALI_DIRS=()
while IFS= read -r d; do
  [[ -n "$d" ]] && SMALI_DIRS+=("$d")
done < <(find "$DECODED_DIR" -mindepth 1 -maxdepth 1 -type d -name 'smali*' | LC_ALL=C sort)

echo "=== In-house ad/analytics wrapper check (detection only): $DECODED_DIR ==="

if [[ ${#SMALI_DIRS[@]} -eq 0 ]]; then
  echo "No smali/ directory found — nothing to scan."
  echo "ADWRAPPER_SUMMARY:none"
  exit 0
fi

# Class-name patterns (matched on the smali file basename)
AD_RE='([Aa]ds?[A-Z]|AdManager|AdsSdk|Mediation|Interstitial|Rewarded|[Bb]anner|AdView|AdLoader|AdUnit|AdConfig|AdNetwork|AdServer|AdProvider|Advert)'
AN_RE='(Tracking|Analytics|Attribution|Beacon|Telemetry)'

# =====================================================================
# 1. Candidate roots: 3-segment (or shorter) package roots that contain an
#    ad-shaped OR analytics-shaped class, minus the exclusion set.
# =====================================================================
CAND=$(
  for s in "${SMALI_DIRS[@]}"; do
    find "$s" -type f -name '*.smali' 2>/dev/null \
      | grep -E "/[^/]*($AD_RE|$AN_RE)[^/]*\.smali$" \
      | sed "s#^$s/##" \
      | while IFS= read -r rel; do
          dir=$(dirname "$rel")
          printf '%s\n' "$dir" | awk -F/ '{ if (NF>=3) print $1"/"$2"/"$3; else print $0 }'
        done
  done | LC_ALL=C sort -u | grep -v '^$' || true
)

# Network root alternation for a single grep pass (roots only, no labels)
NET_ALT=$(printf '%s\n' "$NETWORK_ROOTS" | sed 's/|.*//' | paste -sd'|' - 2>/dev/null \
          || printf '%s\n' "$NETWORK_ROOTS" | sed 's/|.*//' | tr '\n' '|' | sed 's/|$//')

# =====================================================================
# 2. Score each surviving candidate
# =====================================================================
FLAGGED=""   # lines: pkgdot|conf|evidence
SUMMARY=none

while IFS= read -r R; do
  [[ -z "$R" ]] && continue
  is_excluded "$R" && continue

  # collect this root's smali files across all smali dirs
  RFILES=()
  for s in "${SMALI_DIRS[@]}"; do
    if [[ -d "$s/$R" ]]; then
      while IFS= read -r rf; do [[ -n "$rf" ]] && RFILES+=("$rf"); done \
        < <(find "$s/$R" -type f -name '*.smali' 2>/dev/null)
    fi
  done
  [[ ${#RFILES[@]} -eq 0 ]] && continue

  # networks: one grep pass, dedup matched roots, drop refs to R itself
  netlabels=""
  netcount=0
  # /dev/null guarantees grep always has one readable arg (some per-dir paths
  # below will not exist); grep ignores the missing ones (stderr suppressed).
  hits=$(grep -rhoE "L($NET_ALT)" /dev/null "${SMALI_DIRS[@]/%//$R}" 2>/dev/null | LC_ALL=C sort -u || true)
  while IFS='|' read -r nr label; do
    [[ -z "$nr" ]] && continue
    case "$R" in "$nr"|"$nr"/*) continue ;; esac
    # match against the captured hit list without a pipe (pipefail-safe)
    case $'\n'"$hits"$'\n' in
      *$'\n'"L$nr"$'\n'*)
        case "+$netlabels+" in
          *"+$label+"*) : ;;                     # dedup label (admob appears twice)
          *) netlabels="${netlabels:+$netlabels+}$label"; netcount=$((netcount + 1)) ;;
        esac ;;
    esac
  done <<EOF
$NETWORK_ROOTS
EOF

  # ad / analytics class counts (by basename; same regexes as the .ps1 version)
  adn=0; ann=0
  for rf in "${RFILES[@]}"; do
    b=${rf##*/}
    if [[ "$b" =~ $AD_RE ]]; then adn=$((adn + 1)); fi
    if [[ "$b" =~ $AN_RE ]]; then ann=$((ann + 1)); fi
  done

  # webview + mraid presence (one grep each; command substitution keeps the
  # pipeline's SIGPIPE from tripping set -o pipefail in the test)
  wv=no; mr=no
  if [[ -n "$(grep -rlF 'Landroid/webkit/WebView' "${SMALI_DIRS[@]/%//$R}" 2>/dev/null | head -1)" ]]; then wv=yes; fi
  if [[ -n "$(grep -rliE 'mraid' "${SMALI_DIRS[@]/%//$R}" 2>/dev/null | head -1)" ]]; then mr=yes; fi
  wmc=no; [[ "$wv" == yes && "$mr" == yes ]] && wmc=yes

  # vendor match
  vm=no
  case "$R" in "$VROOT"|"$VROOT"/*) vm=yes ;; esac

  # flag decision
  if [[ $netcount -lt 2 && "$wmc" != yes ]]; then continue; fi

  # confidence
  conf=low
  if [[ "$wmc" == yes && $adn -ge 1 ]]; then conf=medium; fi
  if [[ $netcount -ge 2 ]]; then conf=medium; fi
  if { [[ "$vm" == yes ]] && { [[ $netcount -ge 2 ]] || [[ "$wmc" == yes ]]; }; } \
     || { [[ $netcount -ge 2 ]] && [[ "$wmc" == yes ]]; }; then
    conf=high
  fi

  pkgdot=$(printf '%s' "$R" | sed 's#/#.#g')
  [[ -z "$netlabels" ]] && netlabels="-"
  reg=$(inhouse_id "$R")
  ev="adclasses=$adn,networks=$netlabels,webview=$wv,mraid=$mr,analytics=$( [[ $ann -ge 1 ]] && echo yes || echo no ),vendor=$vm"
  [[ -n "$reg" ]] && ev="$ev,registry=$reg"

  FLAGGED="${FLAGGED}${pkgdot}|${conf}|${ev}"$'\n'
done <<EOF
$CAND
EOF

# =====================================================================
# Report (high confidence first, then medium, then low)
# =====================================================================
emit_conf() {
  local want="$1" line pkg conf ev
  while IFS='|' read -r pkg conf ev; do
    [[ -z "$pkg" ]] && continue
    [[ "$conf" == "$want" ]] || continue
    echo "ADWRAPPER_DETECTED:$pkg:$conf:$ev"
    case "$ev" in
      *registry=*)
        regid="${ev##*registry=}"; regid="${regid%%,*}"
        echo "  -> in-house wrapper '$pkg' [$conf] — already has a registry entry ($regid); make sure that entry is applied." ;;
      *)
        echo "  -> in-house wrapper candidate '$pkg' [$conf] — no registry entry; the network-SDK neutralization may not fully stop ads." ;;
    esac
  done <<EOT
$FLAGGED
EOT
}

if [[ -n "${FLAGGED//[$'\n']/}" ]]; then
  SUMMARY=candidate
  emit_conf high
  emit_conf medium
  emit_conf low
fi

echo "ADWRAPPER_SUMMARY:$SUMMARY"

if [[ "$SUMMARY" == candidate ]]; then
  echo
  echo "Note: this app appears to carry a publisher's own in-house ad/analytics wrapper"
  echo "(a layer that drives the network ad SDKs, or serves house/WebView ads, itself)."
  echo "Neutralizing the third-party network SDKs from the registry may NOT fully stop ads"
  echo "(a house/WebView ad path can survive). Consider adding a dedicated registry entry for"
  echo "the package above, or run the unknown-SDK discovery pass (SKILL.md Phases 3b/3c) on it."
else
  echo "No in-house ad/analytics wrapper detected (network-SDK neutralization from the registry should suffice)."
fi
exit 0
