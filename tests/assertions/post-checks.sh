#!/usr/bin/env bash
# Post-conditions of profiles/optional/post-checks.yaml (optional module "post-checks"). The module itself is a
# set of asserts, two of which are bound to the login session (docker group, Vicinae extension loaded) and only
# pass after a log out/in that follows the install. This checks what the install left behind, so it holds in
# the session that ran the install too, and treats the session-bound parts as informational until re-login.
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VICINAE_EXT="$HOME/.local/share/gnome-shell/extensions/vicinae@dagimg-dot"

assert_post_checks() {
    ASSERT_MODULE=post-checks
    section "docker without sudo"
    assert_group_member docker
    if id -nG | grep -qw docker; then
        if has_network && has_systemd; then
            check "docker run --rm hello-world without sudo" docker run --rm hello-world
        else
            skip "docker run hello-world" "no network/systemd"
        fi
    elif has_network && has_systemd && command -v sg >/dev/null; then
        # The group exists in /etc/group but not in this session yet: prove it is enough with sg.
        check_sh "docker run --rm hello-world with the docker group (sg; session gets it at next login)" \
            "sg docker -c 'docker run --rm hello-world' >/dev/null"
    else
        skip "docker without sudo" "docker group takes effect after log out/in"
    fi

    section "login shell, fonts, editor"
    check_sh "login shell is zsh" 'getent passwd "$USER" | grep -q "/zsh$"'
    check_sh "VictorMono Nerd Font known to fontconfig" "fc-list | grep -qi 'VictorMono Nerd'"
    check_sh "nvim runs" 'command -v nvim >/dev/null && nvim --version | head -n1'

    section "Vicinae"
    if has_user_systemd; then
        check "vicinae server answers ping" /usr/local/bin/vicinae ping
    else
        skip "vicinae ping" "no systemd user session"
    fi
    check "extension unpacked" test -f "$VICINAE_EXT/metadata.json"
    if has_gui; then
        check_sh "extension in org.gnome.shell enabled-extensions" \
            "gsettings get org.gnome.shell enabled-extensions | grep -qF \"'vicinae@dagimg-dot'\""
        if gnome-extensions info vicinae@dagimg-dot 2>/dev/null | grep -Eq 'State: (ACTIVE|ENABLED)'; then
            _a_ok "extension is loaded by the running shell"
        else
            skip "extension loaded by the running shell" "becomes ACTIVE after the next log out/in"
        fi
    fi
}

assert_main assert_post_checks
