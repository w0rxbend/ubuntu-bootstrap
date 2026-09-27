#!/usr/bin/env bash
# Post-conditions of profiles/20-docker.yaml (module "docker"): Docker CE, not podman.
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_docker() {
    ASSERT_MODULE=docker
    section "repository"
    assert_file_contains /etc/apt/sources.list.d/docker.list \
        "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable"
    check "docker.gpg carries Docker's key 9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88" \
        bash -c "gpg --show-keys --with-colons /etc/apt/keyrings/docker.gpg 2>/dev/null | grep -q '^fpr:::::::::9DC858229FC7DD38854AE2D88D81803C0EBFCD88:'"

    section "packages"
    mapfile -t pkgs < <(profile_query 20-docker.yaml apt-packages)
    assert_pkgs "docker" "${pkgs[@]}"
    assert_no_pkgs "no podman / distro docker packages" docker.io docker-doc docker-compose docker-compose-v2 podman-docker podman containerd runc
    check_sh "podman is not installed" '! command -v podman'

    section "engine"
    assert_unit docker
    assert_unit containerd
    assert_cmd docker '^Docker version [0-9]'
    check "docker compose v2 plugin" docker compose version
    check "docker buildx plugin" docker buildx version
    if ! has_systemd; then
        skip "docker run hello-world" "no systemd/dockerd here"
    elif ! has_network; then
        skip "docker run hello-world" "ASSERT_NETWORK=0"
    elif id -nG | grep -qw docker; then
        check "docker run --rm hello-world (as $USER, docker group active)" docker run --rm hello-world
    elif can_sudo; then
        check "sudo docker run --rm hello-world (docker group needs a re-login)" sudo -n docker run --rm hello-world
    else
        skip "docker run hello-world" "not in the docker group yet and no sudo ticket"
    fi

    section "distrobox"
    assert_exec "$HOME/.local/bin/distrobox" 'distrobox: 1\.8\.2\.5' version
}

assert_main assert_docker
