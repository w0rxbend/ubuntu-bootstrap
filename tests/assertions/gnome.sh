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

# Current workspace index as mutter publishes it on the Xwayland root window (_NET_CURRENT_DESKTOP; unset until the
# first switch of the session, which counts as 0).
_gnome_current_ws() {
    local v
    v="$(xprop -root _NET_CURRENT_DESKTOP 2>/dev/null)" || return 1
    [[ "$v" == *"= "* ]] && printf '%s\n' "${v##*= }" || printf '0\n'
}

# Presses Super+<to> through a uinput keyboard and checks the workspace mutter reports, then goes back to <back>.
_gnome_live_super_n() {
    local to="$1" back="$2" got
    sudo -n python3 "$ASSERT_REPO_DIR/tests/lib/uinput_keys.py" "super+$to" || return 1
    sleep 0.5
    got="$(_gnome_current_ws)"
    sudo -n python3 "$ASSERT_REPO_DIR/tests/lib/uinput_keys.py" "super+$back" || true
    sleep 0.5
    [[ "$got" == "$((to - 1))" ]] || {
        echo "after Super+$to the current workspace index is '$got', expected $((to - 1))"
        return 1
    }
    [[ "$(_gnome_current_ws)" == "$((back - 1))" ]] || {
        echo "after Super+$back the current workspace index is '$(_gnome_current_ws)', expected $((back - 1))"
        return 1
    }
}

assert_gnome() {
    ASSERT_MODULE=gnome
    if ! has_gui; then
        no_gui "gnome checks (workspaces, Super+N, favourites)"
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
    # gnome-favorite-apps writes the list once (its probe: Vesktop pinned) and then keeps hand edits, so only
    # that is required; pins of the declared list that were removed by hand are reported, not failed.
    local fav a unpinned=()
    fav="$(gsettings get org.gnome.shell favorite-apps 2>/dev/null)"
    check "favourites written (Vesktop pinned: the gnome-favorite-apps probe)" grep -qF "'dev.vencord.Vesktop.desktop'" <<<"$fav"
    for a in ghostty_ghostty.desktop chatgpt.desktop com.anthropic.Claude.desktop paseo.desktop; do
        grep -qF "'$a'" <<<"$fav" || unpinned+=("$a")
    done
    if [[ ${#unpinned[@]} -eq 0 ]]; then
        _a_ok "favourites include Ghostty, ChatGPT, Claude and Paseo"
    else
        skip "favourites include Ghostty, ChatGPT, Claude and Paseo" "unpinned by hand, kept: ${unpinned[*]}"
    fi
    section "live session (mutter)"
    if command -v xprop >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
        check_sh "mutter runs 9 workspaces (_NET_NUMBER_OF_DESKTOPS)" \
            "xprop -root _NET_NUMBER_OF_DESKTOPS | grep -qE '= 9\$'"
    else
        skip "mutter workspace count" "no xprop or DISPLAY"
    fi
    # Opt-in: injects real key presses into the session (Super+3, then Super+1; ends on workspace 1).
    if [[ "${ASSERT_LIVE_INPUT:-0}" != 1 ]]; then
        skip "Super+N key presses switch workspace" "set ASSERT_LIVE_INPUT=1 (injects keys via /dev/uinput)"
    elif ! can_sudo || [[ ! -e /dev/uinput ]] || ! command -v xprop >/dev/null 2>&1 || [[ -z "${DISPLAY:-}" ]]; then
        skip "Super+N key presses switch workspace" "needs sudo -n, /dev/uinput, xprop and DISPLAY"
    else
        check "Super+3 switches to workspace 3, Super+1 back to 1 (real key presses)" _gnome_live_super_n 3 1
    fi
}

assert_main assert_gnome
