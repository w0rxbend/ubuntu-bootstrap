#!/usr/bin/env bash
# Ubuntu 26.04 LTS (resolute) system + toolchain updater.
# Linked to ~/system-update.sh by dotbot; run it via the `update` alias.
# Deliberately NOT using `set -e`: one failing section must not stop the others.
# Every section is guarded, so missing tools are skipped. A summary is printed at the end.
set -uo pipefail

failed=()
skipped=()

section() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
run() {
  # run <label> <command...>
  local label="$1"; shift
  if "$@"; then
    return 0
  else
    printf '\033[1;31m!! %s failed (exit %s)\033[0m\n' "$label" "$?"
    failed+=("$label")
    return 1
  fi
}
skip() { printf '   (skipped: %s)\n' "$2"; skipped+=("$1"); }
have() { command -v "$1" >/dev/null 2>&1; }

# Toolchain bins are not always on PATH in a non-interactive shell.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/.juliaup/bin:$HOME/.local/share/pnpm/bin:$HOME/.go/bin:$PATH"

# ---------------------------------------------------------------- apt
section "APT (update, full-upgrade, autoremove)"
if have apt-get; then
  sudo -n true 2>/dev/null || sudo -v || failed+=("sudo")
  run "apt update" sudo apt update \
    && run "apt full-upgrade" sudo apt full-upgrade -y \
    && run "apt autoremove" sudo apt autoremove -y
else
  skip apt "apt-get not found"
fi

# ---------------------------------------------------------------- snap
section "Snap"
if have snap; then
  run "snap refresh" sudo snap refresh
else
  skip snap "snap not found"
fi

# ---------------------------------------------------------------- flatpak
section "Flatpak"
if have flatpak; then
  run "flatpak update" flatpak update -y
  run "flatpak unused cleanup" flatpak uninstall --unused -y
else
  skip flatpak "flatpak not found"
fi

# ---------------------------------------------------------------- rust
section "Rust (rustup)"
if have rustup; then
  run "rustup update" rustup update
else
  skip rustup "rustup not found"
fi

# ---------------------------------------------------------------- julia
section "Julia (juliaup)"
if have juliaup; then
  juliaup self update >/dev/null 2>&1 || true   # no-op/unsupported for some install methods
  run "juliaup update" juliaup update
else
  skip juliaup "juliaup not found"
fi

# ---------------------------------------------------------------- sdkman
section "SDKMAN"
if [ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]; then
  (
    set +u
    export SDKMAN_DIR="$HOME/.sdkman"
    # shellcheck disable=SC1091
    source "$HOME/.sdkman/bin/sdkman-init.sh"
    sdk selfupdate
    sdk update
    sdk upgrade
  ) || { echo "!! sdkman update failed"; failed+=("sdkman"); }
else
  skip sdkman "$HOME/.sdkman not found"
fi

# ---------------------------------------------------------------- node
section "Node.js (nvm, latest LTS)"
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  (
    set +u
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    . "$HOME/.nvm/nvm.sh"
    nvm install --lts --reinstall-packages-from=current --latest-npm
    nvm alias default 'lts/*'
  ) || { echo "!! nvm update failed"; failed+=("nvm"); }
else
  skip nvm "$HOME/.nvm not found"
fi

# ---------------------------------------------------------------- conda / mamba
section "Miniforge (mamba base env)"
if [ -x "$HOME/.miniforge3/bin/mamba" ]; then
  run "mamba update" "$HOME/.miniforge3/bin/mamba" update -n base --all -y
else
  skip mamba "$HOME/.miniforge3/bin/mamba not found"
fi

# ---------------------------------------------------------------- uv / pnpm / poetry
section "uv"
if have uv; then
  run "uv self update" uv self update
  run "uv tool upgrade" uv tool upgrade --all
else
  skip uv "uv not found"
fi

section "pnpm"
if have pnpm; then
  run "pnpm self-update" pnpm self-update
else
  skip pnpm "pnpm not found"
fi

section "Poetry"
if have poetry; then
  run "poetry self update" poetry self update
else
  skip poetry "poetry not found"
fi

# ---------------------------------------------------------------- oh-my-zsh
section "oh-my-zsh"
omz_dir="$HOME/.oh-my-zsh"
if [ -n "${ZSH:-}" ] && [ -d "$ZSH" ]; then omz_dir="$ZSH"; fi
if [ -x "$omz_dir/tools/upgrade.sh" ]; then
  run "oh-my-zsh upgrade" env ZSH="$omz_dir" "$omz_dir/tools/upgrade.sh"
else
  skip oh-my-zsh "$omz_dir/tools/upgrade.sh not found"
fi

# ---------------------------------------------------------------- cargo crates
section "Cargo crates (cargo-binstall)"
crates=(eza lsd fd-find bingrep hx just sd procs du-dust gping tree-sitter-cli macchina bottom broot)
if have cargo-binstall; then
  run "cargo-binstall self" cargo binstall -y cargo-binstall
  run "cargo crates" cargo binstall -y --locked "${crates[@]}"
else
  skip cargo-binstall "cargo-binstall not found"
fi

# ---------------------------------------------------------------- summary
section "Summary"
if [ "${#skipped[@]}" -gt 0 ]; then
  echo "Skipped: ${skipped[*]}"
fi
echo "Binaries in ~/.apps (binstaller) and Nerd Fonts are refreshed with:"
echo "    cd ~/.ubuntu-bootstrap && just refresh-binaries    # and: just refresh-fonts"
if [ "${#failed[@]}" -gt 0 ]; then
  printf '\033[1;31mFailed sections: %s\033[0m\n' "${failed[*]}"
  exit 1
fi
printf '\033[1;32mAll updates finished.\033[0m\n'
