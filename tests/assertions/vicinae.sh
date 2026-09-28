#!/usr/bin/env bash
# Post-conditions of profiles/75-vicinae.yaml (module "vicinae"): launcher, server, GNOME extension, Super+D.
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VICINAE_KB=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/vicinae/
VICINAE_EXT="$HOME/.local/share/gnome-shell/extensions/vicinae@dagimg-dot"

assert_vicinae() {
    ASSERT_MODULE=vicinae
    section "install (/usr/local via the official script)"
    assert_exec /usr/local/bin/vicinae 'Version v0\.29\.0' version
    check_sh "/usr/local/bin/vicinae -> /usr/local/lib/vicinae/usr/bin/vicinae" \
        'test "$(readlink -f /usr/local/bin/vicinae)" = /usr/local/lib/vicinae/usr/bin/vicinae'
    check_sh "vicinae-input-server has cap_dac_override (snippets, paste)" \
        'getcap /usr/local/lib/vicinae/usr/libexec/vicinae/vicinae-input-server | grep -q cap_dac_override'
    assert_file_contains /usr/local/lib/systemd/user/vicinae.service "ExecStart=/usr/local/bin/vicinae server"
    check "AppImage download cleaned from the cache" test ! -e "$HOME/.cache/ubuntu-bootstrap/vicinae/Vicinae-x86_64-v0.29.0.AppImage"

    section "server (systemd user unit)"
    assert_unit --user vicinae.service
    if has_user_systemd; then
        check "vicinae ping answers" /usr/local/bin/vicinae ping
    else
        skip "vicinae ping" "no systemd user session"
    fi

    section "GNOME extension vicinae@dagimg-dot"
    check_sh "extension v1.7.2 unpacked with compiled schemas" \
        "grep -q '\"version-name\": \"1.7.2\"' '$VICINAE_EXT/metadata.json' && test -f '$VICINAE_EXT/schemas/gschemas.compiled'"
    if has_gui; then
        check_sh "listed in org.gnome.shell enabled-extensions" "gsettings get org.gnome.shell enabled-extensions | grep -qF \"'vicinae@dagimg-dot'\""
        check_sh "not in disabled-extensions" "! gsettings get org.gnome.shell disabled-extensions | grep -qF \"'vicinae@dagimg-dot'\""
        # Only true after a log out/in (Wayland loads extensions at login): informational until then.
        if gnome-extensions info vicinae@dagimg-dot 2>/dev/null | grep -Eq 'State: (ACTIVE|ENABLED)'; then
            _a_ok "extension is loaded by the running shell"
        else
            skip "extension loaded by the running shell" "becomes ACTIVE after the next log out/in"
        fi
    else
        no_gui "extension enabled in org.gnome.shell"
    fi

    section "Super+D toggles vicinae"
    if ! has_gui; then
        no_gui "Super+D keybinding checks"
        return
    fi
    check_sh "show-desktop no longer holds <Super>d" "! gsettings get org.gnome.desktop.wm.keybindings show-desktop | grep -qiF \"'<Super>d'\""
    assert_gsetting org.gnome.desktop.wm.keybindings show-desktop "['<Primary><Super>d', '<Primary><Alt>d']"
    check_sh "custom-keybindings lists $VICINAE_KB" \
        "gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings | grep -qF '$VICINAE_KB'"
    local s="org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:$VICINAE_KB"
    assert_gsetting "$s" binding "'<Super>d'"
    assert_gsetting "$s" command "'/usr/local/bin/vicinae toggle'"
    assert_gsetting "$s" name "'Vicinae'"
    check_sh "no other gsettings key is bound to Super+D" \
        "! gsettings list-recursively 2>/dev/null | grep -iE \"'<Super>d'\""
}

assert_main assert_vicinae
