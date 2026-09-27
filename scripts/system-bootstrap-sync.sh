#!/usr/bin/env bash
# system-bootstrap-sync.sh - clone or fast-forward the live dotfiles clone ~/.system-bootstrap.
#
# github.com/w0rxbend/system-bootstrap is the source of truth for the shared dotfiles. This repo does not copy
# them: dotbot links them straight from this clone (dotfiles/system-bootstrap.conf.yaml).
#
#   scripts/system-bootstrap-sync.sh           # clone if missing, else fast-forward only
#   scripts/system-bootstrap-sync.sh --check   # exit 0 when the clone exists and already contains the
#                                              # remote HEAD (fluxion probe; read-only, needs network)
#
# Rules:
#   - The clone uses https, so it works before any SSH key exists. Pushes go over SSH (remote.origin.pushurl).
#   - An existing clone is only ever fast-forwarded (`git merge --ff-only`). Local commits, uncommitted edits,
#     another branch or a diverged history are left alone with a warning; nothing is reset, stashed or clobbered.
#   - A path that exists but is not a clone of that repo is an error, and it is not touched.
#
# Environment: SYSTEM_BOOTSTRAP_DIR (default ~/.system-bootstrap), SYSTEM_BOOTSTRAP_URL (default the https URL).
set -euo pipefail

DEST="${SYSTEM_BOOTSTRAP_DIR:-$HOME/.system-bootstrap}"
URL="${SYSTEM_BOOTSTRAP_URL:-https://github.com/w0rxbend/system-bootstrap.git}"
PUSH_URL="git@github.com:w0rxbend/system-bootstrap.git"
# Never let git ask for credentials: fluxion runs this unattended.
export GIT_TERMINAL_PROMPT=0

say() { printf 'system-bootstrap: %s\n' "$*"; }
warn() { printf 'system-bootstrap: warning: %s\n' "$*" >&2; }
die() {
    printf 'system-bootstrap: error: %s\n' "$*" >&2
    exit 1
}

is_our_origin() {
    # https://github.com/w0rxbend/system-bootstrap(.git) or git@github.com:w0rxbend/system-bootstrap(.git)
    case "$1" in
        https://github.com/w0rxbend/system-bootstrap | https://github.com/w0rxbend/system-bootstrap.git) return 0 ;;
        git@github.com:w0rxbend/system-bootstrap | git@github.com:w0rxbend/system-bootstrap.git) return 0 ;;
        ssh://git@github.com/w0rxbend/system-bootstrap | ssh://git@github.com/w0rxbend/system-bootstrap.git) return 0 ;;
    esac
    [[ "$1" == "$URL" ]]
}

check() {
    [[ -d "$DEST/.git" ]] || return 1
    local origin remote
    origin="$(git -C "$DEST" remote get-url origin 2>/dev/null)" || return 1
    is_our_origin "$origin" || return 1
    [[ -f "$DEST/.files/.zshrc" ]] || return 1
    # Up to date when the remote HEAD commit is already part of our history (equal, or we are ahead).
    remote="$(git -C "$DEST" ls-remote --quiet origin HEAD 2>/dev/null | cut -f1)" || return 1
    [[ -n "$remote" ]] || return 1
    git -C "$DEST" merge-base --is-ancestor "$remote" HEAD 2>/dev/null
}

if [[ "${1:-}" == --check ]]; then
    if check; then exit 0; else exit 1; fi
elif [[ $# -gt 0 ]]; then
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
    [[ "$1" == -h || "$1" == --help ]] && exit 0
    exit 2
fi

command -v git >/dev/null 2>&1 || die "git is not installed (profiles/00-base.yaml installs it)"

# ---- fresh clone ---------------------------------------------------------------------------------------------
if [[ ! -e "$DEST" && ! -L "$DEST" ]]; then
    say "cloning $URL -> $DEST"
    git clone --quiet "$URL" "$DEST"
    git -C "$DEST" config remote.origin.pushurl "$PUSH_URL"
    say "cloned at $(git -C "$DEST" rev-parse --short HEAD); pushes go to $PUSH_URL"
    exit 0
fi

# ---- existing path -------------------------------------------------------------------------------------------
[[ -d "$DEST/.git" ]] || die "$DEST exists but is not a git clone; move it away and re-run (it was not touched)"
origin="$(git -C "$DEST" remote get-url origin 2>/dev/null || true)"
is_our_origin "$origin" || die "$DEST is a clone of '${origin:-<no origin>}', not w0rxbend/system-bootstrap; not touching it"

current_push="$(git -C "$DEST" config --get remote.origin.pushurl || true)"
if [[ -z "$current_push" ]]; then
    git -C "$DEST" config remote.origin.pushurl "$PUSH_URL"
    say "set pushurl -> $PUSH_URL"
elif [[ "$current_push" != "$PUSH_URL" ]]; then
    warn "remote.origin.pushurl is '$current_push' (expected $PUSH_URL); leaving it as it is"
fi

branch="$(git -C "$DEST" symbolic-ref --quiet --short HEAD || true)"
if [[ -z "$branch" ]]; then
    warn "detached HEAD in $DEST; not updating it"
    exit 0
fi
if ! upstream="$(git -C "$DEST" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
    warn "branch '$branch' has no upstream; not updating it"
    exit 0
fi

if ! git -C "$DEST" fetch --quiet origin; then
    warn "git fetch failed (offline?); keeping the clone at $(git -C "$DEST" rev-parse --short HEAD)"
    exit 0
fi

if git -C "$DEST" merge-base --is-ancestor "$upstream" HEAD; then
    ahead="$(git -C "$DEST" rev-list --count "$upstream..HEAD")"
    if [[ "$ahead" -gt 0 ]]; then
        say "up to date ($branch is $ahead commit(s) ahead of $upstream; push them from $DEST)"
    else
        say "up to date ($branch at $(git -C "$DEST" rev-parse --short HEAD))"
    fi
elif git -C "$DEST" merge-base --is-ancestor HEAD "$upstream"; then
    # --ff-only never creates a merge; git itself refuses when uncommitted edits would be overwritten.
    if git -C "$DEST" merge --ff-only --quiet "$upstream"; then
        say "fast-forwarded $branch to $(git -C "$DEST" rev-parse --short HEAD)"
    else
        warn "fast-forward refused (uncommitted changes in files that changed upstream?); nothing was changed."
        warn "commit or stash your edits in $DEST, then run: git -C $DEST pull --ff-only"
    fi
else
    warn "$branch and $upstream have diverged; not merging. Rebase or merge by hand in $DEST."
fi

if [[ -n "$(git -C "$DEST" status --porcelain)" ]]; then
    warn "$DEST has uncommitted changes (kept):"
    git -C "$DEST" status --short >&2
fi
exit 0
