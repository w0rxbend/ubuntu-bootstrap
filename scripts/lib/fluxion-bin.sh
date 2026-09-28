# shellcheck shell=bash
# shellcheck disable=SC2034  # FLUXION_* are set here for the scripts that source this file
# scripts/lib/fluxion-bin.sh - which fluxion this repo runs, answered in ONE place (sourced, not executed).
#
# bootstrap.sh, tests/run-tests.sh and scripts/validate-all.sh all resolve the binary here, so the build the
# tests exercise is the build a real bootstrap runs. Order:
#   1. $FLUXION_BIN, when set
#   2. the path in fluxion-bin.local at the repo root (git-ignored, one line; `just use-fluxion PATH` writes it)
#   3. fluxion on PATH
# Nothing found -> empty; bootstrap.sh then installs the fluxion release.
#
# This repo needs fluxion >= 0.4.1. 0.4.0 released this repo's fix/zorin-bootstrap fixes (apt probes, one
# apt-get per package list, assert re-checks, apt-source and keyring checks, cargo/SDKMAN probes, binstaller
# v0.5.0, prompt-logout, flatpak extensions); 0.4.1 added what Ubuntu 26.04 needed: privileged commands that are
# symlinks into /usr/lib/cargo (Rust coreutils' install/chown), a probeCommand on the kinds 0.4.0 gave typed
# probes, and waiting out an apt lock another process holds. fluxion_check_capable compares `fluxion --version`
# with FLUXION_MIN_VERSION; FLUXION_ALLOW_UNPATCHED=1 lets an older build run anyway.

FLUXION_MIN_VERSION="0.4.1"

# fluxion_resolve REPO_DIR  - sets FLUXION_RESOLVED (the binary to use, or empty) and FLUXION_BIN_SOURCE
# (env | local | path | none). Sets variables rather than printing, so the caller keeps both without a subshell.
fluxion_resolve() {
    local local_file="$1/fluxion-bin.local" candidate
    FLUXION_RESOLVED=''
    FLUXION_BIN_SOURCE=none
    if [[ -n "${FLUXION_BIN:-}" ]]; then
        FLUXION_RESOLVED="$FLUXION_BIN"
        FLUXION_BIN_SOURCE="env"
        return 0
    fi
    if [[ -f "$local_file" ]]; then
        candidate="$(sed -n '/^[[:space:]]*[^#[:space:]]/{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q}' "$local_file")"
        candidate="${candidate/#\~/$HOME}"
        if [[ -n "$candidate" ]]; then
            FLUXION_RESOLVED="$candidate"
            FLUXION_BIN_SOURCE="fluxion-bin.local"
            return 0
        fi
    fi
    if candidate="$(command -v fluxion 2>/dev/null)" && [[ -n "$candidate" ]]; then
        FLUXION_RESOLVED="$candidate"
        FLUXION_BIN_SOURCE="PATH"
    fi
    return 0
}

# fluxion_binstaller_pin BIN  - the binstaller version BIN pins (e.g. 0.5.0), or nothing
fluxion_binstaller_pin() {
    "$1" tools list 2>/dev/null | awk '$1 == "binstaller" { v = $2; sub(/^v/, "", v); print v; exit }'
}

# fluxion_version BIN  - the version BIN prints (e.g. 0.4.1), or nothing
fluxion_version() {
    "$1" --version 2>/dev/null | awk '$1 == "fluxion" { print $2; exit }'
}

# fluxion_check_capable BIN  - 0 when BIN is fluxion >= FLUXION_MIN_VERSION; otherwise prints why
fluxion_check_capable() {
    local bin="$1" version
    version="$(fluxion_version "$bin")"
    if [[ -z "$version" ]]; then
        echo "could not read the version from '$bin --version'"
        return 1
    fi
    if [[ "$(printf '%s\n%s\n' "$FLUXION_MIN_VERSION" "$version" | sort -V | head -n1)" != "$FLUXION_MIN_VERSION" ]]; then
        echo "$bin is fluxion $version; this repo needs $FLUXION_MIN_VERSION or later"
        return 1
    fi
    return 0
}

# fluxion_help_capable  - what to do about a binary that is too old
fluxion_help_capable() {
    cat <<HELP
  This repo needs fluxion $FLUXION_MIN_VERSION or later (see "fluxion version" in README.md). Install the release:
      curl --proto '=https' --tlsv1.2 -sSfL https://worxbend.github.io/fluxion.cr/install.sh | sh -s -- --version v$FLUXION_MIN_VERSION
  (./bootstrap.sh does this itself when no fluxion is found), and delete fluxion-bin.local if it points at an
  older build. To run another build: just use-fluxion /path/to/fluxion, or FLUXION_BIN=/path/to/fluxion.
  To run with this binary anyway, set FLUXION_ALLOW_UNPATCHED=1.
HELP
}
