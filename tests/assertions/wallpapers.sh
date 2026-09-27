#!/usr/bin/env bash
# Post-conditions of profiles/optional/wallpapers.yaml (optional module "wallpapers").
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_wallpapers() {
    ASSERT_MODULE=wallpapers
    check_sh "wallpapers present in ~/.local/share/backgrounds/system-bootstrap" \
        'test -n "$(find "$HOME/.local/share/backgrounds/system-bootstrap" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.jpeg" -o -iname "*.webp" \) -print -quit 2>/dev/null)"'
    # Both sparse paths landed: every file the source lists under assets/Backgrounds and
    # assets/arch-backgrounds is in the flattened folder. The list comes from the system-bootstrap clone (the
    # dotfiles module keeps it); without one, the three arch-backgrounds files stand in for the second path.
    local dest="$HOME/.local/share/backgrounds/system-bootstrap" sb="${SYSTEM_BOOTSTRAP_DIR:-$HOME/.system-bootstrap}"
    local expected=() missing=() f
    if [[ -d "$sb/.git" ]]; then
        mapfile -t expected < <(git -C "$sb" ls-tree -r --name-only HEAD assets/Backgrounds assets/arch-backgrounds |
            sed -E 's#^assets/(Backgrounds|arch-backgrounds)/##')
    fi
    if [[ ${#expected[@]} -eq 0 ]]; then
        expected=(beach-path.jpg coffee-shop.png minimalist-black-hole.png)
    elif ! printf '%s\n' "${expected[@]}" | grep -qxF coffee-shop.png; then
        _a_fail "the source still has assets/arch-backgrounds" "coffee-shop.png not listed in $sb"
    fi
    for f in "${expected[@]}"; do [[ -f "$dest/$f" ]] || missing+=("$f"); done
    if [[ ${#missing[@]} -eq 0 ]]; then
        _a_ok "all ${#expected[@]} source images (assets/Backgrounds + assets/arch-backgrounds) copied"
    else
        _a_fail "${#missing[@]}/${#expected[@]} source images missing from $dest" "${missing[*]}"
    fi
    check_sh "files are real images" \
        'file -b --mime-type "$HOME"/.local/share/backgrounds/system-bootstrap/* | grep -qv "^image/" && exit 1 || exit 0'
    check_sh "no git metadata left in the wallpaper folder" \
        '! test -e "$HOME/.local/share/backgrounds/system-bootstrap/.git"'
}

assert_main assert_wallpapers
