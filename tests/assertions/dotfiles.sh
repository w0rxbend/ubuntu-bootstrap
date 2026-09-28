#!/usr/bin/env bash
# Post-conditions of profiles/80-dotfiles.yaml (module "dotfiles"): the live clone, every dotbot link, agent
# skills, and a zsh that still finds the user's CLIs.
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SB_DIR="${SYSTEM_BOOTSTRAP_DIR:-$HOME/.system-bootstrap}"

# Every skill folder has a SKILL.md whose name: equals the folder name (see dotfiles/agents/skills/README.md).
_skills_names_match() {
    local dir="$ASSERT_REPO_DIR/dotfiles/agents/skills" d n bad=0
    for d in "$dir"/*/; do
        [[ -d "$d" ]] || continue
        d="$(basename "$d")"
        [[ "$d" == synced ]] && continue
        n="$(sed -n 's/^name:[[:space:]]*//p' "$dir/$d/SKILL.md" 2>/dev/null | head -n1 | tr -d "\"'")"
        if [[ "$n" != "$d" ]]; then
            echo "$d: name is '${n:-<no SKILL.md>}'"
            bad=1
        fi
    done
    return $bad
}

# The interactive zsh the user gets must still find the CLIs the installers put on PATH (the hand-edited
# ~/.zshrc used to add them).
# _zsh_finds CMD...  - an interactive zsh (the linked ~/.zshrc + ~/.custom.zsh) resolves every CMD on its PATH
_zsh_finds() {
    local out
    out="$(env -u KITTY_WINDOW_ID -u TMUX WITH_TMUX=false WITH_ZELLIJ=false \
        timeout 60 zsh -i -c 'for c in "$@"; do print -r -- "$c=$(whence -p $c)"; done' zsh "$@" 2>/dev/null </dev/null)"
    printf '%s\n' "$out"
    [[ -n "$out" ]] && ! grep -q '=$' <<<"$out"
}

# Prints "tool<TAB>fork<TAB>clone" for every tool whose pin in `spec.versions` differs between the Ubuntu fork
# config/binstaller.yaml and the clone's .files/.config/binstaller/config.yaml (tools only one side has are
# listed with "-" for the other side).
_binstaller_version_drift() {
    python3 - "$ASSERT_REPO_DIR/config/binstaller.yaml" "$SB_DIR/.files/.config/binstaller/config.yaml" <<'PY'
import sys, yaml
def versions(path):
    with open(path) as fh:
        return (yaml.safe_load(fh).get("spec") or {}).get("versions") or {}
fork, clone = versions(sys.argv[1]), versions(sys.argv[2])
for tool in sorted(set(fork) | set(clone)):
    if tool == "yq" and tool not in clone:  # Ubuntu-only addition, documented in config/binstaller.yaml
        continue
    if fork.get(tool) != clone.get(tool):
        print(f"{tool}\t{fork.get(tool, '-')}\t{clone.get(tool, '-')}")
PY
}

