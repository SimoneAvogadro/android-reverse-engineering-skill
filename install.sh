#!/usr/bin/env bash
# install.sh — Universal installer for reverse engineering skills
# Installs agent-specific instruction files for any supported AI coding agent.
#
# Usage:
#   ./install.sh                              # Interactive mode
#   ./install.sh --agent cursor               # Install for Cursor
#   ./install.sh --agent all                  # Install for all agents
#   ./install.sh --agent copilot --target ~/my-project
#   ./install.sh --list                       # List available agents
#   ./install.sh --check-deps                 # Run dependency check only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT=""
TARGET=""
LIST=false
CHECK_DEPS=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent|-a)   AGENT="${2,,}"; shift 2 ;;
        --target|-t)  TARGET="$2"; shift 2 ;;
        --list|-l)    LIST=true; shift ;;
        --check-deps) CHECK_DEPS=true; shift ;;
        --help|-h)
            cat <<'EOF'
Reverse Engineering Skills — Universal Installer

Usage:
  ./install.sh                              Interactive mode (choose agent)
  ./install.sh --agent <agent>              Install for a specific agent
  ./install.sh --agent all                  Install for all agents
  ./install.sh --agent <agent> --target <dir>  Install into another project
  ./install.sh --list                       List supported agents
  ./install.sh --check-deps                 Run dependency check only

