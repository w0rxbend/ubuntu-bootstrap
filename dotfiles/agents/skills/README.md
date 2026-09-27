# Agent skills

This folder is the single, git-tracked home of my agent skills. Every coding agent on this machine reads it
through a symlink, so a skill written once works in all of them:

| Link | Agent | Created |
|---|---|---|
| `~/.agents/skills` | Codex (reads it natively), and the shared location other agents are moving to | always |
| `~/.claude/skills` | Claude Code | always |
| `~/.cursor/skills` | Cursor | only when `~/.cursor` exists |
| `~/.gemini/skills` | Gemini CLI | only when `~/.gemini` exists |
| `~/.copilot/skills` | GitHub Copilot CLI | only when `~/.copilot` exists |
| `~/.config/opencode/skills` | opencode | only when `~/.config/opencode` exists |

dotbot creates the links (`dotfiles/install.conf.yaml`, run by `profiles/80-dotfiles.yaml` and `just dotfiles`).
`scripts/link-skills.sh` does the same on its own, for example after installing a new agent.

## Layout

One folder per skill. The folder name **must equal** the `name:` in the `SKILL.md` front matter, and the file
must be called exactly `SKILL.md` (upper case, no other name):

```
agents/skills/
├── README.md                 # this file (not a skill: it sits outside any skill folder)
├── .gitignore                # ignores synced/ (Claude Code's own cache of claude.ai skills)
└── my-skill/
    ├── SKILL.md              # front matter: name: my-skill, description: ...
    ├── scripts/              # optional helpers the skill refers to
    └── references/           # optional extra docs, loaded on demand
```

```markdown
---
name: my-skill
description: One or two sentences that tell the agent when to use this skill.
---

# My skill

Instructions...
```

Keep `description` specific: agents decide whether to load a skill from that line alone.

## Verify

Every skill folder must contain a `SKILL.md` whose `name:` equals the folder name:

```bash
cd ~/.zorin-bootstrap/dotfiles/agents/skills
for d in */; do
  d=${d%/}; [ "$d" = synced ] && continue
  n=$(sed -n 's/^name:[[:space:]]*//p' "$d/SKILL.md" 2>/dev/null | head -n1 | tr -d "\"'")
  [ "$n" = "$d" ] && echo "ok   $d" || echo "FAIL $d (name: '${n:-missing SKILL.md}')"
done
```

`tests/assertions/dotfiles.sh` runs the same check.

## Notes

- `synced/` is where Claude Code stores the skills it syncs from claude.ai. Because `~/.claude/skills` points
  here, that cache lands in this folder; it is git-ignored and Claude Code recreates it by itself. The
  bootstrap backs up the old real `~/.claude/skills` directory to `~/.zorin-bootstrap-backup/.claude/skills`
  before it is replaced by the link.
- Codex's bundled skills live in `~/.codex/skills/.system` and are never touched. `~/.codex/skills/onboard-new-user`
  was not moved here either: it is the Codex app's first-run onboarding skill (it drives app-only tools such as
  `setup_codex_step`), not a skill of mine, and it would be useless to the other agents.
