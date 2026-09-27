#!/usr/bin/env bash
# Post-conditions of profiles/90-session.yaml (module "session"): login shell and group membership.
# (/etc/passwd and /etc/group are checked, so this passes before the re-login that makes them effective.)
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_session() {
    ASSERT_MODULE=session
    section "login shell"
    check_sh "login shell of $USER is /usr/bin/zsh (getent passwd)" 'test "$(getent passwd "$USER" | cut -d: -f7)" = /usr/bin/zsh'
    section "groups (/etc/group)"
    local g
    for g in docker libvirt kvm; do assert_group_member "$g"; done
    if id -nG | grep -qw docker; then
        _a_ok "docker group active in this session"
    else
        skip "docker group active in this session" "takes effect after log out/in"
    fi
}

assert_main assert_session