Agents:
  claude    — Claude Code (.claude-plugin/)
  codex     — OpenAI Codex (AGENTS.md)
  opencode  — OpenCode (AGENTS.md)
  cursor    — Cursor IDE (.cursor/rules/*.mdc)
  copilot   — GitHub Copilot (.github/instructions/)
  cline     — Cline (.clinerules/)
  windsurf  — Windsurf (.windsurf/rules/)
  roo       — Roo Code (.roo/rules/)
  aider     — Aider (.aider.conf.yml)
  all       — Install for all agents at once
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run: ./install.sh --help"
            exit 1
            ;;
    esac
done

VALID_AGENTS=(claude codex opencode cursor copilot cline windsurf roo aider)

# --- List ---
if $LIST; then
    echo "Supported AI Coding Agents:"
    echo ""
    echo "  claude       Claude Code        -> .claude-plugin/"
    echo "  codex        OpenAI Codex       -> AGENTS.md"
    echo "  opencode     OpenCode           -> AGENTS.md"
    echo "  cursor       Cursor IDE         -> .cursor/rules/*.mdc"
    echo "  copilot      GitHub Copilot     -> .github/instructions/"
    echo "  cline        Cline              -> .clinerules/"
    echo "  windsurf     Windsurf           -> .windsurf/rules/"
    echo "  roo          Roo Code           -> .roo/rules/"
    echo "  aider        Aider              -> .aider.conf.yml + AGENTS.md"
    echo ""
    echo "  all          All agents         -> installs everything"
    echo ""
    echo "Usage: ./install.sh --agent <agent>"
    exit 0
fi

# --- Check deps ---
if $CHECK_DEPS; then
    echo "=== Running Dependency Checks ==="
    echo ""
    echo "--- Windows Dependencies ---"
    WIN_SCRIPT="$SCRIPT_DIR/plugins/windows-reverse-engineering/skills/windows-reverse-engineering/scripts/check-deps.ps1"
    if command -v powershell &>/dev/null && [ -f "$WIN_SCRIPT" ]; then
        powershell -ExecutionPolicy Bypass -File "$WIN_SCRIPT" || true
    elif command -v pwsh &>/dev/null && [ -f "$WIN_SCRIPT" ]; then
        pwsh -ExecutionPolicy Bypass -File "$WIN_SCRIPT" || true
    else
        echo "PowerShell not available. Skipping Windows dependency check."
    fi
    echo ""
    echo "--- Android Dependencies ---"
    ANDROID_SCRIPT="$SCRIPT_DIR/plugins/android-reverse-engineering/skills/android-reverse-engineering/scripts/check-deps.sh"
    if [ -f "$ANDROID_SCRIPT" ]; then
        bash "$ANDROID_SCRIPT" || true
    else
        echo "Android check-deps.sh not found."
    fi
    exit 0
fi

# --- Interactive mode ---
if [ -z "$AGENT" ]; then
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║   Reverse Engineering Skills — Universal Installer  ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo "Which AI coding agent do you use?"
    echo ""
    for i in "${!VALID_AGENTS[@]}"; do
        printf "  [%d] %s\n" $((i+1)) "${VALID_AGENTS[$i]}"
    done
    printf "  [%d] all (install for all agents)\n" $(( ${#VALID_AGENTS[@]} + 1 ))
    echo ""
    read -rp "Enter number or agent name: " CHOICE

    if [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
        IDX=$((CHOICE - 1))
        if [ "$IDX" -ge 0 ] && [ "$IDX" -lt "${#VALID_AGENTS[@]}" ]; then
            AGENT="${VALID_AGENTS[$IDX]}"
        elif [ "$IDX" -eq "${#VALID_AGENTS[@]}" ]; then
            AGENT="all"
        else
            echo "Invalid choice."
            exit 1
        fi
    else
        AGENT="${CHOICE,,}"
    fi
fi

# --- Validate agent ---
if [ "$AGENT" != "all" ]; then
    FOUND=false
    for a in "${VALID_AGENTS[@]}"; do
        if [ "$a" = "$AGENT" ]; then
            FOUND=true
            break
        fi
    done
    if ! $FOUND; then
        echo "Unknown agent: $AGENT"
        echo "Run: ./install.sh --list"
        exit 1
    fi
fi

# --- Target directory ---
if [ -z "$TARGET" ]; then
    TARGET="$(pwd)"
fi

mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"

# --- Determine agents to install ---
if [ "$AGENT" = "all" ]; then
    INSTALL_AGENTS=("${VALID_AGENTS[@]}")
else
    INSTALL_AGENTS=("$AGENT")
fi

echo ""
echo "=== Installing Reverse Engineering Skills ==="
echo "Target: $TARGET"
echo "Agents: ${INSTALL_AGENTS[*]}"
echo ""

# --- Copy helper ---
copy_skill() {
    local rel_path="$1"
    local src="$SCRIPT_DIR/$rel_path"
    local dst="$TARGET/$rel_path"

    if [ ! -e "$src" ]; then
        echo "  [SKIP] $rel_path (source not found)"
        return 1
    fi

    mkdir -p "$(dirname "$dst")"

    if [ -d "$src" ]; then
        cp -r "$src" "$(dirname "$dst")/"
        echo "  [DIR]  $rel_path"
    else
        cp "$src" "$dst"
        echo "  [FILE] $rel_path"
    fi
    return 0
}

# --- Copy core plugins if installing to a different directory ---
IS_LOCAL=false
if [ "$TARGET" = "$SCRIPT_DIR" ]; then
    IS_LOCAL=true
fi

if ! $IS_LOCAL; then
    echo "Copying core plugins..."
    copy_skill "plugins" || true
fi

# --- Agent file map ---
COPIED_FILES=()

install_agent() {
    local agent_key="$1"

    case "$agent_key" in
        claude)
            echo ""
            echo "Installing for Claude Code..."
            copy_skill ".claude-plugin" || true
            ;;
        codex|opencode)
            echo ""
            echo "Installing for $([ "$agent_key" = "codex" ] && echo "OpenAI Codex" || echo "OpenCode")..."
            if [[ ! " ${COPIED_FILES[*]:-} " =~ " AGENTS.md " ]]; then
                copy_skill "AGENTS.md" || true
                COPIED_FILES+=("AGENTS.md")
            else
                echo "  [SKIP] AGENTS.md (already copied)"
            fi
            ;;
        cursor)
            echo ""
            echo "Installing for Cursor IDE..."
            copy_skill ".cursor/rules" || true
            ;;
        copilot)
            echo ""
            echo "Installing for GitHub Copilot..."
            copy_skill ".github/copilot-instructions.md" || true
            copy_skill ".github/instructions" || true
            ;;
        cline)
            echo ""
            echo "Installing for Cline..."
            copy_skill ".clinerules" || true
            ;;
        windsurf)
            echo ""
            echo "Installing for Windsurf..."
            copy_skill ".windsurf/rules" || true
            ;;
        roo)
            echo ""
            echo "Installing for Roo Code..."
            copy_skill ".roo/rules" || true
            ;;
        aider)
            echo ""
            echo "Installing for Aider..."
            copy_skill ".aider.conf.yml" || true
            if [[ ! " ${COPIED_FILES[*]:-} " =~ " AGENTS.md " ]]; then
                copy_skill "AGENTS.md" || true
                COPIED_FILES+=("AGENTS.md")
            fi
            ;;
    esac
}

for agent_key in "${INSTALL_AGENTS[@]}"; do
    install_agent "$agent_key"
done

# --- Summary ---
echo ""
echo "=== Installation Complete ==="
echo ""
echo "Installed for: ${INSTALL_AGENTS[*]}"
echo "Location: $TARGET"
echo ""
echo "Next steps:"
echo "  Run dependency check: ./install.sh --check-deps"
echo ""
