# Justfile for ~/.ubuntu-bootstrap (fluxion workstation bootstrap for Ubuntu 26.04 LTS "resolute").
#
# `just` is installed by the `toolchains` module (cargo-binstall), so on a fresh host start with
# ./bootstrap.sh. Afterwards these recipes are shortcuts for it.

set shell := ["bash", "-euo", "pipefail", "-c"]

home := env_var("HOME")

# Same PATH that bootstrap.sh exports, so fluxion/dotbot resolve identically.

export PATH := home + "/.cargo/bin:" + home + "/.local/bin:" + home + "/.go/bin:" + home + "/.go-workspace/bin:" + home + "/.apps/dotbot/bin:" + home + "/.apps/neovim/bin:" + home + "/.apps/yq/bin:" + home + "/.apps/helm/bin:" + home + "/.apps/kustomize/bin:" + home + "/.local/share/pnpm/bin:" + home + "/.juliaup/bin:" + env_var("PATH")

# The fluxion build every recipe runs: the same resolver as bootstrap.sh and tests/run-tests.sh
# ($FLUXION_BIN, else fluxion-bin.local, else fluxion on PATH).
fluxion := `bash -c 'source scripts/lib/fluxion-bin.sh; fluxion_resolve .; printf %s "${FLUXION_RESOLVED:-fluxion}"'`

# List available recipes
default:
    @just --list --unsorted

# --- Whole bootstrap -----------------------------------------------------------------------

# Run the full default sequence (asks for the sudo password once)
bootstrap *FLAGS:
    ./bootstrap.sh {{ FLAGS }}

# Show what the full sequence would do (no sudo, no changes)
dry-run *FLAGS:
    ./bootstrap.sh --dry-run {{ FLAGS }}

# validate --strict + lint every profile, bash -n every script (read-only)
validate:
    scripts/validate-all.sh

# List modules in run order
list:
    ./bootstrap.sh --list

# --- Single modules ------------------------------------------------------------------------

# Apply one or more modules, e.g. `just apply toolchains` or `just apply shell,dotfiles`
apply NAME *FLAGS:
    ./bootstrap.sh --only {{ NAME }} {{ FLAGS }}

# Resume the default sequence at NAME
from NAME *FLAGS:
    ./bootstrap.sh --from {{ NAME }} {{ FLAGS }}

# Dry-run one or more modules
dry NAME:
    ./bootstrap.sh --dry-run --only {{ NAME }}

# Execution plan (tree) for one or more modules
plan NAME:
    ./bootstrap.sh --plan --only {{ NAME }}

# Live probe summary for every default module (or: just status base,docker)
status NAMES="":
    if [ -n "{{ NAMES }}" ]; then ./bootstrap.sh --status --only {{ NAMES }}; else ./bootstrap.sh --status; fi

# Missing/failed items per module (or: just failed docker)
failed NAMES="":
    if [ -n "{{ NAMES }}" ]; then ./bootstrap.sh --failed --only {{ NAMES }}; else ./bootstrap.sh --failed; fi

# Print the recorded fluxion state of a module
state NAME:
    {{ fluxion }} state show {{ NAME }}

# Point every script at a fluxion build (writes the git-ignored fluxion-bin.local) and check it is recent enough
use-fluxion PATH:
    test -x "{{ PATH }}" || { echo "{{ PATH }} is not an executable file" >&2; exit 1; }
    printf '# fluxion build this repo runs (scripts/lib/fluxion-bin.sh; git-ignored, machine-local)\n%s\n' "$(readlink -f "{{ PATH }}")" > fluxion-bin.local
    bash -c 'source scripts/lib/fluxion-bin.sh; FLUXION_BIN= fluxion_resolve .; echo "fluxion: $FLUXION_RESOLVED"; why="$(fluxion_check_capable "$FLUXION_RESOLVED")" && echo "fluxion $(fluxion_version "$FLUXION_RESOLVED") >= $FLUXION_MIN_VERSION: ok" || { echo "warning: $why" >&2; }'

# Forget everything fluxion recorded for a module (next run re-probes and re-runs it)
state-reset NAME:
    {{ fluxion }} state reset {{ NAME }} --force

# --- Dotfiles and skills --------------------------------------------------------------------

# Re-link the dotfiles: back up what is in the way, then dotbot for ~/.system-bootstrap/.files and dotfiles/
dotfiles:
    scripts/dotfiles-link.sh

# Preview the backups and dotbot changes without touching $HOME
dotfiles-dry:
    scripts/dotfiles-link.sh --dry-run

# Exit 0 only when every dotfile link resolves to its source
dotfiles-check:
    scripts/dotfiles-link.sh --check

# Clone ~/.system-bootstrap if missing, else fast-forward it (never clobbers local changes)
dotfiles-pull:
    scripts/system-bootstrap-sync.sh

# Point every installed agent (Claude, Cursor, Gemini, Copilot, opencode) at the shared skills folder
skills:
    scripts/link-skills.sh

# --- Tests ---------------------------------------------------------------------------------

# Full test run: validate, apply, idempotency re-apply, assertions (tests/run-tests.sh --help)
test *ARGS:
    tests/run-tests.sh {{ ARGS }}

# Read-only: regenerate + validate --strict + lint + dry-run every test profile
test-validate *ARGS:
    tests/run-tests.sh --stages validate --with-optional {{ ARGS }}

# Read-only: post-condition assertions only (e.g. just test-assert --only gnome,vicinae)
test-assert *ARGS:
    tests/run-tests.sh --assert-only {{ ARGS }}

# Regenerate tests/generated/ from profiles/
test-gen:
    tests/gen-test-profiles.sh

# --- Maintenance ---------------------------------------------------------------------------

# Update everything (apt, snap, flatpak, rustup, sdkman, nvm, ...) via ~/system-update.sh
update:
    "$HOME/system-update.sh"

# Without --skip-already-installed on purpose: the 13-executable probe would skip the phase.

# Re-download the ~/.apps binaries with binstaller (after a version bump in config/binstaller.yaml)
refresh-binaries:
    {{ fluxion }} apply -c profiles/40-binaries.yaml --profile binaries --phase binstaller --no-tui

# Re-run all four Nerd Font batches (e.g. after adding families; the fc-list probes would skip them)
refresh-fonts:
    {{ fluxion }} apply -c profiles/40-binaries.yaml --profile binaries --phase fonts-core,fonts-more,fonts-rest,fonts-noto --no-tui

# --- Modules with their own recipe --------------------------------------------------------

# Vicinae launcher, its user service and GNOME extension, Super+D (default module)
vicinae:
    ./bootstrap.sh --only vicinae

# --- Optional modules ----------------------------------------------------------------------

# OBS Studio + plugins (flatpak)
obs:
    ./bootstrap.sh --only obs

# Extra GNOME Shell extensions via gext -F (no Shell confirmation dialog)
gnome-extensions:
    ./bootstrap.sh --only gnome-extensions

# Wallpapers from the old system-bootstrap repo (~109 MB)
wallpapers:
    ./bootstrap.sh --only wallpapers

# Verification + manual-step reminders (run after logging back in)
post-checks:
    ./bootstrap.sh --only post-checks
