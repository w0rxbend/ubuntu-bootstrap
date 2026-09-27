#!/usr/bin/env bash
# bootstrap.sh - run the Zorin OS 18 (Ubuntu 24.04 noble) workstation profiles with fluxion.
#
# Every module is a standalone fluxion WorkstationProfile under profiles/. This script runs them
# in a fixed order, and each one gets its own state name (--profile <short-name>). That way a
# module can be re-run on its own, and tools installed by an earlier module are visible to later
# ones, because every profile starts a new fluxion process.
#
#   ./bootstrap.sh                    # full default sequence (asks for the sudo password once)
#   ./bootstrap.sh --dry-run          # show what would run; no sudo, no changes
#   ./bootstrap.sh --only toolchains  # one module (default or optional)
#   ./bootstrap.sh --from shell       # resume the default sequence at a module
#   ./bootstrap.sh --list             # list modules
#   ./bootstrap.sh --only apps --tui  # fluxion's interactive selector/TUI (off by default)
#   ./bootstrap.sh --test --only gnome   # same orchestration on the generated test profiles
#                                        # (tests/generated: no logout checkpoint, state names test-*)
#
# The script never reads, stores or passes a password. It calls `sudo -v` once in your terminal
# and keeps that ticket warm while fluxion runs; fluxion itself only ever uses `sudo -n`.
set -euo pipefail

# --------------------------------------------------------------------------------------------
# Module tables (order matters). Short name = fluxion --profile state name.
# --------------------------------------------------------------------------------------------
DEFAULT_PROFILES=(
    "base:profiles/00-base.yaml:Ubuntu-archive packages, debconf preseeds, git config, clock, libvirtd"
    "apps:profiles/10-apps.yaml:gh, Claude Desktop, VS Code, 1Password, ChatGPT, fastfetch"
    "docker:profiles/20-docker.yaml:Docker CE from download.docker.com (replaces podman), distrobox"
    "toolchains:profiles/30-toolchains.yaml:rustup, cargo-binstall + crates, Go, SDKMAN, nvm, pnpm, pyenv, uv, ..."
    "binaries:profiles/40-binaries.yaml:binstaller tools in ~/.apps, nvim system links, Nerd Fonts"
    "shell:profiles/50-shell.yaml:oh-my-zsh + plugins, TPM, starship, kitty, ghostty"
    "desktop-apps:profiles/60-desktop-apps.yaml:flatpaks, snaps, Claude Code/Codex/Kimi CLIs, Zed, Paseo"
    "gnome:profiles/70-gnome.yaml:GNOME/Zorin workspaces and keybindings"
    "vicinae:profiles/75-vicinae.yaml:Vicinae launcher, user service, GNOME extension, Super+D toggle"
    "dotfiles:profiles/80-dotfiles.yaml:~/.system-bootstrap clone, dotbot-go links, skills, tmux plugins, broot"
    "session:profiles/90-session.yaml:zsh login shell, docker/libvirt/kvm groups, logout prompt"
)
OPTIONAL_PROFILES=(
    "obs:profiles/optional/obs.yaml:OBS Studio + plugins (flatpak)"
    "zorin-pro-parity:profiles/optional/zorin-pro-parity.yaml:the Zorin OS Pro flatpak set (for Core/reinstalls)"
    "gnome-extensions:profiles/optional/gnome-extensions.yaml:extra GNOME Shell extensions via gext -F"
    "wallpapers:profiles/optional/wallpapers.yaml:wallpapers from the old system-bootstrap repo"
    "post-checks:profiles/optional/post-checks.yaml:verification + manual-step reminders (after re-login)"
)

FLUXION_VERSION="${FLUXION_VERSION:-v0.3.1}"
FLUXION_INSTALL_URL="https://worxbend.github.io/fluxion.cr/install.sh"
EXPECTED_REPO_DIR="$HOME/.zorin-bootstrap"
STATE_DIR="$HOME/.local/share/fluxion/state"
EXIT_CHECKPOINT=75
EXIT_INTERRUPTED=130

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEST_PROFILES_DIR="tests/generated"

