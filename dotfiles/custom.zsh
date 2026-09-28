# ~/.custom.zsh - Ubuntu 26.04 LTS overlay for the shared ~/.zshrc.
#
# ~/.zshrc is linked from the live clone ~/.system-bootstrap/.files/.zshrc (the original repo, shared with
# Fedora/Arch). That file ends with `[ -f ~/.custom.zsh ] && source ~/.custom.zsh`, the hook meant for
# machine-specific additions. This file is linked there from ~/.ubuntu-bootstrap/dotfiles/custom.zsh by dotbot.
#
# Keep it small: anything useful on every machine belongs in ~/.system-bootstrap/.files/.zshrc instead.

# Prepend a directory to PATH once, and only when it exists.
_ubuntu_path_prepend() {
    [[ -d "$1" ]] || return 0
    case ":$PATH:" in
        *":$1:"*) ;;
        *) export PATH="$1:$PATH" ;;
    esac
}

# Rust: rustup is installed with --no-modify-path (profiles/30-toolchains.yaml).
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# Claude Code, Codex, uv, poetry, starship, distrobox, ... live in ~/.local/bin. The shared .zshrc appends it;
# prepend it here so these user-installed tools win over older system copies (as the hand-edited ~/.zshrc
# did on this host before the bootstrap).
_ubuntu_path_prepend "$HOME/.local/bin"

# Kimi Code CLI.
_ubuntu_path_prepend "$HOME/.kimi-code/bin"

# pnpm >= 11 puts its executables in $PNPM_HOME/bin (the shared .zshrc only adds $PNPM_HOME).
_ubuntu_path_prepend "$HOME/.local/share/pnpm/bin"

# binstaller tools that the shared .zshrc does not know about yet.
_ubuntu_path_prepend "$HOME/.apps/yq/bin"

# The oh-my-zsh `ubuntu` plugin (apt aliases); the shared plugin list carries `dnf` for Fedora.
[[ -f "$ZSH/plugins/ubuntu/ubuntu.plugin.zsh" ]] && source "$ZSH/plugins/ubuntu/ubuntu.plugin.zsh"

# Repos.
alias bootstrap='cd "$HOME/.ubuntu-bootstrap"'
alias dotfiles='cd "$HOME/.system-bootstrap"'

unfunction _ubuntu_path_prepend
