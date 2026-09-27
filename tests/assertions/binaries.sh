#!/usr/bin/env bash
# Post-conditions of profiles/40-binaries.yaml (module "binaries"): binstaller tools in ~/.apps, nvim links,
# Nerd Fonts.
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_binaries() {
    ASSERT_MODULE=binaries
    section "binstaller tools (pinned versions from config/binstaller.yaml)"
    local a="$HOME/.apps"
    assert_exec "$a/yazi/bin/yazi" 'Yazi 26\.5\.6'
    assert_exec "$a/zig/zig" '^0\.15\.2' version
    assert_exec "$a/kind/bin/kind" 'kind v0\.31\.0' version
    assert_exec "$a/zellij/bin/zellij" 'zellij 0\.44\.1'
    assert_exec "$a/lazygit/bin/lazygit" 'version=0\.61\.0'
    assert_exec "$a/jujutsu/bin/jj" 'jj 0\.40\.0'
    assert_exec "$a/dotbot/bin/dotbot" '0\.4\.2'
    assert_exec "$a/minikube/bin/minikube" 'minikube version: v[0-9]' version
    assert_exec "$a/xplr/bin/xplr" 'xplr [0-9]'
    assert_exec "$a/kubectl/bin/kubectl" 'Client Version: v[0-9]' version --client
    assert_exec "$a/neovim/bin/nvim" '^NVIM v0\.(1[0-9]|[2-9][0-9])'
    assert_exec "$a/neovide/bin/neovide"
    assert_exec "$a/yq/bin/yq" 'mikefarah|version v4'

    section "system-wide nvim links (sudo vim opens the same Neovim)"
    local l
    for l in nvim neovim vim; do assert_link "/usr/local/bin/$l" "$a/neovim/bin/nvim"; done

    section "Nerd Fonts (one family per batch, plus the terminals' fonts)"
    if command -v fc-list >/dev/null 2>&1; then
        local f
        for f in 'JetBrainsMono Nerd' 'VictorMono Nerd' 'FiraCode Nerd' 'Mononoki Nerd' 'Lilex Nerd' 'Noto.*Nerd'; do
            check "font family /$f/ installed" bash -c "fc-list | grep -qi '$f'"
        done
    else
        skip "Nerd Fonts" "fc-list missing"
    fi
}

assert_main assert_binaries
