#!/bin/sh
# link-skills.sh - point every installed coding agent at the one shared skills folder.
#
# Source of truth: ~/.agents/skills, a symlink to ~/.zorin-bootstrap/dotfiles/agents/skills (git-tracked).
# Codex reads ~/.agents/skills natively. For the others this creates <agent-dir>/skills -> ~/.agents/skills:
#   Claude Code ~/.claude   Cursor ~/.cursor   Gemini CLI ~/.gemini   Copilot CLI ~/.copilot
#   opencode ~/.config/opencode
#
#   scripts/link-skills.sh            # create/repair the links (idempotent)
#   scripts/link-skills.sh --check    # report only; exit 1 when a link is missing or wrong
#   scripts/link-skills.sh --dry-run  # print what would change
#
# Rules: agents that are not installed (no agent dir) are skipped; a link that already resolves to the shared
# folder is left alone (dotbot links the agents straight at the repo folder, which is the same place); a wrong
# symlink is replaced with `ln -sfn`; a REAL directory is never overwritten or deleted: it is reported and the
# script exits 1, so move it away (e.g. to ~/.zorin-bootstrap-backup/) and re-run.
# dotbot (dotfiles/install.conf.yaml) creates the same links during the bootstrap; this script is for later
# changes, such as an agent installed after the bootstrap.
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
repo_skills="$here/../dotfiles/agents/skills"
repo_skills=$(CDPATH='' cd -- "$repo_skills" && pwd -P)
src="$HOME/.agents/skills"

mode=apply
case "${1:-}" in
    '') ;;
    --check) mode=check ;;
    -n | --dry-run) mode=dry-run ;;
    -h | --help)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "link-skills: unknown argument: $1" >&2
        exit 2
        ;;
esac

problems=0

# resolve PATH -> canonical path, or empty when it does not resolve
resolve() {
    readlink -f -- "$1" 2>/dev/null || true
}

# link TARGET SOURCE LABEL
link() {
    target=$1
    source=$2
    label=$3
    want=$(resolve "$source")
    if [ -L "$target" ]; then
        if [ -n "$want" ] && [ "$(resolve "$target")" = "$want" ]; then
            echo "ok        $label: $target"
            return 0
        fi
        action="relink"
    elif [ -e "$target" ]; then
        echo "CONFLICT  $label: $target is a real directory or file; not touching it (move it away and re-run)" >&2
        problems=$((problems + 1))
        return 0
    else
        action="link"
    fi
    case "$mode" in
        check)
            echo "MISSING   $label: $target -> $source" >&2
            problems=$((problems + 1))
            ;;
        dry-run)
            printf '%-9s %s\n' "would-$action" "$label: $target -> $source"
            ;;
        apply)
            mkdir -p -- "$(dirname -- "$target")"
            ln -sfn -- "$source" "$target"
            printf '%-9s %s\n' "$action" "$label: $target -> $source"
            ;;
    esac
}

# 1. ~/.agents/skills -> repo folder (Codex reads this path natively)
link "$src" "$repo_skills" "agents"

# 2. every installed agent -> ~/.agents/skills
for entry in \
    "claude:$HOME/.claude" \
    "cursor:$HOME/.cursor" \
    "gemini:$HOME/.gemini" \
    "copilot:$HOME/.copilot" \
    "opencode:$HOME/.config/opencode"; do
    name=${entry%%:*}
    dir=${entry#*:}
    if [ ! -d "$dir" ]; then
        echo "skip      $name: not installed ($dir missing)"
        continue
    fi
    link "$dir/skills" "$src" "$name"
done

if [ "$problems" -gt 0 ]; then
    echo "link-skills: $problems problem(s)" >&2
    exit 1
fi
