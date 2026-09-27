# shellcheck shell=bash
# tests/assertions/lib.sh - helpers shared by the post-condition assertions (sourced, not executed).
#
# Every assertion checks the REAL outcome on the host (a binary runs and reports the pinned version, a link
# resolves into the right repo, gsettings holds the right value, a service is active, docker runs a container),
# never fluxion's own bookkeeping.
#
# Each module file (tests/assertions/<module>.sh) can be run on its own:
#   tests/assertions/docker.sh             # prints ok/FAIL/skip lines, exits 1 when anything failed
# or through tests/run-tests.sh, which sources them in module order.
#
# Environment:
#   ASSERT_CONTEXT=host|container   container: skip checks that need systemd, snapd, flatpak or a GNOME session
#   ASSERT_NETWORK=0                skip checks that need the network (docker pull, apt-get update, ls-remote)
#   ASSERT_VERBOSE=1                print the command output of failed checks
#   ASSERT_LIVE_INPUT=1             gnome: also press Super+3 / Super+1 through /dev/uinput (sudo) and check that
#                                   mutter really switches workspace (off by default: it injects keys)

ASSERT_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
ASSERT_CONTEXT="${ASSERT_CONTEXT:-host}"
ASSERT_NETWORK="${ASSERT_NETWORK:-1}"
ASSERT_VERBOSE="${ASSERT_VERBOSE:-0}"
: "${ASSERT_PASS:=0}" "${ASSERT_FAIL:=0}" "${ASSERT_SKIP:=0}"
ASSERT_MODULE="${ASSERT_MODULE:-?}"

# The same PATH bootstrap.sh gives fluxion, plus the places the installers put binaries.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.go/bin:$HOME/.go-workspace/bin:$HOME/.apps/dotbot/bin:$HOME/.apps/neovim/bin:$HOME/.apps/yq/bin:$HOME/.apps/helm/bin:$HOME/.apps/kustomize/bin:$HOME/.local/share/pnpm/bin:$HOME/.juliaup/bin:$HOME/.kimi-code/bin:$HOME/.local/kitty.app/bin:/usr/local/bin:$PATH"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    _A_G=$'\033[32m' _A_R=$'\033[31m' _A_Y=$'\033[33m' _A_D=$'\033[2m' _A_0=$'\033[0m'
else
    _A_G='' _A_R='' _A_Y='' _A_D='' _A_0=''
fi

_a_ok() {
    ASSERT_PASS=$((ASSERT_PASS + 1))
    printf '  %sok%s    %s\n' "$_A_G" "$_A_0" "$1"
}
_a_fail() {
    ASSERT_FAIL=$((ASSERT_FAIL + 1))
    printf '  %sFAIL%s  %s\n' "$_A_R" "$_A_0" "$1"
    if [[ -n "${2:-}" ]]; then printf '%s\n' "$2" | sed "s/^/        ${_A_D}/;s/\$/${_A_0}/" | head -n 15; fi
}
skip() {
    ASSERT_SKIP=$((ASSERT_SKIP + 1))
    printf '  %sskip%s  %s %s(%s)%s\n' "$_A_Y" "$_A_0" "$1" "$_A_D" "${2:-}" "$_A_0"
}
section() { printf '%s[%s]%s %s\n' "$_A_D" "$ASSERT_MODULE" "$_A_0" "$*"; }

# check "description" command [args...]   (passes when the command exits 0)
check() {
    local desc="$1" out rc=0
    shift
    out="$("$@" 2>&1)" || rc=$?
    if [[ $rc -eq 0 ]]; then
        _a_ok "$desc"
    else
        [[ "$ASSERT_VERBOSE" == 1 ]] || out="${out:0:600}"
        _a_fail "$desc (exit $rc)" "$out"
    fi
}
# check_sh "description" 'shell snippet'
check_sh() { check "$1" bash -c "$2"; }

in_container() { [[ "$ASSERT_CONTEXT" == container ]]; }
has_network() { [[ "$ASSERT_NETWORK" == 1 ]]; }
has_gui() { ! in_container && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && command -v gsettings >/dev/null 2>&1; }
has_systemd() { ! in_container && [[ -d /run/systemd/system ]]; }
has_user_systemd() { has_systemd && systemctl --user show-environment >/dev/null 2>&1; }

