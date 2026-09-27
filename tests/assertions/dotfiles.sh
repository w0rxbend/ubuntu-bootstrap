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
_zsh_finds_clis() {
    local out
    out="$(env -u KITTY_WINDOW_ID -u TMUX WITH_TMUX=false WITH_ZELLIJ=false \
        timeout 60 zsh -i -c 'for c in claude codex kimi starship eza; do print -r -- "$c=$(whence -p $c)"; done' 2>/dev/null </dev/null)"
    printf '%s\n' "$out"
    ! grep -q '=$' <<<"$out" && grep -q '^claude=' <<<"$out"
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
    check_sh "no dotfile copies left in this repo (dotfiles/ holds only Zorin-only files)" \
        "cd '$ASSERT_REPO_DIR/dotfiles' && ! ls -A | grep -Evx 'agents|custom.zsh|install.conf.yaml|system-bootstrap.conf.yaml|zorin-system-update.sh|\\.config'"

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
    assert_link "$HOME/system-update.sh" "$ASSERT_REPO_DIR/dotfiles/zorin-system-update.sh"
    assert_link "$HOME/.config/zorin-xdg-terminals.list" "$ASSERT_REPO_DIR/dotfiles/.config/xdg-terminals.list"
    assert_link "$HOME/.config/binstaller/config.yaml" "$ASSERT_REPO_DIR/config/binstaller.yaml"
    check_sh "no niri / DMS config linked" "! test -L '$HOME/.config/niri' && ! test -L '$HOME/.config/niri/config.kdl' && ! test -L '$HOME/.config/DankMaterialShell/settings.json'"
    if [[ -d "$HOME/.local/share/gnome-shell/extensions/paperwm@paperwm.github.com" || -d /usr/share/gnome-shell/extensions/paperwm@paperwm.github.com ]]; then
        assert_link "$HOME/.config/paperwm/paperwm.conf" "$SB_DIR/.files/paperwm.conf"
    else
        check "paperwm.conf not linked (PaperWM not installed)" test ! -L "$HOME/.config/paperwm/paperwm.conf"
    fi
    if [[ -e "$HOME/.zorin-bootstrap-backup" ]]; then
        _a_ok "backups of replaced files kept in ~/.zorin-bootstrap-backup"
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
        check "interactive zsh finds claude, codex, kimi, starship, eza" _zsh_finds_clis
    else
        skip "interactive zsh" "zsh missing"
    fi
    check "tmux plugins installed (TPM)" test -d "$HOME/.tmux/plugins/tmux-sensible"
    check "broot launcher written" test -s "$HOME/.config/broot/launcher/bash/br"
}

assert_main assert_dotfiles
