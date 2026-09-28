#!/usr/bin/env bash
# dotfiles-link.sh - back up what is in the way, then link the dotfiles with dotbot-go.
#
# Two dotbot configs, each with its own base directory:
#   1. dotfiles/system-bootstrap.conf.yaml   base ~/.system-bootstrap/.files   shared dotfiles (live clone)
#   2. dotfiles/install.conf.yaml            base ~/.ubuntu-bootstrap/dotfiles  Ubuntu-only files, agent skills
#
# Before dotbot runs (its links use force: true), every link target that exists and is not already the right
# link is copied with `cp -a` to ~/.ubuntu-bootstrap-backup/<same path relative to $HOME>. An older backup at the
# same path is never overwritten: the new copy gets a .YYYYmmdd-HHMMSS suffix instead.
#
#   scripts/dotfiles-link.sh             # back up + link (what profiles/80-dotfiles.yaml and `just dotfiles` run)
#   scripts/dotfiles-link.sh --dry-run   # show the backups it would make and run dotbot -n
#   scripts/dotfiles-link.sh --check     # exit 0 only when every applicable link resolves to its source
#   scripts/dotfiles-link.sh --list      # print "target<TAB>source<TAB>config" for every applicable link
#
# `if:` conditions in the configs are evaluated with sh, as dotbot does. The clone must exist first
# (scripts/system-bootstrap-sync.sh). Environment: SYSTEM_BOOTSTRAP_DIR, UBUNTU_BOOTSTRAP_BACKUP, DOTBOT_BIN.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CLONE_DIR="${SYSTEM_BOOTSTRAP_DIR:-$HOME/.system-bootstrap}"
BACKUP_DIR="${UBUNTU_BOOTSTRAP_BACKUP:-$HOME/.ubuntu-bootstrap-backup}"
DOTBOT_VERSION=v0.4.2

# "base directory|config file" pairs, in run order.
PAIRS=(
    "$CLONE_DIR/.files|$REPO_DIR/dotfiles/system-bootstrap.conf.yaml"
    "$REPO_DIR/dotfiles|$REPO_DIR/dotfiles/install.conf.yaml"
)

MODE=apply
case "${1:-}" in
    '') ;;
    -n | --dry-run) MODE="dry-run" ;;
    --check) MODE=check ;;
    --list) MODE=list ;;
    -h | --help)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    *)
        echo "unknown argument: $1 (see --help)" >&2
        exit 2
        ;;
esac

log() { printf 'dotfiles: %s\n' "$*"; }
warn() { printf 'dotfiles: warning: %s\n' "$*" >&2; }

# Prints "target<TAB>source<TAB>if-command" for each link entry of a dotbot config. The target has ~ expanded,
# the source is made absolute against the base directory (normalised, so ../config/... works).
links_of() {
    python3 - "$1" "$2" "$HOME" <<'PY'
import os, sys, yaml

base, conf, home = sys.argv[1], sys.argv[2], sys.argv[3]
with open(conf) as fh:
    doc = yaml.safe_load(fh) or []

def expand(p):
    if p == "~" or p.startswith("~/"):
        return home + p[1:]
    return p

for task in doc:
    if not isinstance(task, dict) or "link" not in task:
        continue
    for target, spec in (task["link"] or {}).items():
        cond = ""
        if isinstance(spec, dict):
            cond = spec.get("if") or ""
            spec = spec.get("path")
        if not spec:  # dotbot's default: basename of the target without its leading dot
            spec = os.path.basename(target.rstrip("/")).lstrip(".")
        src = expand(spec)
        if not os.path.isabs(src):
            src = os.path.join(base, src)
        print("\t".join([expand(target), os.path.normpath(src), cond.replace("\t", " ")]))
PY
}

# Applicable links of all configs: "target<TAB>source<TAB>config-basename".
applicable_links() {
    local pair base conf target src cond
    for pair in "${PAIRS[@]}"; do
        base="${pair%%|*}"
        conf="${pair#*|}"
        while IFS=$'\t' read -r target src cond; do
            [[ -n "$target" ]] || continue
            if [[ -n "$cond" ]] && ! sh -c "$cond" >/dev/null 2>&1; then
                continue
            fi
            printf '%s\t%s\t%s\n' "$target" "$src" "$(basename "$conf")"
        done < <(links_of "$base" "$conf")
    done
}

