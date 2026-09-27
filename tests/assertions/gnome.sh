#!/usr/bin/env bash
# Post-conditions of profiles/70-gnome.yaml (module "gnome"): Fedora-style Super+1..9 workspaces on Zorin.
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Prints every gsettings key (except the workspace bindings themselves) whose value holds exactly <Super>N,
# <Super><Shift>N or <Shift><Super>N; fails when there is one. The Zorin Dash/Taskbar app-hotkey keys are
# ignored because they are inert once their extension's hot-keys=false (asserted separately).
_gnome_foreign_super_n() {
    local hits
    hits="$(gsettings list-recursively 2>/dev/null \
        | grep -E "'(<Super>|<Super><Shift>|<Shift><Super>)[1-9]'" \
        | grep -vE '^org\.gnome\.desktop\.wm\.keybindings (switch|move)-to-workspace-[1-9] ' \
        | grep -vE '^org\.gnome\.shell\.extensions\.zorin-(dash|taskbar) app-(shift-)?hotkey-[1-9] ' || true)"
    [[ -z "$hits" ]] || {
        printf '%s\n' "$hits"
        return 1
    }
}

assert_gnome() {
    ASSERT_MODULE=gnome
    if ! has_gui; then
        skip "all gnome checks" "no GNOME session bus"
        return
    fi
    section "workspaces"
    assert_gsetting org.gnome.mutter dynamic-workspaces false
    assert_gsetting org.gnome.desktop.wm.preferences num-workspaces 9

    section "Super+N switches, Super+Shift+N moves (N = 1..9)"
    local i
    for i in 1 2 3 4 5 6 7 8 9; do
        assert_gsetting org.gnome.desktop.wm.keybindings "switch-to-workspace-$i" "['<Super>$i']"
        assert_gsetting org.gnome.desktop.wm.keybindings "move-to-workspace-$i" "['<Super><Shift>$i']"
    done

    section "nothing else grabs Super+N / Shift+Super+N"
    for i in 1 2 3 4 5 6 7 8 9; do
        check_sh "switch-to-application-$i is empty" "gsettings get org.gnome.shell.keybindings switch-to-application-$i | grep -qF '[]'"
    done
    local schema
    for schema in org.gnome.shell.extensions.zorin-dash org.gnome.shell.extensions.zorin-taskbar; do
        if gsettings list-keys "$schema" 2>/dev/null | grep -qx hot-keys; then
            assert_gsetting "$schema" hot-keys false
        else
            skip "$schema hot-keys" "schema not installed"
        fi
    done
    check "no other gsettings key is bound to Super+N or Shift+Super+N" _gnome_foreign_super_n

    section "other settings"
    assert_gsetting org.gnome.shell.keybindings show-screenshot-ui "['<Super>Print', 'Print']"
    check_sh "favourites include Vesktop, ChatGPT, Claude and Paseo" \
        "f=\$(gsettings get org.gnome.shell favorite-apps); for a in dev.vencord.Vesktop.desktop chatgpt.desktop com.anthropic.Claude.desktop paseo.desktop; do grep -qF \"'\$a'\" <<<\"\$f\" || exit 1; done"
}

assert_main assert_gnome
