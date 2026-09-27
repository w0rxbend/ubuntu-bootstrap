#!/usr/bin/env bash
# Post-conditions of profiles/optional/wallpapers.yaml (optional module "wallpapers").
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_wallpapers() {
    ASSERT_MODULE=wallpapers
    check_sh "wallpapers present in ~/.local/share/backgrounds/system-bootstrap" \
        'test -n "$(find "$HOME/.local/share/backgrounds/system-bootstrap" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.jpeg" -o -iname "*.webp" \) -print -quit 2>/dev/null)"'
}

assert_main assert_wallpapers
