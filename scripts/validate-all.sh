#!/usr/bin/env bash
# validate-all.sh - read-only quality gate for every fluxion profile and script in this repo.
#
#   1. regenerates tests/generated/ (tests/gen-test-profiles.sh), then for every profile in profiles/ AND every
#      generated test profile: fluxion validate --strict (must exit 0) and fluxion lint (advisory)
#   2. shell scripts (bootstrap.sh, scripts/, tests/, dotfiles/): bash -n (sh -n for POSIX sh scripts) and a
#      `shellcheck -S warning` pass; zsh -n for dotfiles/custom.zsh
#   3. every inline shell snippet inside the profiles (shell-scripts content, commands, unless, probeCommand,
#      assert command): bash -n and shellcheck -S warning
# Exits non-zero when anything fails. Needs python3 + PyYAML; shellcheck is used when installed.
#
#   scripts/validate-all.sh            # everything
#   scripts/validate-all.sh -q         # only the summary and failures (lint output hidden)
# Environment: FLUXION_BIN (default: scripts/lib/fluxion-bin.sh: fluxion-bin.local, else fluxion on PATH).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_DIR"

QUIET=0
case "${1:-}" in
    -q | --quiet) QUIET=1 ;;
    -h | --help)
        sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    '') ;;
    *)
        echo "unknown argument: $1" >&2
        exit 2
        ;;
esac

# Same PATH as bootstrap.sh, so profiles resolve identically.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.go/bin:$HOME/.go-workspace/bin:$HOME/.apps/dotbot/bin:$HOME/.apps/neovim/bin:$HOME/.apps/yq/bin:$HOME/.apps/helm/bin:$HOME/.apps/kustomize/bin:$HOME/.local/share/pnpm/bin:$HOME/.juliaup/bin:$PATH"

# shellcheck source=scripts/lib/fluxion-bin.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/fluxion-bin.sh"
fluxion_resolve "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FLUXION_BIN="$FLUXION_RESOLVED"
if [[ -z "$FLUXION_BIN" || ! -x "$FLUXION_BIN" ]]; then
    echo "fluxion is not installed; run ./bootstrap.sh --validate (it installs fluxion) or see README.md" >&2
    exit 1
