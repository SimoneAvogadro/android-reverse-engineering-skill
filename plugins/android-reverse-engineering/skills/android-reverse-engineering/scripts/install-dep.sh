#!/usr/bin/env bash
# install-dep.sh — Install a single dependency for Android reverse engineering
# Usage: install-dep.sh <dependency> [--accept-android-sdk-license]
# Run it as your own user, not with sudo: per-user tools go to ~/.local and
# system packages are installed through sudo by the script itself.
# Dependencies: java, jadx, vineflower, dex2jar, apktool, apkeditor, build-tools, adb, smali, apksigner, zip
# Compound: neutralize-all (java + apktool + apkeditor + build-tools + zip)
#
# Exit codes:
#   0 — installed successfully
#   1 — installation failed
#   2 — requires manual action (e.g. sudo needed but not available)
set -euo pipefail

# Ensure user-local bin is in PATH (previous installs may have placed tools there)
if [[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

usage() {
  cat <<EOF
Usage: install-dep.sh <dependency> [--accept-android-sdk-license]

Install a dependency required for Android reverse engineering.

Available dependencies:
  java         Java JDK 17+
  jadx         jadx decompiler
  vineflower   Vineflower (Fernflower fork) decompiler
  dex2jar      DEX to JAR converter
  apktool      Android resource decoder
  apkeditor    APKEditor (merges XAPK/APKM/APKS split APKs into one APK)
  build-tools  Android SDK Build-Tools $BUILD_TOOLS_VERSION (zipalign -P 16, apksigner, aapt2);
               needs --accept-android-sdk-license (or ACCEPT_ANDROID_SDK_LICENSE=1)
  adb          Android Debug Bridge
  smali        Smali/baksmali assembler/disassembler
  apksigner    Android APK signing tool
  zip          zip archiver (needed for XAPK rebuild)

Compound targets:
  neutralize-all   Install all SDK neutralizer deps (java, apktool, apkeditor, build-tools, zip)

The script detects your OS and package manager, then:
  - Installs directly if possible (brew, or user-local install)
  - Uses sudo if available and needed
  - Prints manual instructions if neither option works
EOF
  exit 0
}

# Android SDK Build-Tools — pinned official package from dl.google.com.
# SHA-256 computed from the archives whose SHA-1 matches Google's repository XML
# (https://dl.google.com/android/repository/repository2-3.xml):
#   linux  b0b6376977657e8ad9b969bacf4093601da2c6fb
#   macosx 199ae0047ee61e842f8ee0c6d3918e44fb9a1f83
# Keep in sync with install-dep.ps1 (windows archive).
BUILD_TOOLS_VERSION="36.0.0"
BUILD_TOOLS_ARCHIVE_TAG="r36"
BUILD_TOOLS_SHA256_LINUX="5d9ac77fb6ff43d9da518a337b4fcf8f9097113df531d99ccefe80ef7ce8250b"
BUILD_TOOLS_SHA256_MACOSX="04e7f3a72044de4926fa038fa0e251a37bba1e1c3fb8beab6f8401bfd9eb4bf3"
ANDROID_SDK_LICENSE_URL="https://developer.android.com/studio/terms"

ACCEPT_ANDROID_SDK_LICENSE="${ACCEPT_ANDROID_SDK_LICENSE:-0}"
DEP=""
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage ;;
    --accept-android-sdk-license) ACCEPT_ANDROID_SDK_LICENSE=1 ;;
    -*) echo "Error: Unknown option $arg" >&2; exit 1 ;;
    *) DEP="$arg" ;;
  esac
done
if [[ -z "$DEP" ]]; then
  usage
fi

# Per-user tools go to ~/.local of the user running this script. Under sudo they
# would land in root's home, so refuse: system packages (Java, zip, ...) are
# installed through sudo by this script itself, or it prints the exact
# 'sudo apt-get install ...' command and exits 2.
case "$DEP" in
  jadx|vineflower|fernflower|dex2jar|apktool|apkeditor|build-tools|buildtools|zipalign|smali|baksmali|apksigner|neutralize-all)
    if [[ "$(id -u)" -eq 0 ]] && [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
      echo "Error: do not run 'install-dep.sh $DEP' with sudo." >&2
      echo "  It installs per-user tools into ~/.local, which would end up in root's home" >&2
      echo "  instead of $SUDO_USER's. Run it as $SUDO_USER: it calls sudo itself for system" >&2
      echo "  packages, or prints the exact sudo command to run first and exits 2." >&2
      exit 1
    fi ;;
esac

# --- Detect environment ---
OS="unknown"
PKG_MANAGER="none"
HAS_SUDO=false
ARCH=$(uname -m)

case "$(uname -s)" in
  Linux)  OS="linux" ;;
  Darwin) OS="macos" ;;
esac

# Detect package manager
if command -v brew &>/dev/null; then
  PKG_MANAGER="brew"
elif command -v apt-get &>/dev/null; then
  PKG_MANAGER="apt"
elif command -v dnf &>/dev/null; then
  PKG_MANAGER="dnf"
elif command -v pacman &>/dev/null; then
  PKG_MANAGER="pacman"
fi

