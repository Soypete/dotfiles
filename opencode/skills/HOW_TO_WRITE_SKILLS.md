# How to Write OpenCode Skills

A skill is a slash command (`/foo`) that injects instructions into the conversation. OpenCode reads them as Markdown files with YAML frontmatter.

## Where they live

OpenCode searches these locations (first match wins per skill name):

- Project: `.opencode/skills/<name>/SKILL.md`
- Global: `$XDG_CONFIG_HOME/opencode/skills/<name>/SKILL.md`
- Claude-compatible: `.claude/skills/<name>/SKILL.md`, `~/.claude/skills/<name>/SKILL.md`
- Agent-compatible: `.agents/skills/<name>/SKILL.md`, `~/.agents/skills/<name>/SKILL.md`

For me, `XDG_CONFIG_HOME=~/dotfiles`, so global skills live at `~/dotfiles/opencode/skills/<name>/SKILL.md`. The directory name must match the `name` field in frontmatter.

## File format

Every skill is one `SKILL.md` with frontmatter:

```markdown
---
name: my-skill
description: One sentence describing what the skill does.
trigger: /my-skill
---

# /my-skill

Body markdown — instructions OpenCode injects when the user types `/my-skill`.
```

### Required fields

- `name` — 1–64 chars, lowercase alphanumeric + hyphens, must match the directory name.
- `description` — 1–1024 chars. Used by OpenCode to decide when the skill is relevant.

### Optional fields

- `trigger` — the slash command. Defaults to `/<name>` if omitted.
- `license`, `compatibility`, `metadata` — see OpenCode docs.

Unknown frontmatter keys are silently ignored.

## Permissions

Skills are gated by `opencode.json`. Keys can be exact skill names or glob patterns; values are `allow` / `deny` / `ask`. Prefer an explicit allowlist over `*` so a stray new skill doesn't auto-run:

```json
{
  "permission": {
    "skill": {
      "graphify": "allow",
      "llmwiki": "allow",
      "mempalace": "allow"
    }
  }
}
```

Wildcards work too — useful for namespaced groups or a deny-list:

```json
{
  "permission": {
    "skill": {
      "*": "allow",
      "internal-*": "deny",
      "experimental-*": "ask"
    }
  }
}
```

Note: `permission.skill` is the only valid skill-related key in `opencode.json`. A top-level `"skill": {...}` block (defining commands inline) is **not** a valid OpenCode config and will throw `ConfigInvalidError: Unrecognized key: "skill"`. Skills are always files on disk.

## Writing the body

The body is plain Markdown. It's prepended to the conversation when the skill fires, so write it as instructions to the model, not docs for a human. Things to include:

- **Usage** — show the exact CLI shape: `/my-skill <arg> [--flag]`.
- **What you must do** — numbered, imperative steps. Be explicit about edge cases ("if no path given, use `.`"). The model follows this literally.
- **Bash blocks** — paste them in fenced code blocks; the model will run them via the Bash tool.
- **State files** — if a step writes a JSON file, say where and how the next step reads it.

Look at `graphify/SKILL.md` for a long example with multi-step pipelines and state passing. `llmwiki/SKILL.md` and `mempalace/SKILL.md` are shorter.

## Adding a new skill — recipe

```bash
mkdir -p ~/dotfiles/opencode/skills/my-skill
$EDITOR ~/dotfiles/opencode/skills/my-skill/SKILL.md
```

Minimum viable content:

```markdown
---
name: my-skill
description: What it does.
---

# /my-skill

When the user types `/my-skill <arg>`:

1. Do the first thing.
2. Do the second thing.
3. Report back.
```

Then in any OpenCode session: `/my-skill foo`.

## Common mistakes

- **`skill` block in `opencode.json`** — there isn't one. Skills are files, not config entries.
- **Per-name `permission.skill` map** — must be glob patterns (`"*"`, `"foo-*"`), not skill names.
- **Directory ≠ name** — `~/dotfiles/opencode/skills/foo/SKILL.md` with `name: bar` won't load.
- **Forgetting frontmatter** — a `SKILL.md` without `name` and `description` is silently ignored.
- **Wrong filename** — must be `SKILL.md` (uppercase), not `skill.md` or `README.md`.

## Debugging

- `opencode --version` to confirm the CLI works.
- Run `opencode` from any cwd; if your `opencode.json` has a syntax error, it fails fast with `ConfigInvalidError` and a JSON path to the bad key.
- To check OpenCode picks up a new skill, start a session and type `/` — the skill should appear in the completion list.
