#!/usr/bin/env bash
# Post-conditions of profiles/10-apps.yaml (module "apps").
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_apps() {
    ASSERT_MODULE=apps
    section "apt repositories and keyrings"
    assert_file_contains /etc/apt/sources.list.d/github-cli.list \
        "deb [arch=amd64 signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main"
    assert_file_contains /etc/apt/sources.list.d/claude-desktop.list \
        "signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.gpg] https://downloads.claude.ai/claude-desktop/apt/stable stable main"
    assert_file_contains /etc/apt/sources.list.d/vscode.sources "Signed-By: /usr/share/keyrings/microsoft.gpg"
    assert_file_contains /etc/apt/sources.list.d/1password.sources "Signed-By: /usr/share/keyrings/1password-archive-keyring.gpg"
    assert_file_contains /etc/apt/sources.list.d/crystal.list \
        "deb [signed-by=/etc/apt/keyrings/crystal.gpg] https://download.opensuse.org/repositories/devel:/languages:/crystal/xUbuntu_24.04/ /"
    check "claude-desktop.list is exactly the declared source line" bash -c \
        "test \"\$(cat /etc/apt/sources.list.d/claude-desktop.list)\" = 'deb [arch=amd64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.gpg] https://downloads.claude.ai/claude-desktop/apt/stable stable main'"
    check "claude-desktop keyring holds exactly the pinned key 31DDDE24...ECACE" bash -c \
        "test \"\$(gpg --show-keys --with-colons /usr/share/keyrings/claude-desktop-archive-keyring.gpg 2>/dev/null | awk -F: '/^pub/{p=1;next} p&&/^fpr/{print \$10;p=0}')\" = 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
    local k
    for k in /etc/apt/keyrings/githubcli-archive-keyring.gpg /usr/share/keyrings/claude-desktop-archive-keyring.gpg \
        /usr/share/keyrings/microsoft.gpg /usr/share/keyrings/1password-archive-keyring.gpg /etc/apt/keyrings/crystal.gpg; do
        check "keyring $k is a non-empty OpenPGP keyring" bash -c "test -s '$k' && gpg --show-keys --with-colons '$k' 2>/dev/null | grep -q '^pub'"
    done

    section "packages"
    mapfile -t pkgs < <(profile_query 10-apps.yaml apt-packages)
    assert_pkgs "apps" "${pkgs[@]}" chatgpt fastfetch

    section "commands and versions"
    assert_cmd gh '^gh version [0-9]'
    assert_cmd code '^[0-9]+\.[0-9]+'
    assert_cmd 1password
    assert_cmd fastfetch 'fastfetch [0-9]'
    assert_cmd crystal 'Crystal 1\.(2[1-9]|[3-9][0-9])'
    assert_cmd shards 'Shards [0-9]'
    check "crystal comes from the OBS repo build (crystal1.21+ package)" bash -c "dpkg-query -W -f='\${Version}' crystal | grep -Eq '^1\.(2[1-9]|[3-9][0-9])'"
}

assert_main assert_apps