# Check sudo availability — must actually work, not just exist
if command -v sudo &>/dev/null; then
  if sudo -n true 2>/dev/null; then
    # Passwordless sudo works (NOPASSWD or cached credentials)
    HAS_SUDO=true
  elif [[ -t 0 ]]; then
    # stdin is a terminal — sudo can prompt for password interactively
    HAS_SUDO=true
  else
    # sudo exists but can't authenticate (no TTY, no cached credentials)
    # This happens inside Claude Code, CI, cron, pipes, etc.
    HAS_SUDO=false
  fi
fi

info()  { echo "[INFO] $*"; }
ok()    { echo "[OK] $*"; }
fail()  { echo "[FAIL] $*" >&2; }
manual() {
  echo "" >&2
  echo "[MANUAL ACTION REQUIRED]" >&2
  echo "  Cannot install automatically (no interactive terminal for sudo)." >&2
  echo "  Please run the following command in a terminal, then retry:" >&2
  echo "" >&2
  echo "    $*" >&2
  echo "" >&2
  exit 2
}

# --- Helper: install via system package manager (needs sudo on Linux) ---
pkg_install() {
  local pkg="$1"
  case "$PKG_MANAGER" in
    brew)
      info "Installing $pkg via Homebrew..."
      brew install "$pkg"
      ;;
    apt)
      if [[ "$HAS_SUDO" == true ]]; then
        info "Installing $pkg via apt..."
        sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg"
      else
        manual "sudo apt-get update && sudo apt-get install -y $pkg"
      fi
      ;;
    dnf)
      if [[ "$HAS_SUDO" == true ]]; then
        info "Installing $pkg via dnf..."
        sudo dnf install -y "$pkg"
      else
        manual "sudo dnf install -y $pkg"
      fi
      ;;
    pacman)
      if [[ "$HAS_SUDO" == true ]]; then
        info "Installing $pkg via pacman..."
        sudo pacman -S --noconfirm "$pkg"
      else
        manual "sudo pacman -S $pkg"
      fi
      ;;
    *)
      manual "No supported package manager found. Install $pkg manually."
      ;;
  esac
}

# --- Helper: check that a tool needed by this script is available ---
require_tool() {
  local tool="$1"
  if command -v "$tool" &>/dev/null; then
    return 0
  fi

  # Build the install command for the user
  local install_cmd=""
  case "$PKG_MANAGER" in
    brew)   install_cmd="brew install $tool" ;;
    apt)    install_cmd="sudo apt-get update && sudo apt-get install -y $tool" ;;
    dnf)    install_cmd="sudo dnf install -y $tool" ;;
    pacman) install_cmd="sudo pacman -S $tool" ;;
  esac

  echo "" >&2
  echo "[MISSING PREREQUISITE] '$tool' is required by install-dep.sh but is not installed." >&2
  if [[ -n "$install_cmd" ]]; then
    echo "  Please run the following command in a terminal first, then retry:" >&2
    echo "" >&2
    echo "    $install_cmd" >&2
  else
    echo "  Please install '$tool' using your system package manager, then retry." >&2
  fi
  echo "" >&2
  exit 2
}

# --- Helper: download a file ---
download() {
  local url="$1" dest="$2"
  if command -v curl &>/dev/null; then
    curl -fsSL -o "$dest" "$url"
  elif command -v wget &>/dev/null; then
    wget -q -O "$dest" "$url"
  else
    require_tool "curl"  # exits with instructions
  fi
}

# --- Helper: SHA-256 of a file (GNU coreutils, macOS shasum, or openssl) ---
sha256_of() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v openssl &>/dev/null; then
    openssl dgst -sha256 "$1" | awk '{print $NF}'
  else
    return 1
  fi
}

require_sha256_tool() {
  if ! command -v sha256sum &>/dev/null && ! command -v shasum &>/dev/null && ! command -v openssl &>/dev/null; then
    fail "No SHA-256 tool found (sha256sum, shasum or openssl) — refusing to install an unverified download."
    exit 1
  fi
}

# --- Helper: download <url> <dest> <sha256>, 3 attempts; returns 1 if never verified ---
download_verified() {
  local url="$1" dest="$2" want="$3" attempt=1 got=""
  while true; do
    if download "$url" "$dest"; then
      got=$(sha256_of "$dest" || true)
      if [[ "$got" == "$want" ]]; then
        return 0
      fi
      fail "SHA-256 mismatch for $(basename "$url") (expected $want, got ${got:-none})"
    fi
    if (( attempt >= 3 )); then
      rm -f "$dest"
      return 1
    fi
    attempt=$((attempt + 1))
    info "Retrying download (attempt $attempt/3)..."
    sleep 2
  done
}

# --- Helper: get latest GitHub release tag ---
gh_latest_tag() {
  local repo="$1"
  local url="https://api.github.com/repos/$repo/releases/latest"
  if command -v curl &>/dev/null; then
    curl -fsSL "$url" | grep '"tag_name"' | sed -n 1p | sed 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/'
  elif command -v wget &>/dev/null; then
    wget -q -O - "$url" | grep '"tag_name"' | sed -n 1p | sed 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/'
  fi
}

