#!/usr/bin/env bash
# Post-conditions of profiles/optional/post-checks.yaml (optional module "post-checks"). The module itself is a
# set of asserts; this re-checks the parts that are not covered by the other modules' assertions.
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_post_checks() {
    ASSERT_MODULE=post-checks
    if id -nG | grep -qw docker; then
        if has_network && has_systemd; then
            check "docker run --rm hello-world without sudo" docker run --rm hello-world
        else
            skip "docker run hello-world" "no network/systemd"
        fi
    else
        skip "docker without sudo" "docker group takes effect after log out/in"
    fi
    check_sh "nvim runs" 'command -v nvim >/dev/null && nvim --version | head -n1'
}

assert_main assert_post_checks
