#!/usr/bin/env bash
# Post-conditions of profiles/30-toolchains.yaml (module "toolchains"): user-level language toolchains.
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_toolchains() {
    ASSERT_MODULE=toolchains
    section "Rust"
    assert_exec "$HOME/.cargo/bin/rustup" '^rustup [0-9]'
    assert_exec "$HOME/.cargo/bin/cargo" '^cargo [0-9]'
    assert_exec "$HOME/.cargo/bin/rustc" '^rustc [0-9]'
    # cargo-binstall's --version takes a value (a crate version); -V prints its own version.
    assert_exec "$HOME/.cargo/bin/cargo-binstall" '^[0-9]+\.[0-9]+' -V

    section "crates (cargo-binstall), by the binary each one provides"
    local crate bin
    while read -r crate; do
        case "$crate" in
            fd-find) bin=fd ;;
            du-dust) bin=dust ;;
            tree-sitter-cli) bin=tree-sitter ;;
            bottom) bin=btm ;;
            *) bin="$crate" ;;
        esac
        assert_exec "$HOME/.cargo/bin/$bin"
    done < <(profile_query 30-toolchains.yaml crates)

    section "Go"
    local gover
    gover="$(sed -n 's/^ *goVersion: *"\{0,1\}\([0-9.]*\)"\{0,1\}.*/\1/p' "$ASSERT_REPO_DIR/profiles/30-toolchains.yaml" | head -n1)"
    assert_exec "$HOME/.go/bin/go" "go${gover//./\\.} " version

    section "JVM (SDKMAN)"
    check "sdkman-init.sh present" test -s "$HOME/.sdkman/bin/sdkman-init.sh"
    check_sh "sdkman_auto_answer=true" "grep -q '^sdkman_auto_answer=true' \$HOME/.sdkman/etc/config"
    local cand
    while read -r cand; do
        check "SDKMAN candidate $cand has a default (candidates/$cand/current)" test -e "$HOME/.sdkman/candidates/$cand/current"
    done < <(profile_query 30-toolchains.yaml sdkman)
    check "java runs" bash -c "\"\$HOME/.sdkman/candidates/java/current/bin/java\" -version"

    section "Node"
    check "nvm installed" test -s "$HOME/.nvm/nvm.sh"
    check "nvm default is an LTS node that runs" bash -c '. "$HOME/.nvm/nvm.sh" && node --version && nvm which default >/dev/null'
    assert_exec "$HOME/.local/share/pnpm/bin/pnpm" '^[0-9]+\.'

    section "Python"
    assert_exec "$HOME/.pyenv/bin/pyenv" '^pyenv [0-9]'
    assert_exec "$HOME/.local/bin/poetry" 'Poetry'
    assert_exec "$HOME/.local/bin/uv" '^uv [0-9]'
    assert_exec "$HOME/.miniforge3/bin/conda" '^conda [0-9]'

    section "Julia, Kubernetes CLIs, dotenvx"
    assert_exec "$HOME/.juliaup/bin/juliaup" 'Juliaup'
    assert_exec "$HOME/.apps/kustomize/bin/kustomize" 'v?[0-9]+\.' version
    assert_exec "$HOME/.apps/helm/bin/helm" 'v4\.' version --short
    assert_exec "$HOME/.local/bin/dotenvx" '[0-9]+\.[0-9]+'
}

assert_main assert_toolchains