# --- Helper: add a line to shell profile if not already present ---
add_to_profile() {
  local line="$1"
  local profile=""
  if [[ -f "$HOME/.zshrc" ]]; then
    profile="$HOME/.zshrc"
  elif [[ -f "$HOME/.bashrc" ]]; then
    profile="$HOME/.bashrc"
  elif [[ -f "$HOME/.profile" ]]; then
    profile="$HOME/.profile"
  fi

  if [[ -n "$profile" ]]; then
    if ! grep -qF "$line" "$profile" 2>/dev/null; then
      echo "$line" >> "$profile"
      info "Added to $profile: $line"
      info "Run 'source $profile' or start a new shell to apply."
    fi
  else
    info "Add this to your shell profile: $line"
  fi
}

# =====================================================================
# Dependency installers
# =====================================================================

install_java() {
  if command -v java &>/dev/null; then
    local ver
    ver=$(java -version 2>&1 | sed -n 1p | sed -n 's/.*"\([0-9]*\)\..*/\1/p')
    if [[ -n "$ver" ]] && (( ver >= 17 )); then
      ok "Java $ver already installed"
      return 0
    fi
  fi

  info "Installing Java JDK 17+..."
  case "$PKG_MANAGER" in
    brew)    brew install openjdk@17 ;;
    apt)     pkg_install "openjdk-17-jdk" ;;
    dnf)     pkg_install "java-17-openjdk-devel" ;;
    pacman)  pkg_install "jdk17-openjdk" ;;
    *)       manual "Install Java JDK 17+ from https://adoptium.net/" ;;
  esac

  # Verify
  if command -v java &>/dev/null; then
    ok "Java installed: $(java -version 2>&1 | sed -n 1p)"
  else
    fail "Java installation may require PATH update."
    if [[ "$PKG_MANAGER" == "brew" ]]; then
      add_to_profile 'export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"'
    fi
    exit 1
  fi
}

install_jadx() {
  if command -v jadx &>/dev/null; then
    ok "jadx already installed: $(jadx --version 2>/dev/null || echo 'unknown')"
    return 0
  fi

  # Check prerequisites for download-based install
  require_tool "unzip"

  # Try brew first (cleanest)
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    info "Installing jadx via Homebrew..."
    brew install jadx
    ok "jadx installed via Homebrew"
    return 0
  fi

  # User-local install from GitHub releases (no sudo needed)
  info "Installing jadx from GitHub releases..."
  local tag
  tag=$(gh_latest_tag "skylot/jadx")
  if [[ -z "$tag" ]]; then
    fail "Could not determine latest jadx version."
    manual "Download from https://github.com/skylot/jadx/releases/latest"
  fi

  local version="${tag#v}"
  local url="https://github.com/skylot/jadx/releases/download/${tag}/jadx-${version}.zip"
  local tmp_zip
  tmp_zip=$(mktemp /tmp/jadx-XXXXXX.zip)

  info "Downloading jadx $version..."
  download "$url" "$tmp_zip"

  local install_dir="$HOME/.local/share/jadx"
  rm -rf "$install_dir"
  mkdir -p "$install_dir"
  unzip -qo "$tmp_zip" -d "$install_dir"
  rm -f "$tmp_zip"
  chmod +x "$install_dir/bin/jadx" "$install_dir/bin/jadx-gui" 2>/dev/null || true

  # Add to PATH
  mkdir -p "$HOME/.local/bin"
  ln -sf "$install_dir/bin/jadx" "$HOME/.local/bin/jadx"
  ln -sf "$install_dir/bin/jadx-gui" "$HOME/.local/bin/jadx-gui"
  export PATH="$HOME/.local/bin:$PATH"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'

  if command -v jadx &>/dev/null; then
    ok "jadx $version installed to $install_dir"
  else
    ok "jadx $version installed to $install_dir"
    info "Run: export PATH=\"\$HOME/.local/bin:\$PATH\" to use it now"
  fi
}

install_vineflower() {
  # Check if already available
  if command -v vineflower &>/dev/null || command -v fernflower &>/dev/null; then
    ok "Vineflower/Fernflower CLI already installed"
    return 0
  fi
  for candidate in \
    "${FERNFLOWER_JAR_PATH:-}" \
    "$HOME/vineflower/vineflower.jar" \
    "$HOME/fernflower/fernflower.jar" \
    "$HOME/fernflower/build/libs/fernflower.jar" \
    "$HOME/vineflower/build/libs/vineflower.jar"; do
    if [[ -n "$candidate" ]] && [[ -f "$candidate" ]]; then
      ok "Vineflower/Fernflower JAR already exists: $candidate"
      return 0
    fi
  done

  # Try brew
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    info "Installing vineflower via Homebrew..."
    if brew install vineflower 2>/dev/null; then
      ok "Vineflower installed via Homebrew"
      return 0
    fi
    info "Homebrew formula not available, falling back to direct download."
  fi

  # Download JAR from GitHub releases (no sudo needed)
  info "Installing Vineflower from GitHub releases..."
  local tag
  tag=$(gh_latest_tag "Vineflower/vineflower")
  if [[ -z "$tag" ]]; then
    fail "Could not determine latest Vineflower version."
    manual "Download from https://github.com/Vineflower/vineflower/releases/latest"
  fi

  local version="${tag#v}"
  local url="https://github.com/Vineflower/vineflower/releases/download/${tag}/vineflower-${version}.jar"
  local install_dir="$HOME/.local/share/vineflower"
  mkdir -p "$install_dir"

  info "Downloading Vineflower $version..."
  download "$url" "$install_dir/vineflower.jar"

  # Create wrapper script
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/vineflower" <<'WRAPPER'
#!/usr/bin/env bash
exec java -jar "$HOME/.local/share/vineflower/vineflower.jar" "$@"
WRAPPER
  chmod +x "$HOME/.local/bin/vineflower"

  export PATH="$HOME/.local/bin:$PATH"
  export FERNFLOWER_JAR_PATH="$install_dir/vineflower.jar"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
  add_to_profile "export FERNFLOWER_JAR_PATH=\"$install_dir/vineflower.jar\""

  ok "Vineflower $version installed to $install_dir/vineflower.jar"
  info "FERNFLOWER_JAR_PATH set to $install_dir/vineflower.jar"
}

