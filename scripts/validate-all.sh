#!/usr/bin/env bash
# validate-all.sh - read-only quality gate for every fluxion profile in this repo.
#
# For each profiles/*.yaml and profiles/optional/*.yaml it runs:
#   fluxion validate -c FILE --strict   (must exit 0; warnings count as failures)
#   fluxion lint     -c FILE            (advisory; prints the score and findings)
# Also syntax-checks the repo's shell scripts with `bash -n` (and shellcheck -S error if it is
# installed). Exits non-zero when any profile fails validation or any script fails the syntax check.
#
#   scripts/validate-all.sh            # everything
#   scripts/validate-all.sh -q         # only the summary and failures (lint output hidden)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_DIR"

QUIET=0
case "${1:-}" in
    -q | --quiet) QUIET=1 ;;
    -h | --help)
        sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    '') ;;
    *)
        echo "unknown argument: $1" >&2
        exit 2
        ;;
esac

# Same PATH as bootstrap.sh, so profiles resolve identically.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.go/bin:$HOME/.go-workspace/bin:$HOME/.apps/dotbot/bin:$HOME/.apps/neovim/bin:$HOME/.apps/yq/bin:$HOME/.local/share/pnpm:$HOME/.juliaup/bin:$PATH"

if ! command -v fluxion >/dev/null 2>&1; then
    echo "fluxion is not installed; run ./bootstrap.sh --validate (it installs fluxion) or see README.md" >&2
    exit 1
fi

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m' BOLD=$'\033[1m' RESET=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' BOLD='' RESET=''
fi

shopt -s nullglob
files=(profiles/*.yaml profiles/optional/*.yaml)
if [[ ${#files[@]} -eq 0 ]]; then
    echo "no profiles found under profiles/" >&2
    exit 1
fi

declare -a rows=()
failures=0

for f in "${files[@]}"; do
    printf '%s━━━ %s%s\n' "$BOLD" "$f" "$RESET"
    vrc=0
    vout="$(fluxion validate -c "$f" --strict --no-tui 2>&1)" || vrc=$?
    if [[ $vrc -eq 0 ]]; then
        printf '  %svalidate --strict: ok%s\n' "$GREEN" "$RESET"
    else
        printf '  %svalidate --strict: FAILED (rc=%d)%s\n' "$RED" "$vrc" "$RESET"
        printf '%s\n' "$vout" | sed 's/^/    /'
        failures=$((failures + 1))
    fi

    lrc=0
    lout="$(fluxion lint -c "$f" --no-tui 2>&1)" || lrc=$?
    score="$(printf '%s\n' "$lout" | grep -Eo '[0-9]+ ?/ ?100' | head -n1 || true)"
    [[ -n "$score" ]] || score="-"
    if [[ $QUIET -eq 0 ]]; then
        printf '%s\n' "$lout" | sed 's/^/    /'
    fi
    if [[ $lrc -ne 0 ]]; then
        printf '  %slint exited %d%s\n' "$YELLOW" "$lrc" "$RESET"
    fi

    rows+=("$(printf '%-44s %-8s %s' "$f" "$([[ $vrc -eq 0 ]] && echo ok || echo "FAIL:$vrc")" "$score")")
done

# Shell scripts: syntax (and shellcheck errors when available).
printf '%s━━━ shell scripts%s\n' "$BOLD" "$RESET"
scripts=(bootstrap.sh scripts/*.sh dotfiles/*.sh)
for s in "${scripts[@]}"; do
    [[ -f "$s" ]] || continue
    src=0
    if ! sout="$(bash -n "$s" 2>&1)"; then
        src=1
        printf '%s\n' "$sout" | sed 's/^/    /'
    fi
    if [[ $src -eq 0 ]] && command -v shellcheck >/dev/null 2>&1; then
        shellcheck -S error "$s" || src=$?
    fi
    if [[ $src -eq 0 ]]; then
        printf '  %sok%s   %s\n' "$GREEN" "$RESET" "$s"
    else
        printf '  %sFAIL%s %s\n' "$RED" "$RESET" "$s"
        failures=$((failures + 1))
    fi
done
command -v shellcheck >/dev/null 2>&1 || printf '  (shellcheck not installed; only bash -n was run)\n'

printf '\n%sSummary%s\n' "$BOLD" "$RESET"
printf '  %-44s %-8s %s\n' "profile" "validate" "lint score"
for r in "${rows[@]}"; do printf '  %s\n' "$r"; done

if [[ $failures -gt 0 ]]; then
    printf '\n%s%d check(s) failed.%s\n' "$RED" "$failures" "$RESET"
    exit 1
fi
printf '\n%sAll %d profiles validate (--strict).%s\n' "$GREEN" "${#files[@]}" "$RESET"
