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
# This repo needs fixes that are not in a fluxion release yet (fluxion.cr branch fix/zorin-bootstrap; see
# "fluxion.cr patches" in README.md). A stock 0.3.1 prints the same `fluxion 0.3.1`, so the version string cannot
# tell them apart; fluxion_check_capable reads the build's binstaller pin instead: fix/zorin-bootstrap pins
# binstaller v0.5.0 (8065313), fluxion 0.3.1 as released pins v0.2.0, which cannot unpack zig 0.15.2. The same
# branch carries the apt probe, prompt-logout and assert fixes, so the pin stands for all of them.

FLUXION_REQUIRED_BRANCH="fix/zorin-bootstrap"
FLUXION_MIN_BINSTALLER="0.3.0"

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

# fluxion_check_capable BIN  - 0 when BIN is a build with the fixes this repo needs; otherwise prints why
fluxion_check_capable() {
    local bin="$1" pin
    pin="$(fluxion_binstaller_pin "$bin")"
    if [[ -z "$pin" ]]; then
        echo "could not read the binstaller pin from '$bin tools list'"
        return 1
    fi
    if [[ "$(printf '%s\n%s\n' "$FLUXION_MIN_BINSTALLER" "$pin" | sort -V | head -n1)" != "$FLUXION_MIN_BINSTALLER" ]]; then
        echo "$bin pins binstaller v$pin (< v$FLUXION_MIN_BINSTALLER): it is a fluxion without the $FLUXION_REQUIRED_BRANCH fixes"
        return 1
    fi
    return 0
}

# fluxion_help_capable  - what to do about a binary without the fixes
fluxion_help_capable() {
    cat <<HELP
  This repo needs a fluxion build with the fixes on fluxion.cr branch $FLUXION_REQUIRED_BRANCH (or a fluxion
  release that includes them; see "fluxion.cr patches" in README.md). Point the repo at such a build:
      just use-fluxion /path/to/fluxion        # writes fluxion-bin.local (git-ignored), used by every script
  or  FLUXION_BIN=/path/to/fluxion ./bootstrap.sh ...
  To run with this binary anyway (known failures: binaries/zig, apt probes, logout checkpoint), set
  FLUXION_ALLOW_UNPATCHED=1.
HELP
}
