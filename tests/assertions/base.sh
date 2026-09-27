#!/usr/bin/env bash
# Post-conditions of profiles/00-base.yaml (module "base").
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_base() {
    ASSERT_MODULE=base
    section "apt archive packages (every apt-packages list in the profile)"
    mapfile -t pkgs < <(profile_query 00-base.yaml apt-packages)
    assert_pkgs "base" "${pkgs[@]}"

    section "commands"
    local c
    for c in git zsh curl wget jq fzf tmux rg btop htop zoxide pipx clang cmake meson gdb valgrind vlc mpv zathura virsh; do
        assert_cmd "$c"
    done
    check "python3 can import yaml (python3-yaml)" python3 -c 'import yaml'
    assert_link "$HOME/.local/bin/bat" /usr/bin/batcat
    check "bat (batcat) runs" "$HOME/.local/bin/bat" --version

    section "apt sources"
    check_sh "no broken Crystal source (no '\\/' in crystal.list)" "! grep -qsF '\\/' /etc/apt/sources.list.d/crystal.list"
    check_sh "no empty Crystal keyring in trusted.gpg.d" '! { test -f /etc/apt/trusted.gpg.d/devel_languages_crystal.gpg && ! test -s /etc/apt/trusted.gpg.d/devel_languages_crystal.gpg; }'
    if has_network && can_sudo; then
        check_sh "apt-get update succeeds without errors or Signed-By conflicts" \
            'out="$(sudo -n apt-get update 2>&1)"; rc=$?; printf "%s\n" "$out" | grep -E "^(E:|W: Conflicting)" && exit 1; exit $rc'
    else
        skip "apt-get update" "needs network and sudo -n"
    fi

    section "debconf preseeds"
    check_sh "mscorefonts EULA preseeded" "debconf-show ttf-mscorefonts-installer 2>/dev/null | grep -q 'accepted-mscorefonts-eula: true'"
    check_sh "wireshark setuid preseeded to false" "debconf-show wireshark-common 2>/dev/null | grep -q 'install-setuid: false'"

    section "services and system settings"
    # libvirtd.service is socket-activated and exits after 120 s idle: assert the socket, the service's
    # enablement, and that a client connection really reaches the daemon (which starts it on demand).
    assert_unit libvirtd.socket
    if has_systemd; then
        check_sh "libvirtd.service enabled" 'test "$(systemctl is-enabled libvirtd.service)" = enabled'
        if can_sudo; then
            check "virsh reaches qemu:///system (socket-activates libvirtd)" sudo -n virsh -c qemu:///system version
        else
            skip "virsh -c qemu:///system version" "needs sudo -n"
        fi
    fi
    if has_systemd; then
        check_sh "NTP enabled" 'timedatectl show -p NTP --value | grep -qx yes'
        check_sh "RTC in UTC" 'timedatectl show -p LocalRTC --value | grep -qx no'
    else
        skip "timedatectl NTP/RTC" "no systemd"
    fi

    section "git config (global)"
    check_sh "user.name = w0rxbend" 'test "$(git config --global --get user.name)" = w0rxbend'
    check_sh "user.email = balyszyn@gmail.com" 'test "$(git config --global --get user.email)" = balyszyn@gmail.com'
    check_sh "pull.rebase = true" 'test "$(git config --global --get pull.rebase)" = true'
    check_sh "init.defaultBranch = main" 'test "$(git config --global --get init.defaultBranch)" = main'
    check_sh "core.autocrlf = input" 'test "$(git config --global --get core.autocrlf)" = input'
}

assert_main assert_base