install_dex2jar() {
  if command -v d2j-dex2jar &>/dev/null || command -v d2j-dex2jar.sh &>/dev/null; then
    ok "dex2jar already installed"
    return 0
  fi

  # Check prerequisites for download-based install
  require_tool "unzip"

  # Try brew
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    info "Installing dex2jar via Homebrew..."
    if brew install dex2jar 2>/dev/null; then
      ok "dex2jar installed via Homebrew"
      return 0
    fi
    info "Homebrew formula not available, falling back to direct download."
  fi

  # Download from GitHub (no sudo needed)
  info "Installing dex2jar from GitHub releases..."
  local tag
  tag=$(gh_latest_tag "ThexXTURBOXx/dex2jar")
  if [[ -z "$tag" ]]; then
    # Fallback to a known maintained release if GitHub metadata is unavailable.
    tag="2.4.35"
  fi

  local version="${tag#v}"
  local url="https://github.com/ThexXTURBOXx/dex2jar/releases/download/${tag}/dex-tools-${version}.zip"
  local tmp_zip
  tmp_zip=$(mktemp /tmp/dex2jar-XXXXXX.zip)

  info "Downloading dex2jar $version..."
  if ! download "$url" "$tmp_zip"; then
    # Try alternate naming
    url="https://github.com/ThexXTURBOXx/dex2jar/releases/download/${tag}/dex-tools-v${version}.zip"
    download "$url" "$tmp_zip" || {
      fail "Download failed."
      manual "Download from https://github.com/ThexXTURBOXx/dex2jar/releases/latest"
    }
  fi

  local install_dir="$HOME/.local/share/dex2jar"
  rm -rf "$install_dir"
  mkdir -p "$install_dir"
  unzip -qo "$tmp_zip" -d "$install_dir"
  rm -f "$tmp_zip"

  # The zip may contain a top-level directory — find the actual bin location
  local bin_dir=""
  if [[ -f "$install_dir/d2j-dex2jar.sh" ]]; then
    bin_dir="$install_dir"
  else
    bin_dir=$(find "$install_dir" -name "d2j-dex2jar.sh" -exec dirname {} \; | sed -n 1p)
  fi

  if [[ -z "$bin_dir" ]]; then
    fail "Could not find d2j-dex2jar.sh in extracted archive."
    manual "Download and extract manually from https://github.com/ThexXTURBOXx/dex2jar/releases"
  fi

  chmod +x "$bin_dir"/*.sh 2>/dev/null || true

  mkdir -p "$HOME/.local/bin"
  for script in "$bin_dir"/d2j-*.sh; do
    local name
    name=$(basename "$script" .sh)
    ln -sf "$script" "$HOME/.local/bin/$name"
  done

  export PATH="$HOME/.local/bin:$PATH"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'

  ok "dex2jar $version installed to $install_dir"
}

install_apktool() {
  # Minimum version required by sdk-neutralizer (modern APKs, targetSdk 34+)
  local MIN_MAJOR=2 MIN_MINOR=9 MIN_PATCH=0
  local need_install=false

  if command -v apktool &>/dev/null; then
    local ver_raw
    ver_raw=$(apktool --version 2>/dev/null | sed -n 1p | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sed -n 1p)
    if [[ -n "$ver_raw" ]]; then
      local cur_major cur_minor cur_patch
      IFS='.' read -r cur_major cur_minor cur_patch <<< "$ver_raw"
      cur_major=${cur_major:-0}; cur_minor=${cur_minor:-0}; cur_patch=${cur_patch:-0}

      if (( cur_major > MIN_MAJOR )) || \
         (( cur_major == MIN_MAJOR && cur_minor > MIN_MINOR )) || \
         (( cur_major == MIN_MAJOR && cur_minor == MIN_MINOR && cur_patch >= MIN_PATCH )); then
        ok "apktool $ver_raw already installed (>= ${MIN_MAJOR}.${MIN_MINOR}.${MIN_PATCH})"
        return 0
      else
        info "apktool $ver_raw found but >= ${MIN_MAJOR}.${MIN_MINOR}.${MIN_PATCH} is required — upgrading..."
        need_install=true
      fi
    else
      ok "apktool detected (could not parse version — assuming compatible)"
      return 0
    fi
  else
    need_install=true
  fi

  if [[ "$need_install" == true ]]; then
    # User-local install from GitHub (no sudo needed, takes PATH precedence)
    info "Installing apktool from GitHub releases to ~/.local/bin..."
    local tag
    tag=$(gh_latest_tag "iBotPeaches/Apktool")
    if [[ -z "$tag" ]]; then
      tag="v2.10.0"  # fallback known-good version
      info "Could not fetch latest tag, using fallback: $tag"
    fi

    local version="${tag#v}"
    local install_dir="$HOME/.local/share/apktool"
    mkdir -p "$install_dir" "$HOME/.local/bin"

    info "Downloading apktool $version..."
    download "https://bitbucket.org/iBotPeaches/apktool/downloads/apktool_${version}.jar" \
      "$install_dir/apktool.jar" 2>/dev/null || \
    download "https://github.com/iBotPeaches/Apktool/releases/download/${tag}/apktool_${version}.jar" \
      "$install_dir/apktool.jar"

    if [[ ! -f "$install_dir/apktool.jar" ]]; then
      fail "Failed to download apktool $version."
      manual "Download from https://apktool.org/docs/install"
    fi

    # Create wrapper script
    cat > "$HOME/.local/bin/apktool" <<'WRAPPER'
#!/usr/bin/env bash
exec java -jar "$HOME/.local/share/apktool/apktool.jar" "$@"
WRAPPER
    chmod +x "$HOME/.local/bin/apktool"

    export PATH="$HOME/.local/bin:$PATH"
    add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'

    # Verify
    local installed_ver
    installed_ver=$("$HOME/.local/bin/apktool" --version 2>/dev/null | sed -n 1p | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sed -n 1p)
    if [[ -n "$installed_ver" ]]; then
      ok "apktool $installed_ver installed to $install_dir"
    else
      fail "apktool installation may have failed."
      exit 1
    fi
  fi
}

# APKEditor (REAndroid, Apache-2.0) — pinned release, verified by SHA-256.
# Bump version and hash together (hash = the release asset's sha256 digest).
APKEDITOR_VERSION="1.4.9"
APKEDITOR_SHA256="a9cd40df818845456be6d696de6110c89edf4b0a0580cb83438ed6b25a366e67"

install_apkeditor() {
  if [[ -n "${APKEDITOR_JAR:-}" ]]; then
    if [[ -f "$APKEDITOR_JAR" ]]; then
      ok "APKEditor JAR provided via APKEDITOR_JAR: $APKEDITOR_JAR"
      return 0
    fi
    fail "APKEDITOR_JAR is set but the file does not exist: $APKEDITOR_JAR"
    exit 1
  fi

  local install_dir="$HOME/.local/share/apkeditor"
  local jar="$install_dir/APKEditor.jar"
  local url="https://github.com/REAndroid/APKEditor/releases/download/V${APKEDITOR_VERSION}/APKEditor-${APKEDITOR_VERSION}.jar"
  local actual=""

  if [[ -f "$jar" ]]; then
    actual=$(sha256_of "$jar" || true)
  fi
  if [[ -n "$actual" ]] && [[ "$actual" == "$APKEDITOR_SHA256" ]]; then
    ok "APKEditor $APKEDITOR_VERSION already installed: $jar"
  else
    require_sha256_tool
    info "Installing APKEditor $APKEDITOR_VERSION from GitHub releases..."
    mkdir -p "$install_dir"
    local tmp_jar
    tmp_jar=$(mktemp "${TMPDIR:-/tmp}/apkeditor-XXXXXX")
    local attempt=1
    while true; do
      if download "$url" "$tmp_jar"; then
        actual=$(sha256_of "$tmp_jar" || true)
        if [[ -z "$actual" ]]; then
          rm -f "$tmp_jar"
          fail "No SHA-256 tool found (sha256sum, shasum or openssl) — refusing to install an unverified JAR."
          exit 1
        fi
        if [[ "$actual" == "$APKEDITOR_SHA256" ]]; then
          break
        fi
        fail "SHA-256 mismatch for APKEditor-${APKEDITOR_VERSION}.jar (expected $APKEDITOR_SHA256, got $actual)"
      fi
      if (( attempt >= 3 )); then
        rm -f "$tmp_jar"
        fail "Could not download a verified APKEditor $APKEDITOR_VERSION JAR."
        echo "  Manually download: $url" >&2
        echo "  check that its SHA-256 is $APKEDITOR_SHA256," >&2
        echo "  then save it as $jar (or point APKEDITOR_JAR at it)." >&2
        exit 2
      fi
      attempt=$((attempt + 1))
      info "Retrying download (attempt $attempt/3)..."
      sleep 2
    done
    mv -f "$tmp_jar" "$jar"
    chmod 644 "$jar"
    ok "APKEditor $APKEDITOR_VERSION installed to $jar (SHA-256 verified)"
  fi

  # Launcher (honours APKEDITOR_JAR at run time)
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/apkeditor" <<'WRAPPER'
#!/usr/bin/env bash
exec java -jar "${APKEDITOR_JAR:-$HOME/.local/share/apkeditor/APKEditor.jar}" "$@"
WRAPPER
  chmod +x "$HOME/.local/bin/apkeditor"

  export PATH="$HOME/.local/bin:$PATH"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
}

# Latest build-tools version directory under an SDK root (numeric sort, BSD-safe)
latest_build_tools_dir() {
  local sdk="$1" v
  [[ -n "$sdk" ]] && [[ -d "$sdk/build-tools" ]] || return 1
  v=$(ls -1 "$sdk/build-tools" 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
  [[ -n "$v" ]] && [[ -d "$sdk/build-tools/$v" ]] || return 1
  echo "$sdk/build-tools/$v"
}

zipalign_has_P() {
  local usage_text
  usage_text=$("$1" 2>&1 || true)
  case "$usage_text" in *"-P <pagesize"*) return 0 ;; esac
  return 1
}

print_android_sdk_license_notice() {
  cat >&2 <<EOF

[LICENSE] Android SDK Build-Tools $BUILD_TOOLS_VERSION are distributed by Google under the
          Android Software Development Kit License Agreement:
            $ANDROID_SDK_LICENSE_URL
          Read it before installing. To accept it and install, re-run with
            install-dep.sh build-tools --accept-android-sdk-license
          (or set ACCEPT_ANDROID_SDK_LICENSE=1).

EOF
}

install_build_tools() {
  # Already satisfied: an SDK build-tools dir with a -P capable zipalign and apksigner
  local sdk bt
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "$HOME/.local/share/android-sdk"; do
    bt=$(latest_build_tools_dir "$sdk" || true)
    if [[ -n "$bt" ]] && [[ -x "$bt/zipalign" ]] && [[ -x "$bt/apksigner" ]] && zipalign_has_P "$bt/zipalign"; then
      ok "Android build-tools with zipalign -P and apksigner already installed: $bt"
      return 0
    fi
  done

  print_android_sdk_license_notice
  if [[ "$ACCEPT_ANDROID_SDK_LICENSE" != "1" ]]; then
    fail "Android SDK license not accepted — build-tools not installed."
    return 2
  fi
  info "Android SDK license accepted via --accept-android-sdk-license / ACCEPT_ANDROID_SDK_LICENSE=1"

  # Prefer sdkmanager when an SDK root is configured
  local sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  local sdkm=""
  if [[ -n "$sdk_root" ]]; then
    if [[ -x "$sdk_root/cmdline-tools/latest/bin/sdkmanager" ]]; then
      sdkm="$sdk_root/cmdline-tools/latest/bin/sdkmanager"
    elif command -v sdkmanager &>/dev/null; then
      sdkm=$(command -v sdkmanager)
    fi
  fi
  if [[ -n "$sdkm" ]]; then
    info "Installing build-tools;$BUILD_TOOLS_VERSION with sdkmanager into $sdk_root..."
    if { yes 2>/dev/null || true; } | "$sdkm" --sdk_root="$sdk_root" --install "build-tools;$BUILD_TOOLS_VERSION"; then
      if [[ -x "$sdk_root/build-tools/$BUILD_TOOLS_VERSION/zipalign" ]]; then
        ok "build-tools $BUILD_TOOLS_VERSION installed with sdkmanager: $sdk_root/build-tools/$BUILD_TOOLS_VERSION"
        return 0
      fi
    fi
    info "sdkmanager did not install build-tools — falling back to direct download."
  fi

  local host sha
  case "$OS" in
    linux) host="linux"; sha="$BUILD_TOOLS_SHA256_LINUX" ;;
    macos) host="macosx"; sha="$BUILD_TOOLS_SHA256_MACOSX" ;;
    *) manual "Install Android SDK Build-Tools $BUILD_TOOLS_VERSION with Android Studio's SDK Manager." ;;
  esac
  require_tool "unzip"
  require_sha256_tool

  local url="https://dl.google.com/android/repository/build-tools_${BUILD_TOOLS_ARCHIVE_TAG}_${host}.zip"
  local tmp_dir
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/build-tools-XXXXXX")
  info "Downloading $url..."
  if ! download_verified "$url" "$tmp_dir/bt.zip" "$sha"; then
    rm -rf "$tmp_dir"
    fail "Could not download a verified build-tools $BUILD_TOOLS_VERSION archive."
    echo "  Install it with Android Studio's SDK Manager, or download $url" >&2
    echo "  (SHA-256 $sha) and unzip it to ~/.local/share/android-sdk/build-tools/$BUILD_TOOLS_VERSION" >&2
    exit 2
  fi
  unzip -q "$tmp_dir/bt.zip" -d "$tmp_dir/x"
  local top
  top=$(ls -1 "$tmp_dir/x" | sed -n 1p)
  if [[ -z "$top" ]] || [[ ! -f "$tmp_dir/x/$top/zipalign" ]]; then
    rm -rf "$tmp_dir"
    fail "Unexpected build-tools archive layout."
    exit 1
  fi
  local dest="$HOME/.local/share/android-sdk/build-tools/$BUILD_TOOLS_VERSION"
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  mv "$tmp_dir/x/$top" "$dest"
  rm -rf "$tmp_dir"

  # Launchers (wrappers keep the tools next to their lib/ and lib64/ directories)
  mkdir -p "$HOME/.local/bin"
  local t
  for t in zipalign apksigner aapt2; do
    printf '#!/usr/bin/env bash\nexec "%s/%s" "$@"\n' "$dest" "$t" > "$HOME/.local/bin/$t"
    chmod +x "$HOME/.local/bin/$t"
  done
  export PATH="$HOME/.local/bin:$PATH"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'

  if zipalign_has_P "$dest/zipalign"; then
    ok "Android build-tools $BUILD_TOOLS_VERSION installed to $dest (SHA-256 verified)"
  else
    fail "build-tools installed to $dest but its zipalign does not run on this system."
    exit 1
  fi
}

install_adb() {
  if command -v adb &>/dev/null; then
    ok "adb already installed"
    return 0
  fi

  case "$PKG_MANAGER" in
    brew)    info "Installing adb via Homebrew..."; brew install android-platform-tools ;;
    apt)     pkg_install "adb" ;;
    dnf)     pkg_install "android-tools" ;;
    pacman)  pkg_install "android-tools" ;;
    *)       manual "Install Android SDK Platform Tools from https://developer.android.com/tools/releases/platform-tools" ;;
  esac

  if command -v adb &>/dev/null; then
    ok "adb installed"
  else
    fail "adb installation may have failed."
    exit 1
  fi
}

install_smali() {
  if command -v smali &>/dev/null || command -v baksmali &>/dev/null; then
    ok "smali/baksmali already installed"
    return 0
  fi

  # Check prerequisites for download-based install
  require_tool "unzip"

  # Try brew first
  if [[ "$PKG_MANAGER" == "brew" ]]; then
    info "Installing smali via Homebrew..."
    if brew install smali 2>/dev/null; then
      ok "smali installed via Homebrew"
      return 0
    fi
    info "Homebrew formula not available, falling back to direct download."
  fi

  # Download from GitHub releases (no sudo needed)
  info "Installing smali from GitHub releases..."
  local tag
  tag=$(gh_latest_tag "google/smali")
  if [[ -z "$tag" ]]; then
    tag="v3.0.8"
  fi

  local version="${tag#v}"
  local url="https://github.com/google/smali/releases/download/${tag}/smali-${version}.zip"
  local tmp_zip
  tmp_zip=$(mktemp /tmp/smali-XXXXXX.zip)

  info "Downloading smali $version..."
  if ! download "$url" "$tmp_zip"; then
    # Try alternate naming with baksmali
    url="https://github.com/google/smali/releases/download/${tag}/smali-${version}-fat.jar"
    local install_dir="$HOME/.local/share/smali"
    mkdir -p "$install_dir"
    if download "$url" "$install_dir/smali.jar"; then
      # Single JAR install — create wrapper
      mkdir -p "$HOME/.local/bin"
      cat > "$HOME/.local/bin/smali" <<'WRAPPER'
#!/usr/bin/env bash
exec java -jar "$HOME/.local/share/smali/smali.jar" assemble "$@"
WRAPPER
      cat > "$HOME/.local/bin/baksmali" <<'WRAPPER'
#!/usr/bin/env bash
exec java -jar "$HOME/.local/share/smali/smali.jar" disassemble "$@"
WRAPPER
      chmod +x "$HOME/.local/bin/smali" "$HOME/.local/bin/baksmali"
      export PATH="$HOME/.local/bin:$PATH"
      add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
      ok "smali $version installed to $install_dir"
      rm -f "$tmp_zip"
      return 0
    fi
    fail "Download failed."
    rm -f "$tmp_zip"
    manual "Download from https://github.com/google/smali/releases/latest"
  fi

  local install_dir="$HOME/.local/share/smali"
  rm -rf "$install_dir"
  mkdir -p "$install_dir"
  unzip -qo "$tmp_zip" -d "$install_dir"
  rm -f "$tmp_zip"

  # Create wrapper scripts
  mkdir -p "$HOME/.local/bin"

  # Look for the smali JAR
  local smali_jar
  smali_jar=$(find "$install_dir" -name "smali*.jar" -not -name "*baksmali*" | sed -n 1p)
  local baksmali_jar
  baksmali_jar=$(find "$install_dir" -name "baksmali*.jar" | sed -n 1p)

  if [[ -n "$smali_jar" ]]; then
    cat > "$HOME/.local/bin/smali" <<WRAPPER
#!/usr/bin/env bash
exec java -jar "$smali_jar" "\$@"
WRAPPER
    chmod +x "$HOME/.local/bin/smali"
  fi

  if [[ -n "$baksmali_jar" ]]; then
    cat > "$HOME/.local/bin/baksmali" <<WRAPPER
#!/usr/bin/env bash
exec java -jar "$baksmali_jar" "\$@"
WRAPPER
    chmod +x "$HOME/.local/bin/baksmali"
  fi

  # Also look for shell scripts
  for script in "$install_dir"/bin/smali "$install_dir"/bin/baksmali "$install_dir"/smali "$install_dir"/baksmali; do
    if [[ -x "$script" ]]; then
      local name
      name=$(basename "$script")
      ln -sf "$script" "$HOME/.local/bin/$name"
    fi
  done

  export PATH="$HOME/.local/bin:$PATH"
  add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'

  ok "smali $version installed to $install_dir"
}

install_apksigner() {
  if command -v apksigner &>/dev/null; then
    ok "apksigner already installed"
    return 0
  fi

  # Check if Android SDK build-tools has apksigner
  if [[ -n "${ANDROID_HOME:-}" ]]; then
    local bt_dir="$ANDROID_HOME/build-tools"
    if [[ -d "$bt_dir" ]]; then
      local latest_bt
      latest_bt=$(ls -1 "$bt_dir" 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
      if [[ -n "$latest_bt" ]] && [[ -f "$bt_dir/$latest_bt/apksigner" ]]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$bt_dir/$latest_bt/apksigner" "$HOME/.local/bin/apksigner"
        export PATH="$HOME/.local/bin:$PATH"
        add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
        ok "apksigner linked from Android SDK build-tools ($latest_bt)"
        return 0
      fi
    fi
  fi

  # Also check ANDROID_SDK_ROOT
  if [[ -n "${ANDROID_SDK_ROOT:-}" ]] && [[ "$ANDROID_SDK_ROOT" != "${ANDROID_HOME:-}" ]]; then
    local bt_dir="$ANDROID_SDK_ROOT/build-tools"
    if [[ -d "$bt_dir" ]]; then
      local latest_bt
      latest_bt=$(ls -1 "$bt_dir" 2>/dev/null | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
      if [[ -n "$latest_bt" ]] && [[ -f "$bt_dir/$latest_bt/apksigner" ]]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$bt_dir/$latest_bt/apksigner" "$HOME/.local/bin/apksigner"
        export PATH="$HOME/.local/bin:$PATH"
        add_to_profile 'export PATH="$HOME/.local/bin:$PATH"'
        ok "apksigner linked from Android SDK build-tools ($latest_bt)"
        return 0
      fi
    fi
  fi

  # Try package manager
  case "$PKG_MANAGER" in
    brew)
      info "Installing apksigner via Homebrew..."
      # apksigner comes with android-sdk or android-build-tools
      if brew install --cask android-commandlinetools 2>/dev/null; then
        ok "Android command-line tools installed (includes apksigner)"
        info "Run: sdkmanager --install 'build-tools;34.0.0' to get apksigner"
        return 0
      fi
      ;;
    apt)
      # On Debian/Ubuntu, apksigner is in the apksigner package
      pkg_install "apksigner"
      if command -v apksigner &>/dev/null; then
        ok "apksigner installed via apt"
        return 0
      fi
      ;;
    dnf|pacman)
      # Typically part of android-tools or SDK
      ;;
  esac

  # Fallback: check if jarsigner is available as alternative
  if command -v jarsigner &>/dev/null; then
    info "apksigner not found, but jarsigner is available as a fallback."
    info "For best results, install Android SDK build-tools."
    manual "Install Android SDK build-tools: sdkmanager --install 'build-tools;34.0.0'"
  fi

  manual "Install Android SDK build-tools or run: sudo apt install apksigner (Debian/Ubuntu)"
}

install_zip() {
  if command -v zip &>/dev/null; then
    ok "zip already installed"
    return 0
  fi

  info "Installing zip..."
  case "$PKG_MANAGER" in
    brew)    brew install zip ;;
    apt)     pkg_install "zip" ;;
    dnf)     pkg_install "zip" ;;
    pacman)  pkg_install "zip" ;;
    *)       manual "Install zip using your system package manager." ;;
  esac

  if command -v zip &>/dev/null; then
    ok "zip installed"
  else
    fail "zip installation may have failed."
    exit 1
  fi
}

install_neutralize_all() {
  echo "=== Installing all SDK Neutralizer dependencies ==="
  echo
  local failed=() needs_license=false rc
  for dep_fn in install_java install_apktool install_apkeditor install_build_tools install_zip; do
    dep_name="${dep_fn#install_}"
    info "--- $dep_name ---"
    rc=0
    $dep_fn || rc=$?
    if [[ $rc -ne 0 ]]; then
      failed+=("$dep_name")
      if [[ "$dep_fn" == "install_build_tools" ]] && [[ $rc -eq 2 ]]; then needs_license=true; fi
    fi
    echo
  done

  if [[ ${#failed[@]} -gt 0 ]]; then
    fail "Failed to install: ${failed[*]}"
    if [[ "$needs_license" == true ]] && [[ ${#failed[@]} -eq 1 ]]; then
      exit 2
    fi
    exit 1
  fi
  ok "All SDK Neutralizer dependencies installed."
}

# =====================================================================
# Dispatch
# =====================================================================

case "$DEP" in
  java)        install_java ;;
  jadx)        install_jadx ;;
  vineflower|fernflower)  install_vineflower ;;
  dex2jar)     install_dex2jar ;;
  apktool)     install_apktool ;;
  apkeditor)   install_apkeditor ;;
  build-tools|buildtools|zipalign)
    rc=0; install_build_tools || rc=$?
    exit $rc ;;
  adb)         install_adb ;;
  smali|baksmali)  install_smali ;;
  apksigner)   install_apksigner ;;
  zip)         install_zip ;;
  neutralize-all)  install_neutralize_all ;;
  *)
    echo "Error: Unknown dependency '$DEP'" >&2
    echo "Available: java, jadx, vineflower, dex2jar, apktool, apkeditor, build-tools, adb, smali, apksigner, zip" >&2
    echo "Compound: neutralize-all" >&2
    exit 1
    ;;
esac