fi

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m' BOLD=$'\033[1m' RESET=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' BOLD='' RESET=''
fi

failures=0
declare -a rows=()

# ---- 1. profiles ------------------------------------------------------------------------------------------------
tests/gen-test-profiles.sh --quiet

shopt -s nullglob
files=(profiles/*.yaml profiles/optional/*.yaml tests/generated/*.yaml tests/generated/optional/*.yaml)
if [[ ${#files[@]} -eq 0 ]]; then
    echo "no profiles found under profiles/" >&2
    exit 1
fi

printf '%susing %s (%s)%s\n' "$BOLD" "$("$FLUXION_BIN" --version 2>/dev/null)" "$FLUXION_BIN" "$RESET"
for f in "${files[@]}"; do
    printf '%s━━━ %s%s\n' "$BOLD" "$f" "$RESET"
    vrc=0
    vout="$("$FLUXION_BIN" validate -c "$f" --strict --no-tui 2>&1)" || vrc=$?
    if [[ $vrc -eq 0 ]]; then
        printf '  %svalidate --strict: ok%s\n' "$GREEN" "$RESET"
    else
        printf '  %svalidate --strict: FAILED (rc=%d)%s\n' "$RED" "$vrc" "$RESET"
        printf '%s\n' "$vout" | sed 's/^/    /'
        failures=$((failures + 1))
    fi

    lrc=0
    lout="$("$FLUXION_BIN" lint -c "$f" --no-tui 2>&1)" || lrc=$?
    score="$(printf '%s\n' "$lout" | grep -Eo '[0-9]+ ?/ ?100' | head -n1 || true)"
    [[ -n "$score" ]] || score="-"
    if [[ $QUIET -eq 0 ]]; then
        printf '%s\n' "$lout" | sed 's/^/    /'
    fi
    if [[ $lrc -ne 0 ]]; then
        printf '  %slint exited %d%s\n' "$YELLOW" "$lrc" "$RESET"
    fi

    rows+=("$(printf '%-48s %-8s %s' "$f" "$([[ $vrc -eq 0 ]] && echo ok || echo "FAIL:$vrc")" "$score")")
done

# ---- 2. shell scripts -------------------------------------------------------------------------------------------
printf '%s━━━ shell scripts%s\n' "$BOLD" "$RESET"
have_shellcheck=0
command -v shellcheck >/dev/null 2>&1 && have_shellcheck=1

check_script() {
    # check_script FILE DIALECT(bash|sh)
    local s="$1" dialect="$2" out rc=0
    if ! out="$("$dialect" -n "$s" 2>&1)"; then
        rc=1
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
    if [[ $rc -eq 0 && $have_shellcheck -eq 1 ]]; then
        shellcheck -x -S warning -s "$dialect" "$s" || rc=1
    fi
    if [[ $rc -eq 0 ]]; then
        [[ $QUIET -eq 1 ]] || printf '  %sok%s   %s\n' "$GREEN" "$RESET" "$s"
    else
        printf '  %sFAIL%s %s\n' "$RED" "$RESET" "$s"
        failures=$((failures + 1))
    fi
}

scripts=(bootstrap.sh scripts/*.sh tests/*.sh tests/assertions/*.sh dotfiles/*.sh)
for s in "${scripts[@]}"; do
    [[ -f "$s" ]] || continue
    if head -n1 "$s" | grep -q '^#!/bin/sh'; then
        check_script "$s" sh
    else
        check_script "$s" bash
    fi
done
if command -v zsh >/dev/null 2>&1; then
    if zsh -n dotfiles/custom.zsh; then
        [[ $QUIET -eq 1 ]] || printf '  %sok%s   dotfiles/custom.zsh (zsh -n)\n' "$GREEN" "$RESET"
    else
        printf '  %sFAIL%s dotfiles/custom.zsh (zsh -n)\n' "$RED" "$RESET"
        failures=$((failures + 1))
    fi
fi

# ---- 3. inline snippets in the profiles -------------------------------------------------------------------------
printf '%s━━━ inline shell snippets in profiles/%s\n' "$BOLD" "$RESET"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mapfile -t snippets < <(python3 tests/lib/extract_inline_scripts.py "$tmp" profiles/*.yaml profiles/optional/*.yaml)
bad=0
for s in "${snippets[@]}"; do
    if ! bash -n "$s" 2>"$tmp/err"; then
        printf '  %sFAIL%s %s\n' "$RED" "$RESET" "$(sed -n '2s/^# from //p' "$s")"
        sed 's/^/    /' "$tmp/err"
        bad=$((bad + 1))
    elif [[ $have_shellcheck -eq 1 ]] && ! out="$(shellcheck -S warning "$s" 2>&1)"; then
        printf '  %sFAIL%s %s\n' "$RED" "$RESET" "$(sed -n '2s/^# from //p' "$s")"
        printf '%s\n' "$out" | sed 's/^/    /'
        bad=$((bad + 1))
    fi
done
if [[ $bad -eq 0 ]]; then
    printf '  %sok%s   %d snippets\n' "$GREEN" "$RESET" "${#snippets[@]}"
else
    failures=$((failures + bad))
fi
[[ $have_shellcheck -eq 1 ]] || printf '  (shellcheck not installed; only syntax checks were run: sudo apt install -y shellcheck)\n'

# ---- summary ----------------------------------------------------------------------------------------------------
printf '\n%sSummary%s\n' "$BOLD" "$RESET"
printf '  %-48s %-8s %s\n' "profile" "validate" "lint score"
for r in "${rows[@]}"; do printf '  %s\n' "$r"; done

if [[ $failures -gt 0 ]]; then
    printf '\n%s%d check(s) failed.%s\n' "$RED" "$failures" "$RESET"
    exit 1
fi
printf '\n%sAll %d profiles validate (--strict); scripts and inline snippets pass.%s\n' "$GREEN" "${#files[@]}" "$RESET"