# Root-only checks: fluxion's `sudo -n` model, so a missing sudo ticket is a skip, not a failure.
can_sudo() { sudo -n true 2>/dev/null; }

profile_query() { python3 "$ASSERT_REPO_DIR/tests/lib/profile_query.py" "$ASSERT_REPO_DIR/profiles/$1" "$2"; }

# ---- building blocks ----------------------------------------------------------------------------------------

# assert_cmd NAME [VERSION_REGEX [VERSION_ARGS...]]  - on PATH, and (optionally) its version output matches
assert_cmd() {
    local name="$1" re="${2:-}" out
    shift $(($# > 1 ? 2 : 1))
    local vargs=("$@")
    [[ ${#vargs[@]} -gt 0 ]] || vargs=(--version)
    if ! command -v "$name" >/dev/null 2>&1; then
        _a_fail "$name on PATH" "not found in PATH=$PATH"
        return
    fi
    if [[ -z "$re" ]]; then
        _a_ok "$name on PATH ($(command -v "$name"))"
        return
    fi
    out="$("$name" "${vargs[@]}" 2>&1 | head -n 5)" || true
    if grep -Eq -- "$re" <<<"$out"; then
        _a_ok "$name matches /$re/ ($(head -n1 <<<"$out"))"
    else
        _a_fail "$name version matches /$re/" "$out"
    fi
}

# assert_exec PATH [VERSION_REGEX [ARGS...]]  - an executable file (not necessarily on PATH)
assert_exec() {
    local path="$1" re="${2:-}" out
    shift $(($# > 1 ? 2 : 1))
    local vargs=("$@")
    [[ ${#vargs[@]} -gt 0 ]] || vargs=(--version)
    if [[ ! -x "$path" ]]; then
        _a_fail "executable $path" "missing or not executable"
        return
    fi
    if [[ -z "$re" ]]; then
        _a_ok "executable $path"
        return
    fi
    out="$("$path" "${vargs[@]}" 2>&1 | head -n 5)" || true
    if grep -Eq -- "$re" <<<"$out"; then
        _a_ok "$path matches /$re/"
    else
        _a_fail "$path version matches /$re/" "$out"
    fi
}

# assert_pkgs PKG...  - dpkg says "install ok installed" for every package (one line per missing package)
assert_pkgs() {
    local label="$1" p missing=()
    shift
    for p in "$@"; do
        [[ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" == "install ok installed" ]] || missing+=("$p")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        _a_ok "$label: $# apt package(s) installed"
    else
        _a_fail "$label: ${#missing[@]}/$# apt package(s) not installed" "${missing[*]}"
    fi
}

# assert_no_pkgs LABEL PKG...  - none of these is installed
assert_no_pkgs() {
    local label="$1" p present=()
    shift
    for p in "$@"; do
        [[ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null)" == "install ok installed" ]] && present+=("$p")
    done
    if [[ ${#present[@]} -eq 0 ]]; then
        _a_ok "$label"
    else
        _a_fail "$label" "installed: ${present[*]}"
    fi
}

# assert_flatpaks LABEL ID...
# IDs may be apps or extensions (OBS plugins are runtime refs, com.obsproject.Studio.Plugin.*), so the list is
# every installed ref, not just --app.
assert_flatpaks() {
    local label="$1" id missing=()
    shift
    if in_container || ! command -v flatpak >/dev/null 2>&1; then
        skip "$label: $# flatpak(s)" "no flatpak here"
        return
    fi
    local installed
    installed="$(flatpak list --columns=application 2>/dev/null)"
    for id in "$@"; do grep -qxF "$id" <<<"$installed" || missing+=("$id"); done
    if [[ ${#missing[@]} -eq 0 ]]; then
        _a_ok "$label: $# flatpak(s) installed"
    else
        _a_fail "$label: ${#missing[@]}/$# flatpak(s) missing" "${missing[*]}"
    fi
}

# assert_snaps LABEL NAME...
assert_snaps() {
    local label="$1" s missing=()
    shift
    if in_container || ! command -v snap >/dev/null 2>&1; then
        skip "$label" "no snapd here"
        return
    fi
    for s in "$@"; do snap list "$s" >/dev/null 2>&1 || missing+=("$s"); done
    if [[ ${#missing[@]} -eq 0 ]]; then
        _a_ok "$label: $* installed"
    else
        _a_fail "$label: missing snaps" "${missing[*]}"
    fi
}

# assert_link TARGET EXPECTED_REALPATH  - TARGET is a symlink resolving to EXPECTED_REALPATH
assert_link() {
    local target="$1" want got
    want="$(readlink -f -- "$2" 2>/dev/null || true)"
    if [[ ! -L "$target" ]]; then
        _a_fail "link $target" "not a symlink ($(stat -c %F -- "$target" 2>/dev/null || echo missing))"
        return
    fi
    got="$(readlink -f -- "$target" 2>/dev/null || true)"
    if [[ -n "$want" && "$got" == "$want" ]]; then
        _a_ok "link ${target/#$HOME/\~} -> ${want/#$HOME/\~}"
    else
        _a_fail "link ${target/#$HOME/\~} -> ${2/#$HOME/\~}" "resolves to: ${got:-<dangling>}"
    fi
}

# assert_gsetting SCHEMA[:PATH] KEY EXPECTED  - exact `gsettings get` output
assert_gsetting() {
    local schema="$1" key="$2" want="$3" got
    if ! has_gui; then
        skip "gsettings $schema $key" "no GNOME session bus"
        return
    fi
    got="$(gsettings get "$schema" "$key" 2>&1)" || true
    if [[ "$got" == "$want" ]]; then
        _a_ok "gsettings ${schema##*.} $key = $want"
    else
        _a_fail "gsettings $schema $key = $want" "got: $got"
    fi
}

# assert_unit [--user] UNIT  - enabled and active
assert_unit() {
    local scope=--system
    if [[ "$1" == --user ]]; then
        scope=--user
        shift
    fi
    local unit="$1" en act
    if [[ "$scope" == --user ]] && ! has_user_systemd; then
        skip "user unit $unit" "no systemd user session"
        return
    elif ! has_systemd; then
        skip "unit $unit" "no systemd"
        return
    fi
    en="$(systemctl "$scope" is-enabled "$unit" 2>&1 || true)"
    act="$(systemctl "$scope" is-active "$unit" 2>&1 || true)"
    if [[ "$en" == enabled && "$act" == active ]]; then
        _a_ok "${scope#--} unit $unit enabled + active"
    else
        _a_fail "${scope#--} unit $unit enabled + active" "is-enabled: $en; is-active: $act"
    fi
}

# assert_file_contains FILE FIXED_STRING
assert_file_contains() {
    if [[ ! -f "$1" ]]; then
        _a_fail "$1 contains '$2'" "file missing"
    elif grep -qF -- "$2" "$1"; then
        _a_ok "${1/#$HOME/\~} contains '$2'"
    else
        _a_fail "${1/#$HOME/\~} contains '$2'" "$(head -n 5 "$1")"
    fi
}

# assert_group_member GROUP  - the user is listed for GROUP in /etc/group (effective after re-login)
assert_group_member() {
    local g="$1" line
    line="$(getent group "$g" || true)"
    if [[ -z "$line" ]]; then
        _a_fail "group $g exists" "no such group"
    elif tr ',' '\n' <<<"${line##*:}" | grep -qx "$USER"; then
        _a_ok "$USER is in group $g (/etc/group)"
    else
        _a_fail "$USER is in group $g (/etc/group)" "$line"
    fi
}

# assert_git_head DIR COMMIT
assert_git_head() {
    local got
    got="$(git -C "$1" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$got" == "$2" ]]; then
        _a_ok "${1/#$HOME/\~} at ${2:0:12}"
    else
        _a_fail "${1/#$HOME/\~} at ${2:0:12}" "HEAD: ${got:-<not a git checkout>}"
    fi
}

# Prints the module tally and returns 1 when something failed. Standalone runs call it at the end.
assert_summary() {
    printf '%s[%s]%s %d ok, %d failed, %d skipped\n' "$_A_D" "$ASSERT_MODULE" "$_A_0" \
        "$ASSERT_PASS" "$ASSERT_FAIL" "$ASSERT_SKIP"
    [[ $ASSERT_FAIL -eq 0 ]]
}

# Run the module's assertions when a module file is executed directly (not sourced by run-tests.sh).
assert_main() {
    if [[ "${BASH_SOURCE[1]}" == "$0" ]]; then
        "$1"
        assert_summary
        exit $?
    fi
}