# --------------------------------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------------------------------
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_BOLD=$'\033[1m' C_DIM=$'\033[2m' C_RED=$'\033[31m' C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m' C_RESET=$'\033[0m'
else
    C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_RESET=''
fi

info() { printf '%s==>%s %s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$*"; }
ok() { printf '%s ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YELLOW$C_BOLD" "$C_RESET" "$*" >&2; }
err() { printf '%serror%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$*" >&2; }
die() {
    err "$*"
    exit 1
}

usage() {
    cat <<EOF
Usage: ./bootstrap.sh [MODE] [OPTIONS]

Runs the fluxion profiles in profiles/ in order (Zorin OS 18 / Ubuntu 24.04 noble).

Modes (default: apply):
  --dry-run          fluxion dry-run for each selected profile (no sudo, no changes)
  --validate         fluxion validate + lint for each selected profile only
  --plan             fluxion plan --format tree for each selected profile
  --status           fluxion status --summary for each selected profile (read-only probes)
  --failed           fluxion status --failed (missing/failed items) for each selected profile
  --list             list the modules and exit

Selection:
  --only a,b         run only these modules (default or optional short names), in table order
  --from NAME        start the default sequence at NAME (e.g. after fixing a failure)

Profiles and state (the orchestration is identical; only the files/state names change):
  --test             use the generated test profiles ($TEST_PROFILES_DIR, regenerated first by
                     tests/gen-test-profiles.sh: no logout checkpoint or manual/interrupt steps)
                     with state names 'test-NAME'
  --profiles-dir DIR read each module's profile from DIR instead of profiles/ (same relative
                     layout: DIR/00-base.yaml, DIR/optional/obs.yaml, ...)
  --state-prefix P   prefix for the fluxion state names (default: none; --test uses 'test-')
  --report FILE      append one line per module to FILE: name, rc, note, seconds, and fluxion's
                     Summary counts (ok, failed, skipped, would run) for apply/dry-run (tests/)

Pass-through to fluxion apply/dry-run:
  --yes, -y          approve items that declare confirm
  --tui              open fluxion's full-screen selector/TUI per module (apply only; press
                     enter to start and q to close; q at the selector skips the module)
  --no-tui           plain output (the default; accepted for compatibility)
  --show-output      echo each command's own output
  --re-probe         ignore recorded state and trust live probes only

  -h, --help         this help

Environment:
  FLUXION_BIN        fluxion executable to use (default: fluxion on PATH, installed if missing)
  FLUXION_VERSION    release to install when fluxion is missing (default: v0.3.1)

Default sequence: $(default_names | tr '\n' ' ')
Optional modules: $(optional_names | tr '\n' ' ')
EOF
}

# --------------------------------------------------------------------------------------------
# Table helpers
# --------------------------------------------------------------------------------------------
entry_name() { printf '%s' "${1%%:*}"; }
entry_file() {
    local rest="${1#*:}"
    printf '%s' "${rest%%:*}"
}
entry_desc() {
    local rest="${1#*:}"
    printf '%s' "${rest#*:}"
}
default_names() {
    local e
    for e in "${DEFAULT_PROFILES[@]}"; do entry_name "$e" && echo; done
}
optional_names() {
    local e
    for e in "${OPTIONAL_PROFILES[@]}"; do entry_name "$e" && echo; done
}
is_known() {
    local e
    for e in "${DEFAULT_PROFILES[@]}" "${OPTIONAL_PROFILES[@]}"; do
        [[ "$(entry_name "$e")" == "$1" ]] && return 0
    done
    return 1
}
is_default() {
    local e
    for e in "${DEFAULT_PROFILES[@]}"; do
        [[ "$(entry_name "$e")" == "$1" ]] && return 0
    done
    return 1
}

# Maps a table path (profiles/...) to the file actually used: PROFILES_DIR/... when --profiles-dir or
# --test is given. Always returns an absolute path.
profile_path() {
    local rel="${1#profiles/}"
    if [[ -n "$PROFILES_DIR" ]]; then
        printf '%s/%s' "$PROFILES_DIR" "$rel"
    else
        printf '%s/profiles/%s' "$REPO_DIR" "$rel"
    fi
}
display_path() { printf '%s' "${1#"$REPO_DIR"/}"; }

list_profiles() {
    local e name file mark
    printf '%sDefault sequence%s (./bootstrap.sh)\n' "$C_BOLD" "$C_RESET"
    local i=1
    for e in "${DEFAULT_PROFILES[@]}"; do
        name="$(entry_name "$e")"
        file="$(profile_path "$(entry_file "$e")")"
        mark=' '
        [[ -f "$file" ]] || mark='!'
        printf ' %2d %s %-18s %-40s %s%s%s\n' "$i" "$mark" "$name" "$(display_path "$file")" "$C_DIM" "$(entry_desc "$e")" "$C_RESET"
        i=$((i + 1))
    done
    printf '\n%sOptional%s (./bootstrap.sh --only NAME)\n' "$C_BOLD" "$C_RESET"
    for e in "${OPTIONAL_PROFILES[@]}"; do
        name="$(entry_name "$e")"
        file="$(profile_path "$(entry_file "$e")")"
        mark=' '
        [[ -f "$file" ]] || mark='!'
        printf '    %s %-18s %-40s %s%s%s\n' "$mark" "$name" "$(display_path "$file")" "$C_DIM" "$(entry_desc "$e")" "$C_RESET"
    done
    printf '\n%s! = profile file missing%s\n' "$C_DIM" "$C_RESET"
}

# --------------------------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------------------------
MODE=apply
ONLY=''
FROM=''
PASS_ARGS=()
USE_TUI=0
PROFILES_DIR=''
STATE_PREFIX=''
TEST_MODE=0
REPORT_FILE=''
LIST_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) MODE=dry-run ;;
        --validate) MODE=validate ;;
        --plan) MODE=plan ;;
        --status) MODE=status ;;
        --failed) MODE=failed ;;
        --list) LIST_ONLY=1 ;;
        --test) TEST_MODE=1 ;;
        --profiles-dir)
            [[ $# -ge 2 ]] || die "--profiles-dir needs a directory"
            PROFILES_DIR="$2"
            shift
            ;;
        --profiles-dir=*) PROFILES_DIR="${1#--profiles-dir=}" ;;
        --state-prefix)
            [[ $# -ge 2 ]] || die "--state-prefix needs a value"
            STATE_PREFIX="$2"
            shift
            ;;
        --state-prefix=*) STATE_PREFIX="${1#--state-prefix=}" ;;
        --report)
            [[ $# -ge 2 ]] || die "--report needs a file"
            REPORT_FILE="$2"
            shift
            ;;
        --report=*) REPORT_FILE="${1#--report=}" ;;
        --only)
            [[ $# -ge 2 ]] || die "--only needs a comma-separated list of modules"
            ONLY="$2"
            shift
            ;;
        --only=*) ONLY="${1#--only=}" ;;
        --from)
            [[ $# -ge 2 ]] || die "--from needs a module name"
            FROM="$2"
            shift
            ;;
        --from=*) FROM="${1#--from=}" ;;
        -y | --yes) PASS_ARGS+=(--yes) ;;
        --tui) USE_TUI=1 ;;
        --no-tui) USE_TUI=0 ;;
        --show-output) PASS_ARGS+=(--show-output) ;;
        --re-probe) PASS_ARGS+=(--re-probe) ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            err "unknown argument: $1"
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [[ -n "$ONLY" && -n "$FROM" ]]; then die "--only and --from cannot be combined"; fi