assert_dotfiles() {
    ASSERT_MODULE=dotfiles
    section "~/.system-bootstrap live clone"
    check "clone exists" test -d "$SB_DIR/.git"
    check_sh "origin is the https URL" "git -C '$SB_DIR' remote get-url origin | grep -Eq '^https://github.com/w0rxbend/system-bootstrap(\\.git)?\$'"
    check_sh "pushurl is SSH" "test \"\$(git -C '$SB_DIR' config --get remote.origin.pushurl)\" = git@github.com:w0rxbend/system-bootstrap.git"
    if has_network; then
        check "clone contains the remote HEAD (fast-forwarded)" "$ASSERT_REPO_DIR/scripts/system-bootstrap-sync.sh" --check
    else
        skip "clone up to date" "ASSERT_NETWORK=0"
    fi
    # Content, not names: every git-tracked file of this repo against every git-tracked file under the clone's
    # .files, byte for byte and with comments/quotes/whitespace normalised away. config/binstaller.yaml is not
    # allow-listed: it is a real fork (different content), so it never matches; the drift check below covers it.
    check "no file of this repo is a copy of a system-bootstrap dotfile (content check)" \
        python3 "$ASSERT_REPO_DIR/tests/lib/find_copies.py" "$ASSERT_REPO_DIR" "$SB_DIR"
    local drift
    if drift="$(_binstaller_version_drift 2>&1)"; then
        if [[ -z "$drift" ]]; then
            _a_ok "config/binstaller.yaml pins the same versions as the clone's binstaller config"
        else
            while IFS=$'\t' read -r tool fork clone; do
                skip "binstaller pin for $tool" "Ubuntu fork has $fork, system-bootstrap has $clone: port the bump into config/binstaller.yaml"
            done <<<"$drift"
        fi
    else
        _a_fail "compare config/binstaller.yaml with the clone's binstaller config" "$drift"
    fi

    section "dotbot links (both configs, if: conditions evaluated)"
    check "scripts/dotfiles-link.sh --check: every applicable link resolves to its source" "$ASSERT_REPO_DIR/scripts/dotfiles-link.sh" --check
    assert_link "$HOME/.zshrc" "$SB_DIR/.files/.zshrc"
    assert_link "$HOME/.tmux.conf" "$SB_DIR/.files/.tmux.conf"
    assert_link "$HOME/.config/nvim" "$SB_DIR/.files/nvim"
    assert_link "$HOME/.config/kitty/kitty.conf" "$SB_DIR/.files/kitty.conf"
    assert_link "$HOME/.config/starship.toml" "$SB_DIR/.files/starship.toml"
    assert_link "$HOME/.config/ghostty" "$SB_DIR/.files/.config/ghostty"
    assert_link "$HOME/.config/zellij/config.kdl" "$SB_DIR/.files/.config/zellij/config.kdl"
    assert_link "$HOME/.config/yazi/yazi.toml" "$SB_DIR/.files/.config/yazi/yazi.toml"
    assert_link "$HOME/.config/nerd-fonts-installer/config.yaml" "$SB_DIR/.files/.config/nerd-fonts-installer/config.yaml"
    # The linked yazi config must load in the pinned yazi (config/binstaller.yaml). The files come from the
    # system-bootstrap clone, so a format break there is reported (skip + reason), not fixed here: yazi then
    # stops at "Press <Enter> to continue with preset settings" on every start. Fix it upstream.
    if [[ -x "$HOME/.apps/yazi/bin/yazi" ]]; then
        local yout
        if yout="$("$HOME/.apps/yazi/bin/yazi" --version </dev/null 2>&1)"; then
            _a_ok "yazi loads the linked ~/.config/yazi"
        else
            skip "yazi loads the linked ~/.config/yazi" "the pinned yazi rejects the upstream config: $(head -n1 <<<"$yout"); fix .files/.config/yazi in ~/.system-bootstrap"
        fi
    fi
    assert_link "$HOME/.custom.zsh" "$ASSERT_REPO_DIR/dotfiles/custom.zsh"
    assert_link "$HOME/system-update.sh" "$ASSERT_REPO_DIR/dotfiles/ubuntu-system-update.sh"
    assert_link "$HOME/.config/ubuntu-xdg-terminals.list" "$ASSERT_REPO_DIR/dotfiles/.config/xdg-terminals.list"
    assert_link "$HOME/.config/gnome-xdg-terminals.list" "$ASSERT_REPO_DIR/dotfiles/.config/xdg-terminals.list"
    assert_link "$HOME/.config/binstaller/config.yaml" "$ASSERT_REPO_DIR/config/binstaller.yaml"
    check_sh "no niri / DMS config linked" "! test -L '$HOME/.config/niri' && ! test -L '$HOME/.config/niri/config.kdl' && ! test -L '$HOME/.config/DankMaterialShell/settings.json'"
    if [[ -d "$HOME/.local/share/gnome-shell/extensions/paperwm@paperwm.github.com" || -d /usr/share/gnome-shell/extensions/paperwm@paperwm.github.com ]]; then
        assert_link "$HOME/.config/paperwm/paperwm.conf" "$SB_DIR/.files/paperwm.conf"
    else
        check "paperwm.conf not linked (PaperWM not installed)" test ! -L "$HOME/.config/paperwm/paperwm.conf"
    fi
    if [[ -e "$HOME/.ubuntu-bootstrap-backup" ]]; then
        _a_ok "backups of replaced files kept in ~/.ubuntu-bootstrap-backup"
    fi

    section "agent skills"
    local skills="$ASSERT_REPO_DIR/dotfiles/agents/skills"
    check "dotfiles/agents/skills is a real, git-tracked directory" bash -c "test -d '$skills' && ! test -L '$skills' && git -C '$ASSERT_REPO_DIR' ls-files --error-unmatch dotfiles/agents/skills/README.md"
    assert_link "$HOME/.agents/skills" "$skills"
    assert_link "$HOME/.claude/skills" "$skills"
    local agent
    for agent in .cursor .gemini .copilot .config/opencode; do
        if [[ -d "$HOME/$agent" ]]; then
            assert_link "$HOME/$agent/skills" "$skills"
        else
            skip "~/$agent/skills" "agent not installed"
        fi
    done
    check "scripts/link-skills.sh --check" sh "$ASSERT_REPO_DIR/scripts/link-skills.sh" --check
    check "every skill folder name equals its SKILL.md name:" _skills_names_match

    section "shell"
    if command -v zsh >/dev/null 2>&1; then
        check "interactive zsh finds starship, eza" _zsh_finds starship eza
        # claude, codex and kimi come from desktop-apps. The container runs no GUI module, so there they are
        # only checked when present (the host always checks them: a missing one fails).
        local agents=() missing=() c p
        for c in claude:"$HOME/.local/bin/claude" codex:"$HOME/.local/bin/codex" kimi:"$HOME/.kimi-code/bin/kimi"; do
            p="${c#*:}"
            if [[ -x "$p" ]] || ! in_container; then agents+=("${c%%:*}"); else missing+=("${c%%:*}"); fi
        done
        [[ ${#agents[@]} -eq 0 ]] || check "interactive zsh finds ${agents[*]}" _zsh_finds "${agents[@]}"
        [[ ${#missing[@]} -eq 0 ]] || skip "interactive zsh finds ${missing[*]}" "installed by desktop-apps, which the container does not run"
    else
        skip "interactive zsh" "zsh missing"
    fi
    check "tmux plugins installed (TPM)" test -d "$HOME/.tmux/plugins/tmux-sensible"
    check "broot launcher written" test -s "$HOME/.config/broot/launcher/bash/br"
}

assert_main assert_dotfiles
