#!/usr/bin/env bash
# Post-conditions of profiles/50-shell.yaml (module "shell").
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_shell() {
    ASSERT_MODULE=shell
    section "oh-my-zsh, plugins, TPM (pinned commits from the profile)"
    check "oh-my-zsh installed" test -f "$HOME/.oh-my-zsh/oh-my-zsh.sh"
    local dest ref _url
    while IFS=$'\t' read -r dest ref _url; do
        assert_git_head "$dest" "$ref"
    done < <(profile_query 50-shell.yaml git-repos)

    section "starship, kitty"
    assert_exec "$HOME/.local/bin/starship" '^starship [0-9]'
    assert_exec "$HOME/.local/kitty.app/bin/kitty" '^kitty [0-9]'
    assert_link "$HOME/.local/bin/kitty" "$HOME/.local/kitty.app/bin/kitty"
    assert_link "$HOME/.local/bin/kitten" "$HOME/.local/kitty.app/bin/kitten"
    assert_file_contains "$HOME/.local/share/applications/kitty.desktop" "Exec=$HOME/.local/kitty.app/bin/kitty"
    check_sh "x-terminal-emulator alternative is kitty" 'readlink -f /etc/alternatives/x-terminal-emulator | grep -q kitty.app'

    section "ghostty (snap)"
    assert_snaps "ghostty" ghostty
}

assert_main assert_shell
