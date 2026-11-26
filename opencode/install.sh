#!/usr/bin/env bash
#
# Install the android-reverse-engineering skill and /decompile command for opencode.
#
# opencode discovers skills in:
#   ~/.config/opencode/skills/<id>/   (global)   or   .opencode/skills/<id>/   (project)
# and commands in:
#   ~/.config/opencode/commands/      (global)   or   .opencode/commands/     (project)
#
# The Claude Code plugin references its files through the ${CLAUDE_PLUGIN_ROOT}
# variable, which only exists inside Claude Code plugins. opencode resolves
# paths written in a SKILL.md relative to the directory containing that
# SKILL.md, so this script copies the skill and rewrites those references to
# relative paths. The source skill in this repository is never modified.
#
# Usage:
#   bash opencode/install.sh              # global install (~/.config/opencode)
#   bash opencode/install.sh --project    # install into ./.opencode of the cwd
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_SRC="$REPO_ROOT/plugins/android-reverse-engineering/skills/android-reverse-engineering"
COMMAND_SRC="$SCRIPT_DIR/command/decompile.md"
SKILL_ID="android-reverse-engineering"

SCOPE="global"
if [[ "${1:-}" == "--project" ]]; then
  SCOPE="project"
elif [[ -n "${1:-}" ]]; then
  echo "Unknown option: $1 (supported: --project)" >&2
  exit 1
fi

if [[ "$SCOPE" == "global" ]]; then
  DEST_BASE="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
else
  DEST_BASE=".opencode"
fi
DEST_SKILL="$DEST_BASE/skills/$SKILL_ID"
DEST_CMD="$DEST_BASE/commands/decompile.md"

[[ -f "$SKILL_SRC/SKILL.md" ]] || { echo "ERROR: SKILL.md not found at $SKILL_SRC" >&2; exit 1; }
[[ -f "$COMMAND_SRC" ]] || { echo "ERROR: command template not found at $COMMAND_SRC" >&2; exit 1; }

# Clean reinstall so files removed upstream do not linger.
rm -rf "$DEST_SKILL"
mkdir -p "$DEST_SKILL" "$(dirname "$DEST_CMD")"
cp -R "$SKILL_SRC/." "$DEST_SKILL/"
cp "$COMMAND_SRC" "$DEST_CMD"

# Rewrite ${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/<rest>
# to the relative path <rest> (resolved against the SKILL.md directory by opencode).
find "$DEST_SKILL" -type f -name '*.md' -exec \
  sed -i 's|\${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/||g' {} +

# Make the relative-path convention explicit for the agent, right after the
# YAML frontmatter.
NOTE='> **Paths in this document are relative to the directory containing this SKILL.md.** Resolve `scripts/…` and `references/…` against the skill base directory before running them.'
awk -v note="$NOTE" '
  /^---[[:space:]]*$/ { n++; print; if (n == 2) { print ""; print note; print "" } next }
  { print }
' "$DEST_SKILL/SKILL.md" > "$DEST_SKILL/SKILL.md.tmp" && mv "$DEST_SKILL/SKILL.md.tmp" "$DEST_SKILL/SKILL.md"

if grep -rq 'CLAUDE_PLUGIN_ROOT' "$DEST_SKILL"; then
  echo "ERROR: some CLAUDE_PLUGIN_ROOT references were not rewritten:" >&2
  grep -rn 'CLAUDE_PLUGIN_ROOT' "$DEST_SKILL" >&2
  exit 1
fi

echo "Skill   installed -> $DEST_SKILL"
echo "Command installed -> $DEST_CMD"
echo
echo "Verification:"
echo "  1. Start opencode in any project directory"
echo "  2. Run /decompile <path-to.apk> — or just ask to decompile an APK"
echo "     (the skill is auto-advertised via its description)"
echo
echo "To let opencode run the skill scripts without confirmation prompts, add"
echo "these rules to your opencode.json/c (see opencode/README.md for details):"
CONFIG_BASE="$(cd "$DEST_BASE" && pwd)"
cat <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "permissions": [
    { "action": "skill", "resource": "$SKILL_ID", "effect": "allow" },
    { "action": "shell", "resource": "bash *$SKILL_ID/scripts/*", "effect": "allow" },
    { "action": "read", "resource": "$CONFIG_BASE/skills/$SKILL_ID/*", "effect": "allow" }
  ]
}
EOF
