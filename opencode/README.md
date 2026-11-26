# Using this skill with opencode

[opencode](https://opencode.ai) has first-class support for the same
`SKILL.md`-based Agent Skills format used by Claude Code, so this repository
works with both tools:

- **Claude Code**: install as a plugin (see the main [README](../README.md)). Files are referenced through the `${CLAUDE_PLUGIN_ROOT}` variable.
- **opencode**: install the skill and the `/decompile` command with the script below. Paths are rewritten to be relative to the skill directory, which is how opencode resolves them.

The installer always copies from the single canonical skill under
`plugins/android-reverse-engineering/skills/android-reverse-engineering/`,
so both tools share one source of truth — pull the latest master and re-run
the installer to update.

## Install

```bash
git clone https://github.com/SimoneAvogadro/android-reverse-engineering-skill
cd android-reverse-engineering-skill

bash opencode/install.sh              # global: ~/.config/opencode (all projects)
# or
bash opencode/install.sh --project    # current project only: ./.opencode/
```

This installs:

| Component | Global location | Project location |
|---|---|---|
| Skill | `~/.config/opencode/skills/android-reverse-engineering/` | `.opencode/skills/android-reverse-engineering/` |
| Command | `~/.config/opencode/commands/decompile.md` | `.opencode/commands/decompile.md` |

opencode discovers both automatically — no configuration file changes are
required for basic use.

## Verify it works

1. Start `opencode` in any directory.
2. Run `/decompile path/to/app.apk`, or simply ask something like
   *"decompile this APK and extract its API endpoints"* — the skill is
   advertised to the model through its description and is loaded on demand.
3. You can also reference it explicitly in a prompt with `@android-reverse-engineering`.

## Permissions (recommended)

By default opencode asks for confirmation before running shell commands and
loading skills. To let the agent run this skill and its helper scripts without
prompts, add these rules to your `opencode.json` / `opencode.jsonc`
(global: `~/.config/opencode/`, project: alongside `.opencode/`):

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "permissions": [
    { "action": "skill", "resource": "android-reverse-engineering", "effect": "allow" },
    { "action": "shell", "resource": "bash *android-reverse-engineering/scripts/*", "effect": "allow" },
    { "action": "read", "resource": "~/.config/opencode/skills/android-reverse-engineering/*", "effect": "allow" }
  ]
}
```

> The `shell` pattern matches commands like
> `bash ~/.config/opencode/skills/android-reverse-engineering/scripts/decompile.sh app.apk`.
> The skill scripts themselves invoke `jadx`, `java`, etc. — those still follow
> your normal permission settings.

## Uninstall / update

```bash
rm -rf ~/.config/opencode/skills/android-reverse-engineering \
       ~/.config/opencode/commands/decompile.md     # uninstall

git pull && bash opencode/install.sh                # update
```

## How the adapter works

The Claude Code SKILL.md references its scripts through the
`${CLAUDE_PLUGIN_ROOT}` variable, which only exists inside Claude Code
plugins. opencode instead resolves paths written in a `SKILL.md` relative to
the directory containing it. `opencode/install.sh` therefore:

1. Copies `plugins/.../skills/android-reverse-engineering/` (SKILL.md, scripts, references) to the opencode skills directory.
2. Rewrites every `${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/…` reference to the relative `scripts/…` / `references/…` form.
3. Adds a short note after the frontmatter telling the agent to resolve those relative paths against the skill base directory (which opencode provides when the skill loads).

Windows users: opencode discovers `~/.claude/skills` and `.claude/skills` too,
but this repository's skill is not directly usable from there because of the
`${CLAUDE_PLUGIN_ROOT}` references — run `bash opencode/install.sh` from Git
Bash / WSL, or copy the skill directory manually and strip the
`${CLAUDE_PLUGIN_ROOT}/skills/android-reverse-engineering/` prefix from the
paths in `SKILL.md`.
