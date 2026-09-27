#!/usr/bin/env bash
# Post-conditions of profiles/optional/wallpapers.yaml (optional module "wallpapers").
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_wallpapers() {
    ASSERT_MODULE=wallpapers
    check_sh "wallpapers present in ~/.local/share/backgrounds/system-bootstrap" \
        'test -n "$(find "$HOME/.local/share/backgrounds/system-bootstrap" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.jpeg" -o -iname "*.webp" \) -print -quit 2>/dev/null)"'
    # both sparse paths landed (assets/Backgrounds + assets/arch-backgrounds), as real images (not LFS pointers)
    check_sh "at least 20 images copied from both source folders" \
        'test "$(find "$HOME/.local/share/backgrounds/system-bootstrap" -type f | wc -l)" -ge 20'
    check_sh "files are real images" \
        'file -b --mime-type "$HOME"/.local/share/backgrounds/system-bootstrap/* | grep -qv "^image/" && exit 1 || exit 0'
    check_sh "no git metadata left in the wallpaper folder" \
        '! test -e "$HOME/.local/share/backgrounds/system-bootstrap/.git"'
}

assert_main assert_wallpapers
