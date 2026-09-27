#!/usr/bin/env bash
# Post-conditions of profiles/optional/gnome-extensions.yaml (optional module "gnome-extensions").
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_gnome_extensions() {
    ASSERT_MODULE=gnome-extensions
    assert_exec "$HOME/.local/bin/gext"
    if ! has_gui; then
        skip "extension checks" "no GNOME session bus"
        return
    fi
    local uuid
    for uuid in user-theme@gnome-shell-extensions.gcampax.github.com battery-indicator-icon@Deminder \
        notification-icons@muhammad_ans.github tophat@fflewddur.github.io space-bar@luchrioh AlphabeticalAppGrid@stuarthayhurst; do
        check_sh "$uuid installed and enabled" \
            "{ test -f \"\$HOME/.local/share/gnome-shell/extensions/$uuid/metadata.json\" || test -f /usr/share/gnome-shell/extensions/$uuid/metadata.json; } && gsettings get org.gnome.shell enabled-extensions | grep -qF \"'$uuid'\""
    done
}

assert_main assert_gnome_extensions