# True when $1 is a symlink that resolves to the same place as $2.
linked_to() {
    [[ -L "$1" ]] || return 1
    local a b
    a="$(readlink -f -- "$1" 2>/dev/null)" || return 1
    b="$(readlink -f -- "$2" 2>/dev/null)" || return 1
    [[ -n "$a" && "$a" == "$b" ]]
}

backup_one() {
    # $1 = target that is in the way
    local target="$1" rel dest
    case "$target" in
        "$HOME"/*) rel="${target#"$HOME"/}" ;;
        *) rel="_root${target}" ;;
    esac
    dest="$BACKUP_DIR/$rel"
    if [[ -e "$dest" || -L "$dest" ]]; then
        if diff -rq --no-dereference -- "$target" "$dest" >/dev/null 2>&1; then
            log "already backed up: ~/${rel} (identical copy in $BACKUP_DIR)"
            return 0
        fi
        dest="$dest.$(date +%Y%m%d-%H%M%S)"
    fi
    if [[ "$MODE" == dry-run ]]; then
        log "would back up ~/${rel} -> $dest"
        return 0
    fi
    mkdir -p -- "$(dirname -- "$dest")"
    cp -a -- "$target" "$dest"
    log "backed up ~/${rel} -> $dest"
}

need_clone() {
    if [[ ! -f "$CLONE_DIR/.files/.zshrc" ]]; then
        echo "dotfiles: $CLONE_DIR/.files is missing; run scripts/system-bootstrap-sync.sh first" >&2
        exit 1
    fi
}

resolve_dotbot() {
    if [[ -n "${DOTBOT_BIN:-}" && -x "${DOTBOT_BIN}" ]]; then
        printf '%s' "$DOTBOT_BIN"
    elif command -v dotbot >/dev/null 2>&1; then
        command -v dotbot
    elif [[ -x "$HOME/.apps/dotbot/bin/dotbot" ]]; then
        printf '%s' "$HOME/.apps/dotbot/bin/dotbot"
    elif [[ -x "$HOME/.cache/fluxion/tools/dotbot/$DOTBOT_VERSION/dotbot" ]]; then
        printf '%s' "$HOME/.cache/fluxion/tools/dotbot/$DOTBOT_VERSION/dotbot"
    else
        # fluxion's verified, pinned download (the same binary its dotfiles-apply kind would use).
        "${FLUXION_BIN:-fluxion}" tools install dotbot >/dev/null
        printf '%s' "$HOME/.cache/fluxion/tools/dotbot/$DOTBOT_VERSION/dotbot"
    fi
}

command -v python3 >/dev/null 2>&1 || {
    echo "dotfiles: python3 (with PyYAML) is required" >&2
    exit 1
}

case "$MODE" in
    list)
        applicable_links
        exit 0
        ;;
    check)
        [[ -f "$CLONE_DIR/.files/.zshrc" ]] || exit 1
        bad=0
        while IFS=$'\t' read -r target src _conf; do
            if ! linked_to "$target" "$src"; then
                echo "not linked: $target -> $src" >&2
                bad=1
            fi
        done < <(applicable_links)
        exit $bad
        ;;
esac

need_clone

# ---- 1. back up whatever is in the way ------------------------------------------------------------------------
while IFS=$'\t' read -r target src _conf; do
    linked_to "$target" "$src" && continue
    if [[ -e "$target" || -L "$target" ]]; then
        backup_one "$target"
    fi
done < <(applicable_links)

# ---- 2. dotbot, once per config -------------------------------------------------------------------------------
bin="$(resolve_dotbot)"
log "using $("$bin" --version 2>/dev/null || echo "$bin")"
dry=()
[[ "$MODE" == dry-run ]] && dry=(-n)
for pair in "${PAIRS[@]}"; do
    base="${pair%%|*}"
    conf="${pair#*|}"
    log "dotbot -d $base -c $conf ${dry[*]}"
    "$bin" "${dry[@]}" -d "$base" -c "$conf"
done