if [[ $TEST_MODE -eq 1 ]]; then
    [[ -n "$PROFILES_DIR" ]] || PROFILES_DIR="$TEST_PROFILES_DIR"
    [[ -n "$STATE_PREFIX" ]] || STATE_PREFIX="test-"
fi
if [[ -n "$PROFILES_DIR" ]]; then
    [[ "$PROFILES_DIR" == /* ]] || PROFILES_DIR="$REPO_DIR/$PROFILES_DIR"
    PROFILES_DIR="${PROFILES_DIR%/}"
fi
if [[ -n "$STATE_PREFIX" && ! "$STATE_PREFIX" =~ ^[A-Za-z0-9._-]+$ ]]; then
    die "--state-prefix may only contain letters, digits, '.', '_' and '-'"
fi
if [[ -n "$REPORT_FILE" && "$REPORT_FILE" != /* ]]; then REPORT_FILE="$PWD/$REPORT_FILE"; fi

# The test profiles are generated from profiles/ so they cannot drift: regenerate before every --test run.
if [[ $TEST_MODE -eq 1 && "$PROFILES_DIR" == "$REPO_DIR/$TEST_PROFILES_DIR" ]]; then
    "$REPO_DIR/tests/gen-test-profiles.sh" --quiet || die "tests/gen-test-profiles.sh failed"
fi

if [[ $LIST_ONLY -eq 1 ]]; then
    list_profiles
    exit 0
fi

# Build the selection (always in table order).
SELECTED=()
if [[ -n "$ONLY" ]]; then
    IFS=',' read -r -a wanted <<<"$ONLY"
    for w in "${wanted[@]}"; do
        w="${w// /}"
        [[ -z "$w" ]] && continue
        is_known "$w" || die "unknown module '$w' (see ./bootstrap.sh --list)"
    done
    for e in "${DEFAULT_PROFILES[@]}" "${OPTIONAL_PROFILES[@]}"; do
        n="$(entry_name "$e")"
        for w in "${wanted[@]}"; do
            if [[ "${w// /}" == "$n" ]]; then
                SELECTED+=("$e")
                break
            fi
        done
    done
elif [[ -n "$FROM" ]]; then
    is_default "$FROM" || die "--from must name a module of the default sequence (see --list)"
    started=0
    for e in "${DEFAULT_PROFILES[@]}"; do
        if [[ "$(entry_name "$e")" == "$FROM" ]]; then started=1; fi
        if [[ $started -eq 1 ]]; then SELECTED+=("$e"); fi
    done
else
    SELECTED=("${DEFAULT_PROFILES[@]}")
fi
[[ ${#SELECTED[@]} -gt 0 ]] || die "nothing selected"

# --------------------------------------------------------------------------------------------
# Preflight
# --------------------------------------------------------------------------------------------
if [[ "$(id -u)" -eq 0 ]]; then
    die "do not run this as root or with sudo; run it as your user (it asks for sudo itself)"
fi

if [[ "$REPO_DIR" != "$(cd "$EXPECTED_REPO_DIR" 2>/dev/null && pwd -P || echo "$EXPECTED_REPO_DIR")" ]]; then
    warn "repo is at $REPO_DIR, but the profiles hard-code repoDir=\$HOME/.zorin-bootstrap."
    warn "dotbot links will point at $EXPECTED_REPO_DIR. Move/clone the repo there for a correct run."
fi

if [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_TTY:-}" ]]; then
    warn "running over SSH: system flatpak installs (polkit) and gsettings need the local GNOME session."
    warn "the desktop-apps, gnome and gnome-extensions modules may fail; re-run them locally."
fi

if [[ -r /etc/os-release ]] && ! grep -q '^VERSION_CODENAME=noble' /etc/os-release; then
    warn "this host is not Ubuntu 24.04 'noble'-based; every profile's host-check will refuse to run."
fi

# PATH for fluxion: it inherits PATH once and never refreshes it, and `tool-packages` looks up
# its backends (cargo-binstall, pipx, ...) on this PATH. Export everything the modules install.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.go/bin:$HOME/.go-workspace/bin:$HOME/.apps/dotbot/bin:$HOME/.apps/neovim/bin:$HOME/.apps/yq/bin:$HOME/.apps/helm/bin:$HOME/.apps/kustomize/bin:$HOME/.local/share/pnpm/bin:$HOME/.juliaup/bin:$PATH"

if [[ -n "${FLUXION_BIN:-}" ]]; then
    [[ -x "$FLUXION_BIN" ]] || die "FLUXION_BIN=$FLUXION_BIN is not an executable file"
else
    if ! command -v fluxion >/dev/null 2>&1; then
        command -v curl >/dev/null 2>&1 || die "curl is required to install fluxion: sudo apt install -y curl"
        command -v tar >/dev/null 2>&1 || die "tar is required to install fluxion"
        info "fluxion not found; installing $FLUXION_VERSION to ~/.local/bin"
        curl --proto '=https' --tlsv1.2 -sSfL "$FLUXION_INSTALL_URL" | sh -s -- --version "$FLUXION_VERSION"
        hash -r
        command -v fluxion >/dev/null 2>&1 || die "fluxion install failed (expected ~/.local/bin/fluxion)"
    fi
    FLUXION_BIN="$(command -v fluxion)"
fi
# Scripts the profiles run (dotfiles-link.sh's dotbot fallback) use the same binary.
export FLUXION_BIN
FLUXION_VER_STR="$("$FLUXION_BIN" --version 2>/dev/null || echo 'fluxion ?')"
info "using $FLUXION_VER_STR ($FLUXION_BIN)"
if [[ -n "$PROFILES_DIR" ]]; then
    info "profiles from $(display_path "$PROFILES_DIR"); state names: ${STATE_PREFIX}NAME"
elif [[ -n "$STATE_PREFIX" ]]; then
    info "state names: ${STATE_PREFIX}NAME"
fi
case "$FLUXION_VER_STR" in
    *" ${FLUXION_VERSION#v}"*) ;;
    *) warn "this repo was written and tested against fluxion ${FLUXION_VERSION#v}; other versions may behave differently." ;;
esac

cd "$REPO_DIR"

# --------------------------------------------------------------------------------------------
# sudo: authenticate once, keep the ticket warm (apply mode only)
# --------------------------------------------------------------------------------------------
KEEPALIVE_PID=''
cleanup() {
    if [[ -n "$KEEPALIVE_PID" ]]; then
        kill "$KEEPALIVE_PID" 2>/dev/null || true
        wait "$KEEPALIVE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'echo; warn "interrupted"; exit $EXIT_INTERRUPTED' INT TERM

if [[ "$MODE" == apply ]]; then
    command -v sudo >/dev/null 2>&1 || die "sudo is required"
    # `sudo -n true` first: with a NOPASSWD rule plus the stock `%sudo ... ALL` rule, sudoers' default
    # verifypw=all makes `sudo -v` ask for a password although every `sudo -n CMD` works.
    if ! sudo -n true 2>/dev/null; then
        info "fluxion runs privileged steps with 'sudo -n'. Authenticate once (prompted by sudo itself):"
        sudo -v || die "sudo authentication failed"
    fi
    parent_pid=$$
    (
        # Running a command refreshes the ticket too, and also works where `sudo -n -v` is refused.
        while kill -0 "$parent_pid" 2>/dev/null; do
            sudo -n -v 2>/dev/null || sudo -n true 2>/dev/null || exit 0
            sleep 50
        done
    ) &
    KEEPALIVE_PID=$!
fi

# --------------------------------------------------------------------------------------------
# Run
# --------------------------------------------------------------------------------------------
RESULT_NAMES=()
RESULT_CODES=()
RESULT_NOTES=()
RESULT_SECS=()
FAILED=0
CHECKPOINT=''

record() {
    RESULT_NAMES+=("$1")
    RESULT_CODES+=("$2")
    RESULT_NOTES+=("$3")
    RESULT_SECS+=("$4")
    if [[ -n "$REPORT_FILE" ]]; then
        # name rc note seconds ok failed skipped would-run   (tab-separated; '-' = not applicable)
        local counts="$LAST_COUNTS"
        [[ -n "$counts" ]] || counts=$'-\t-\t-\t-'
        printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$counts" >>"$REPORT_FILE"
    fi
    LAST_COUNTS=''
}

# Reads fluxion's closing "Summary: N ok · N failed · N skipped [· N would run]" line from a log and
# prints "ok<TAB>failed<TAB>skipped<TAB>would-run".
summary_counts() {
    local line ok failed skipped would
    line="$(sed 's/\x1b\[[0-9;]*m//g' "$1" | grep -a '^Summary:' | tail -n1 || true)"
    [[ -n "$line" ]] || return 0
    ok="$(grep -Eo '[0-9]+ ok' <<<"$line" | grep -Eo '^[0-9]+' || echo 0)"
    failed="$(grep -Eo '[0-9]+ failed' <<<"$line" | grep -Eo '^[0-9]+' || echo 0)"
    skipped="$(grep -Eo '[0-9]+ skipped' <<<"$line" | grep -Eo '^[0-9]+' || echo 0)"
    would="$(grep -Eo '[0-9]+ would run' <<<"$line" | grep -Eo '^[0-9]+' || echo 0)"
    printf '%s\t%s\t%s\t%s' "$ok" "$failed" "$skipped" "$would"
}
LAST_COUNTS=''

run_profile() {
    # $1 = entry; sets global LAST_RC
    local name file rc=0 started
    name="$(entry_name "$1")"
    file="$(profile_path "$(entry_file "$1")")"
    local state="${STATE_PREFIX}${name}"
    started=$SECONDS
    LAST_RC=0

    printf '\n%s━━━ %s%s  %s(%s)%s\n' "$C_BOLD" "$name" "$C_RESET" "$C_DIM" "$(display_path "$file")" "$C_RESET"

    if [[ ! -f "$file" ]]; then
        err "$file not found"
        LAST_RC=4
        record "$name" 4 "missing file" 0
        return
    fi

    case "$MODE" in
        validate)
            "$FLUXION_BIN" validate -c "$file" --strict --no-tui || rc=$?
            if [[ $rc -eq 0 ]]; then
                "$FLUXION_BIN" lint -c "$file" --no-tui || true
                record "$name" 0 "valid" $((SECONDS - started))
            else
                record "$name" "$rc" "invalid" $((SECONDS - started))
            fi
            LAST_RC=$rc
            return
            ;;
        plan)
            "$FLUXION_BIN" plan -c "$file" --format tree --no-tui || rc=$?
            record "$name" "$rc" "$([[ $rc -eq 0 ]] && echo planned || echo 'plan failed')" $((SECONDS - started))
            LAST_RC=$rc
            return
            ;;
        status | failed)
            local flag=--summary
            [[ "$MODE" == failed ]] && flag=--failed
            "$FLUXION_BIN" status -c "$file" --profile "$state" "$flag" --no-tui || rc=$?
            record "$name" "$rc" "$([[ $rc -eq 0 ]] && echo probed || echo 'status failed')" $((SECONDS - started))
            LAST_RC=$rc
            return
            ;;
    esac

    # apply / dry-run: validate first (exit 3 = invalid profile, skip it)
    "$FLUXION_BIN" validate -c "$file" --no-tui >/dev/null 2>&1 || rc=$?
    if [[ $rc -ne 0 ]]; then
        err "$file does not validate (rc=$rc); skipping. Details: fluxion validate -c $file"
        record "$name" "$rc" "invalid profile" $((SECONDS - started))
        LAST_RC=$rc
        return
    fi

    local sub=apply
    [[ "$MODE" == dry-run ]] && sub=dry-run
    local cmd=("$FLUXION_BIN" "$sub" -c "$file" --profile "$state" --skip-already-installed)
    # Plain output by default so the sequence runs unattended. The TUI waits for enter/q per
    # module, and backing out of its selector exits 0, which would be reported as "ok".
    if [[ "$MODE" == dry-run || $USE_TUI -eq 0 ]]; then
        cmd+=(--no-tui)
    fi
    if [[ ${#PASS_ARGS[@]} -gt 0 ]]; then
        cmd+=("${PASS_ARGS[@]}")
    fi
    printf '%s$ %s%s\n' "$C_DIM" "${cmd[*]}" "$C_RESET"
    if [[ -n "$REPORT_FILE" && ( "$MODE" == dry-run || $USE_TUI -eq 0 ) ]]; then
        # Keep fluxion's output on screen and read its Summary line afterwards.
        local log
        log="$(mktemp)"
        "${cmd[@]}" 2>&1 | tee "$log" || true
        rc=${PIPESTATUS[0]}
        LAST_COUNTS="$(summary_counts "$log")"
        rm -f "$log"
    else
        "${cmd[@]}" || rc=$?
    fi

    local note
    case $rc in
        0) note="ok" ;;
        "$EXIT_CHECKPOINT") note="checkpoint (log out/in)" ;;
        "$EXIT_INTERRUPTED") note="interrupted" ;;
        3) note="invalid profile" ;;
        *) note="failed" ;;
    esac
    record "$name" "$rc" "$note" $((SECONDS - started))
    LAST_RC=$rc
}

info "mode: $MODE; modules: $(for e in "${SELECTED[@]}"; do printf '%s ' "$(entry_name "$e")"; done)"

LAST_RC=0
for e in "${SELECTED[@]}"; do
    run_profile "$e"
    case $LAST_RC in
        0) ;;
        "$EXIT_CHECKPOINT")
            CHECKPOINT="$(entry_name "$e")"
            break
            ;;
        "$EXIT_INTERRUPTED")
            FAILED=$((FAILED + 1))
            warn "fluxion was interrupted; stopping."
            break
            ;;
        *)
            FAILED=$((FAILED + 1))
            if [[ "$MODE" == apply || "$MODE" == dry-run ]]; then
                warn "$(entry_name "$e") failed (rc=$LAST_RC); continuing with the next module."
            fi
            ;;
    esac
done

# --------------------------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------------------------
printf '\n%sSummary (%s)%s\n' "$C_BOLD" "$MODE" "$C_RESET"
printf '  %-18s %4s  %7s  %s\n' "module" "rc" "time" "result"
for i in "${!RESULT_NAMES[@]}"; do
    rc="${RESULT_CODES[$i]}"
    colour="$C_GREEN"
    [[ "$rc" -eq "$EXIT_CHECKPOINT" ]] && colour="$C_YELLOW"
    [[ "$rc" -ne 0 && "$rc" -ne "$EXIT_CHECKPOINT" ]] && colour="$C_RED"
    secs="${RESULT_SECS[$i]}"
    printf '  %-18s %4s  %4dm%02ds  %s%s%s\n' "${RESULT_NAMES[$i]}" "$rc" $((secs / 60)) $((secs % 60)) "$colour" "${RESULT_NOTES[$i]}" "$C_RESET"
done

if [[ ${#RESULT_NAMES[@]} -lt ${#SELECTED[@]} ]]; then
    printf '  %s(%d module(s) not run)%s\n' "$C_DIM" $((${#SELECTED[@]} - ${#RESULT_NAMES[@]})) "$C_RESET"
fi

if [[ -n "$CHECKPOINT" ]]; then
    echo
    if [[ "$MODE" == dry-run ]]; then
        info "dry-run stopped at the '$CHECKPOINT' logout checkpoint (expected: it is the last module)."
    else
        info "Checkpoint reached in '$CHECKPOINT'. Log out and back in (or reboot) so the new groups"
        info "(docker, libvirt, kvm) and the zsh login shell take effect, then run:"
        printf '      cd %s && ./bootstrap.sh --only post-checks\n' "$REPO_DIR"
    fi
fi

if [[ $FAILED -gt 0 ]]; then
    RERUN_FLAG=''
    [[ $TEST_MODE -eq 1 ]] && RERUN_FLAG='--test '
    echo
    err "$FAILED module(s) failed. To investigate one (NAME = module, FILE = its profile):"
    cat >&2 <<EOF
      fluxion status  -c FILE --profile ${STATE_PREFIX}NAME --failed
      fluxion explain -c FILE --profile ${STATE_PREFIX}NAME --phase PHASE
      fluxion state show ${STATE_PREFIX}NAME            # recorded state: $STATE_DIR/${STATE_PREFIX}NAME.json
    Fix the cause and re-run the module: ./bootstrap.sh ${RERUN_FLAG}--only NAME
    (or resume the sequence: ./bootstrap.sh ${RERUN_FLAG}--from NAME). Finished items are skipped.
EOF
    exit 1
fi

if [[ "$MODE" == apply && -z "$CHECKPOINT" ]]; then
    ok "all selected modules finished."
fi
exit 0
