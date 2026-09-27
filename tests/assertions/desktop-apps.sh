#!/usr/bin/env bash
# Post-conditions of profiles/60-desktop-apps.yaml (module "desktop-apps").
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_desktop_apps() {
    ASSERT_MODULE=desktop-apps
    section "flatpaks (every flatpak-packages list in the profile)"
    if ! in_container && command -v flatpak >/dev/null 2>&1; then
        check_sh "flathub remote configured (system)" 'flatpak remotes --system --columns=name | grep -qx flathub'
    fi
    mapfile -t apps < <(profile_query 60-desktop-apps.yaml flatpaks)
    assert_flatpaks "desktop-apps" "${apps[@]}"

    section "snaps"
    mapfile -t snaps < <(profile_query 60-desktop-apps.yaml snaps)
    assert_snaps "desktop-apps" "${snaps[@]}"

    section "AI CLIs (they must also be on PATH in an interactive zsh: see dotfiles)"
    assert_exec "$HOME/.local/bin/claude" '[0-9]+\.[0-9]+'
    assert_exec "$HOME/.local/bin/codex" 'codex'
    assert_exec "$HOME/.kimi-code/bin/kimi" '[0-9]+\.[0-9]+'

    section "home-dir apps"
    assert_exec "$HOME/.local/zed.app/bin/zed" 'Zed'
    check "Paseo AppImage" test -x "$HOME/AppImages/paseo.appimage"
    check "Paseo launcher" test -f "$HOME/.local/share/applications/paseo.desktop"
    check "paseo on PATH (~/.local/bin/paseo)" test -e "$HOME/.local/bin/paseo"
}

assert_main assert_desktop_apps
