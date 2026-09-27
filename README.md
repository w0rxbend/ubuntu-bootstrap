# zorin-bootstrap

This repo sets up my workstation on **Zorin OS 18 Pro** (Ubuntu 24.04 "noble" base, GNOME, amd64) using
[fluxion](https://worxbend.github.io/fluxion.cr/) 0.3.1.

It ports the Arch and Fedora scripts from
[w0rxbend/system-bootstrap](https://github.com/w0rxbend/system-bootstrap) to declarative fluxion profiles. It also
reproduces everything I installed by hand on the current Zorin install, as found in the bash and zsh history, the
apt log, and the snap and flatpak lists. The same tools stay in charge of their own jobs:

- **dotbot** (dotbot-go) links the dotfiles, straight from a live clone of the original repo in
  `~/.system-bootstrap` (nothing is copied into this repo).
- **nerd-fonts-installer** installs the Nerd Fonts.
- **cargo-binstall** installs the Rust CLI tools.
- **binstaller** installs the pinned release binaries in `~/.apps`.
- **SDKMAN**, **nvm**, **pyenv** and the other language installers work as before.

The desktop is Zorin's own GNOME, with Fedora-style `Super+1..9` workspaces and the **Vicinae** launcher on
`Super+D`. Nothing from the tiling or Arch desktop setup is included (niri, DMS, sway, PaperWM, waybar and so on),
and **Docker CE replaces podman**. Agent skills live in one git-tracked folder that every coding agent links to.
A test harness runs the same orchestration on generated, non-halting copies of the profiles.

---

## Contents

- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [Layout](#layout)
- [Modules](#modules)
- [Full inventory](#full-inventory)
- [Docker instead of podman](#docker-instead-of-podman)
- [Dotfiles with dotbot](#dotfiles-with-dotbot)
- [Agent skills](#agent-skills)
- [Vicinae launcher](#vicinae-launcher)
- [Testing](#testing)
- [Adding or changing items](#adding-or-changing-items)
- [Re-running and idempotency](#re-running-and-idempotency)
- [fluxion 0.3.1 caveats handled here](#fluxion-031-caveats-handled-here)
- [Manual steps after the bootstrap](#manual-steps-after-the-bootstrap)
- [Optional modules](#optional-modules)
- [Not ported, and why](#not-ported-and-why)
- [Updating](#updating)
- [Troubleshooting](#troubleshooting)

---

## Quick start

Do this from the **local GNOME session**, in a terminal on the machine itself rather than over SSH. System flatpak
installs are authorised by polkit only for the active local session, and `gsettings` needs the session bus.

```bash
# 1. prerequisites (a fresh Zorin already ships curl, but git may be missing)
sudo apt update && sudo apt install -y git curl

# 2. clone to the expected path (the profiles hard-code repoDir=$HOME/.zorin-bootstrap)
git clone <your-remote>/zorin-bootstrap.git ~/.zorin-bootstrap
cd ~/.zorin-bootstrap

# 3. install fluxion into ~/.local/bin (bootstrap.sh also does this if it is missing)
curl --proto '=https' --tlsv1.2 -sSfL https://worxbend.github.io/fluxion.cr/install.sh | sh
#    or pin the release this repo was tested with:
curl --proto '=https' --tlsv1.2 -sSfL https://worxbend.github.io/fluxion.cr/install.sh | sh -s -- --version v0.3.1

# 4. check the host is ready (read-only)
fluxion doctor -c profiles/00-base.yaml

# 5. see what would happen (read-only, no sudo)
./bootstrap.sh --validate      # validate --strict + lint for every module
./bootstrap.sh --plan          # execution plan per module (tree)
./bootstrap.sh --dry-run       # exact commands per module

# 6. run it. sudo asks for your password once, and the script keeps the ticket warm
./bootstrap.sh
```

The `dotfiles` module clones [w0rxbend/system-bootstrap](https://github.com/w0rxbend/system-bootstrap) to
`~/.system-bootstrap` over https (no SSH key needed) and links the shared dotfiles from there; anything it replaces in
`$HOME` is backed up to `~/.zorin-bootstrap-backup/` first.

The run is unattended: `bootstrap.sh` passes `--no-tui`, so fluxion prints plain output instead of opening its
full-screen selector for each module. Add `--tui` to get the selector (press `enter` to start and `q` to close the
screen after the run). Pressing `q` **at the selector** skips that module, and fluxion still exits 0, so the
summary reports it as `ok` even though nothing ran.

`fluxion doctor` always prints `[warn] host os unrecognised: zorin`; that is expected (see the caveats table). On a
fresh host `doctor` also fails `cargo-binstall command not found` for `30-toolchains.yaml` and `pipx command not
found` for `optional/gnome-extensions.yaml`. Both are installed by an earlier phase/module of the same run
(`rust` phase and `base`), so those two failures are expected before the first apply.

To apply a single module, or a single phase inside a module, without running everything:

```bash
./bootstrap.sh --only docker                  # one module (wrapper: PATH, sudo keep-alive, summary)
./bootstrap.sh --only apps,docker             # several modules, in table order
# one phase, directly with fluxion (keep the module's state name; run `sudo -v` first):
fluxion apply -c profiles/10-apps.yaml --profile apps --phase vscode --skip-already-installed
fluxion list -c profiles/10-apps.yaml         # phase and step names of a module
fluxion graph -c profiles/10-apps.yaml        # phase dependency graph (mermaid)
```

The last module (`session`) changes your groups (`docker`, `libvirt`, `kvm`) and your login shell. It then stops with
a **log-out checkpoint** (fluxion exit code 75). The re-login also loads the Vicinae GNOME Shell extension. Log out
and back in, or reboot, then run:

```bash
cd ~/.zorin-bootstrap && ./bootstrap.sh --only post-checks
```

A full run on a fresh install takes a while. The slow parts are TeX Live, around 55 flatpaks, SDKMAN candidates,
Miniforge and the Nerd Fonts, which total about 1.5 GB. When a module fails, the script **carries on with the next
one** and prints a summary at the end. Fix whatever failed and re-run just that module with
`./bootstrap.sh --only NAME`.

### `bootstrap.sh` reference

```
./bootstrap.sh [--dry-run | --validate | --plan | --status | --failed | --list]
               [--only a,b | --from NAME] [--yes] [--tui] [--show-output] [--re-probe]
               [--test | --profiles-dir DIR] [--state-prefix P] [--report FILE]
```

| Flag | Effect |
|---|---|
| *(none)* | Runs `fluxion apply --profile NAME --skip-already-installed --no-tui` for every default module, in order |
| `--dry-run` | Runs `fluxion dry-run --no-tui`: prints the exact commands and changes nothing. No sudo |
| `--validate` | Runs `fluxion validate --strict` and `fluxion lint` on each selected module |
| `--plan` | Runs `fluxion plan --format tree` |
| `--status` / `--failed` | Runs `fluxion status --summary` / `--failed`: read-only live probes |
| `--list` | Lists the modules and their files |
| `--only a,b` | Selects only these modules, default or optional. They always run in table order |
| `--from NAME` | Resumes the default sequence at `NAME` |
| `--tui` | Opens fluxion's interactive selector/TUI for each module instead of plain output (apply only) |
| `--no-tui` | The default; accepted for compatibility |
| `--yes`, `--show-output`, `--re-probe` | Passed through to fluxion |
| `--test` | Runs the generated test profiles (`tests/generated/`, regenerated first) with state names `test-NAME`. Same orchestration, same modules; see [Testing](#testing) |
| `--profiles-dir DIR` | Reads each module's profile from `DIR` instead of `profiles/` (same relative layout) |
| `--state-prefix P` | Prefixes the fluxion state names (`--test` uses `test-`) |
| `--report FILE` | Appends one tab-separated line per module: name, rc, result, seconds and fluxion's `Summary:` counts (ok, failed, skipped, would run) |

`FLUXION_BIN=/path/to/fluxion ./bootstrap.sh ...` uses that fluxion instead of the one on PATH (for example a patched
build); the profiles' own scripts get the same binary through the exported variable.

Before any module runs, the script does these checks and setup steps:

- It refuses to run as root.
- It warns if the repo is not at `~/.zorin-bootstrap`, if you are connected over SSH, or if the host is not
  noble-based.
- It uses `$FLUXION_BIN` when set, otherwise installs fluxion when it is missing, and warns if the version is not
  0.3.1.
- It exports a PATH that includes every tool location the modules create: `~/.cargo/bin`, `~/.local/bin`,
  `~/.go/bin`, `~/.apps/{dotbot,neovim,yq,helm,kustomize}/bin`, `~/.local/share/pnpm/bin` and juliaup.
- It runs `sudo -v` once (skipped when `sudo -n true` already works, e.g. under NOPASSWD, where `sudo -v` can
  still ask for a password) and then refreshes the ticket every 50 s until the script exits.

Each module is validated before it is applied. The exit code is 0 when everything succeeded or the log-out
checkpoint was reached, and 1 when any module failed.

The script never sees your password. `sudo` prompts for it directly, and fluxion only ever calls `sudo -n`.

### `just` shortcuts

`just` is installed by the `toolchains` module, so it is only available after the first run.

| Recipe | Runs |
|---|---|
| `just bootstrap` / `just dry-run` / `just validate` / `just list` | The full run, the dry-run, `scripts/validate-all.sh`, and the module list |
| `just apply NAME` | `./bootstrap.sh --only NAME` (NAME can be `a,b`) |
| `just from NAME` | Resumes the default sequence at NAME |
| `just dry NAME` / `just plan NAME` | Dry-run or plan for one module |
| `just status [a,b]` / `just failed [a,b]` | Live probe summary, or only the missing and failed items |
| `just state NAME` / `just state-reset NAME` | Shows or deletes the fluxion state recorded for a module |
| `just dotfiles` / `just dotfiles-dry` / `just dotfiles-check` | `scripts/dotfiles-link.sh`: back up + re-link everything, preview, or verify every link |
| `just dotfiles-pull` | `scripts/system-bootstrap-sync.sh`: clone `~/.system-bootstrap` or fast-forward it |
| `just skills` | `scripts/link-skills.sh`: link every installed agent to the shared skills folder |
| `just test [ARGS]` / `just test-validate` / `just test-assert` / `just test-gen` | `tests/run-tests.sh` (all stages / read-only validate + dry-run / assertions only), regenerate `tests/generated/` |
| `just vicinae` | `./bootstrap.sh --only vicinae` |
| `just update` | `~/system-update.sh` (apt, snap, flatpak, rustup, SDKMAN, nvm, ...) |
| `just refresh-binaries` / `just refresh-fonts` | Re-runs the binstaller phase / the four Nerd Font phases without `--skip-already-installed` (see [Updating](#updating)) |
| `just obs` / `pro-parity` / `gnome-extensions` / `wallpapers` / `post-checks` | The optional modules |

---

## How it works

fluxion has no include mechanism, so every module is a **complete, standalone `WorkstationProfile`** in `profiles/`.
`bootstrap.sh` runs them one after another. Each module gets its **own state name** (`--profile base`,
`--profile docker`, ...), so its state lives in `~/.local/share/fluxion/state/<name>.json`.

Splitting the setup this way has these consequences:

- Each module runs in a new fluxion process. fluxion reads PATH and evaluates `when:` only once, at load time. Tools
  installed by an earlier module (cargo-binstall, dotbot, broot, gext) are therefore visible to later modules.
- A module can be re-run, reset or debugged on its own.
- A failure in one module does not block the others. Inside a module, the lists most likely to fail (flatpaks, snaps,
  curl installers) sit in **leaf phases** that no other phase depends on.
- The only `prompt-logout` phase is in the last module, `session`, so dry-runs of the other modules are never cut
  short. The generated test profiles drop it entirely.
- `dotfiles` runs late on purpose. Several installers (SDKMAN, juliaup, pnpm, codex, kimi) append lines to
  `~/.zshrc`. Running dotbot after them means those lines land in the throwaway oh-my-zsh template (which is backed
  up to `~/.zorin-bootstrap-backup/.zshrc`), and dotbot then replaces it with the link to
  `~/.system-bootstrap/.files/.zshrc`. If dotbot ran first, the installers would edit the shared file.

Every profile begins with a `host-check` assert that the host is noble-based with `apt-get`. Profiles never use
`when: {distribution: ubuntu}`, because fluxion does not map `ID=zorin` to ubuntu.

---

## Layout

```
~/.zorin-bootstrap/
├── README.md
├── Justfile                      # shortcuts (just is installed by `toolchains`)
├── bootstrap.sh                  # ordered runner: preflight, sudo keep-alive, summary (--test for the tests)
├── .gitignore  .editorconfig  .shellcheckrc
├── scripts/
│   ├── validate-all.sh           # validate --strict + lint (prod + test profiles), bash -n + shellcheck
│   ├── system-bootstrap-sync.sh  # clone ~/.system-bootstrap (https) or fast-forward it; --check
│   ├── dotfiles-link.sh          # back up what is in the way, run dotbot for both configs; --check/--dry-run
│   └── link-skills.sh            # POSIX sh: <agent>/skills -> ~/.agents/skills for installed agents
├── profiles/
│   ├── 00-base.yaml              # base
│   ├── 10-apps.yaml              # apps
│   ├── 20-docker.yaml            # docker
│   ├── 30-toolchains.yaml        # toolchains
│   ├── 40-binaries.yaml          # binaries
│   ├── 50-shell.yaml             # shell
│   ├── 60-desktop-apps.yaml      # desktop-apps
│   ├── 70-gnome.yaml             # gnome
│   ├── 75-vicinae.yaml           # vicinae
│   ├── 80-dotfiles.yaml          # dotfiles
│   ├── 90-session.yaml           # session (log-out checkpoint)
│   └── optional/
│       ├── obs.yaml
│       ├── zorin-pro-parity.yaml
│       ├── gnome-extensions.yaml
│       ├── wallpapers.yaml
│       └── post-checks.yaml
├── config/
│   ├── binstaller.yaml           # binstaller profile (also linked to ~/.config/binstaller/config.yaml)
│   └── nerd-fonts/
│       ├── all.yaml              # all 42 families (linked to ~/.config/nerd-fonts-installer/config.yaml)
│       ├── 01-core.yaml  02-more.yaml  03-rest.yaml  04-noto.yaml   # batches fluxion uses
├── dotfiles/                     # ONLY Zorin-specific files; shared dotfiles come from ~/.system-bootstrap
│   ├── system-bootstrap.conf.yaml  # dotbot config, base dir ~/.system-bootstrap/.files (the live clone)
│   ├── install.conf.yaml         # dotbot config, base dir dotfiles/ (the Zorin-only files below)
│   ├── custom.zsh                # -> ~/.custom.zsh, sourced by the shared .zshrc (Zorin PATH + ubuntu plugin)
│   ├── zorin-system-update.sh    # -> ~/system-update.sh
│   ├── .config/xdg-terminals.list  .config/environment.d/90-session.conf   # kitty as terminal, session env
│   └── agents/skills/            # the shared agent skills (README.md explains the layout)
└── tests/
    ├── gen-test-profiles.sh      # profiles/ -> tests/generated/ (halting steps removed)
    ├── run-tests.sh              # validate, apply, idempotency re-apply, assertions; --container
    ├── generated/                # git-ignored, regenerated before every use
    ├── assertions/               # lib.sh + one <module>.sh per module (the real post-conditions)
    ├── container/Dockerfile      # ubuntu:24.04 image for --container
    ├── lib/                      # generator, profile queries, inline-snippet extractor (python3 + PyYAML)
    └── logs/                     # git-ignored run logs

~/.system-bootstrap/              # live clone of github.com/w0rxbend/system-bootstrap (source of truth)
└── .files/                       # .zshrc, nvim, kitty.conf, .tmux.conf, starship, alacritty, .config/...
```

Relative paths inside a profile resolve from the profile file's own directory. That is why `profiles/*.yaml` refer
to `../config/...` and `profiles/optional/*.yaml` refer to `../../...`.

---

## Modules

Default sequence (`./bootstrap.sh`):

| # | Module | File | What it does |
|---|---|---|---|
| 1 | `base` | `profiles/00-base.yaml` | Repair of the broken Crystal apt source, `apt full-upgrade`, debconf preseeds, about 190 Ubuntu-archive packages (CLI, build, debug, GUI-dev, media, fonts, TeX, desktop, virtualisation), GPU tools chosen by `lspci`, libvirtd, global git config, NTP clock, `bat` symlink |
| 2 | `apps` | `profiles/10-apps.yaml` | Third-party apt apps: GitHub CLI, Claude Desktop, VS Code, 1Password, Crystal (repo and key), ChatGPT and fastfetch (`.deb`) |
| 3 | `docker` | `profiles/20-docker.yaml` | Docker CE, buildx and the compose plugin from Docker's apt repo, the docker/containerd services, distrobox |
| 4 | `toolchains` | `profiles/30-toolchains.yaml` | rustup, cargo-binstall and 14 crates, Go 1.27.1, SDKMAN and 8 candidates, nvm and Node LTS, pnpm, pyenv, poetry, uv, Miniforge, juliaup, kustomize, helm 4, dotenvx |
| 5 | `binaries` | `profiles/40-binaries.yaml` | binstaller profile (13 tools in `~/.apps`), `nvim`/`vim` links in `/usr/local/bin`, Nerd Fonts in 4 batches |
| 6 | `shell` | `profiles/50-shell.yaml` | oh-my-zsh (pinned) and 3 plugins, TPM, starship, kitty (upstream build, desktop integration, `x-terminal-emulator` alternative), ghostty snap |
| 7 | `desktop-apps` | `profiles/60-desktop-apps.yaml` | Flathub remote, 55 flatpaks in category groups, theia-ide and telegram snaps, Claude Code, Codex and Kimi CLIs, Zed, Paseo |
| 8 | `gnome` | `profiles/70-gnome.yaml` | 9 fixed workspaces, `Super+N` / `Super+Shift+N` bindings, screenshot keys, Zorin Dash / Zorin Taskbar hot-keys turned off, pinned favourites |
| 9 | `vicinae` | `profiles/75-vicinae.yaml` | Vicinae launcher (pinned AppImage via the official script into `/usr/local`), its systemd user service, the `vicinae@dagimg-dot` GNOME extension, `Super+D` toggle |
| 10 | `dotfiles` | `profiles/80-dotfiles.yaml` | Clones/fast-forwards `~/.system-bootstrap`, backs up what is in the way, links both dotbot configs (shared dotfiles from the clone, Zorin-only files and agent skills from this repo), tmux plugins, broot launcher |
| 11 | `session` | `profiles/90-session.yaml` | zsh as login shell, `docker`/`libvirt`/`kvm` groups, **log-out checkpoint** |

Optional modules (`./bootstrap.sh --only NAME`):

| Module | What it does |
|---|---|
| `obs` | OBS Studio and 10 flatpak plugins (DroidCam, background removal, VAAPI, PipeWire video, ...) |
| `zorin-pro-parity` | The 35 flatpaks that Zorin OS **Pro** preinstalls, for a Zorin Core install or a reinstall without Pro |
| `gnome-extensions` | `gext` (pipx) plus user-theme, battery-indicator-icon, notification-icons, tophat, space-bar, AlphabeticalAppGrid, installed with `gext -F` (no GNOME Shell dialog) |
| `wallpapers` | Sparse clone of the wallpapers from the old repo into `~/.local/share/backgrounds/system-bootstrap` (about 109 MB) |
| `post-checks` | Run after logging back in. Checks the docker group, `docker run hello-world`, the zsh login shell, fonts, nvim, the core CLIs and that the Vicinae extension is active, then reminds you of the manual steps |

---

## Full inventory

The profile files have the exact spec for each item. This section is a quick summary.

### `base`: Ubuntu archive

| Group | Packages |
|---|---|
| core | ca-certificates curl wget gnupg git zsh unzip zip xz-utils fontconfig fuse3 libfuse2t64 software-properties-common debconf-utils apt-transport-https pciutils python3-yaml (used by the dotfiles and test scripts) |
| CLI | alacritty bat btop fzf htop tmux wl-clipboard jq net-tools hyperfine asciinema gdu xsensors lm-sensors stress zoxide tig wev foot mtr nmap httpie ripgrep pipx stacer tree mediainfo libimage-exiftool-perl imagemagick poppler-utils ffmpegthumbnailer 7zip python3-venv python3-pip python3-dev |
| build | build-essential gcc g++ pkg-config clang clangd clang-format clang-tidy clang-tools llvm llvm-dev libclang-dev libclang-rt-dev lld lldb make cmake meson ninja-build ccache flex bison gperf, plus the -dev libraries that pyenv, Python, Rust and Crystal builds need (readline, ffi, ssl, zlib, bz2, sqlite3, lzma, tk, ncurses, xml2, xmlsec1, secret, yaml, gmp) and dfu-util |
| debug | gdb valgrind strace ltrace linux-tools-common linux-tools-generic-hwe-24.04 tshark protobuf-compiler |
| GUI dev | GTK 3/4 and GObject-introspection dev packages, WebKitGTK 6, X11/Xcursor/Xrandr/Xi/Xinerama dev, Mesa/GL/EGL/GBM dev, mesa-utils, mesa-vdpau-drivers |
| media | vlc mpv imv ffmpeg, libav* dev packages, the GStreamer plugin sets (base/good/bad/ugly/libav/vaapi/pipewire), libopenh264-7, VA-API/VDPAU and vainfo, PipeWire and wireplumber, easyeffects, power-profiles-daemon, upower, **ubuntu-restricted-extras** (EULA preseeded), **v4l2loopback-dkms** and HWE headers |
| fonts / TeX | fonts-firacode fonts-font-awesome fonts-noto-core fonts-noto-color-emoji fonts-roboto, texlive-base/latex-base/latex-recommended/fonts-recommended/xetex |
| desktop | gnome-tweaks, shell-extension prefs and extensions, gnome-browser-connector, xdg-desktop-portal-gtk, gnome-keyring, libpam-gnome-keyring, seahorse, gcr, gcr4, zathura (+pdf-poppler), mupdf |
| GPU (by `lspci`, as in the old scripts) | `radeontop` when an AMD GPU is present, `intel-media-va-driver` (iHD VA-API) when an Intel GPU is present; nothing otherwise |
| virt | qemu-system-x86 qemu-utils ovmf libvirt-daemon-system libvirt-clients virtinst virt-manager bridge-utils dnsmasq-base vde2 netcat-openbsd cpu-checker, plus `libvirtd.socket` enabled and listening (`libvirtd.service` enabled; it is socket-activated and exits after 120 s idle) |
| config | git `user.email`, `user.name` = w0rxbend, `pull.rebase=true`, `init.defaultBranch=main`, `core.autocrlf=input`; NTP on and RTC in UTC; `~/.local/bin/bat` pointing to `batcat` |

Before anything runs `apt-get update`, the `apt-sources-repair` phase moves aside the broken Crystal source this host got
from `curl -fsSL https://crystal-lang.org/install.sh | sudo zsh` (see [Troubleshooting](#troubleshooting)). It does
nothing when the files are absent or correct.

Debconf preseeds run first: they accept the mscorefonts EULA and set wireshark to `install-setuid=false`. fluxion does
not set `DEBIAN_FRONTEND`, so without the preseeds these packages could hang waiting for an answer.

### `apps`: third-party apt apps (these were installed by hand on this host)

| App | Source |
|---|---|
| `gh` | `cli.github.com/packages` repo, keyring `/etc/apt/keyrings/githubcli-archive-keyring.gpg` (sha256-pinned) |
| `claude-desktop` | `downloads.claude.ai/claude-desktop/apt/stable` repo, keyring `/usr/share/keyrings/claude-desktop-archive-keyring.gpg`. It pulls in qemu, ovmf and virtiofsd for its VM |
| `code` | Microsoft key (fingerprint-pinned) and a `vscode.sources` file identical to the one the package writes |
| `1password` | 1Password key (fingerprint-pinned) and a `1password.sources` file identical to the one the package writes |
| `chatgpt` | The latest `.deb` from `persistent.oaistatic.com`. Its postinst adds the repo and keyring, since there is no public key URL |
| `fastfetch` | The latest `.deb` from the fastfetch GitHub releases (it is not in the noble archive) |
| `crystal` | openSUSE OBS `devel:languages:crystal` repo (`xUbuntu_24.04`, the one `crystal-lang.org/install.sh` sets up), keyring `/etc/apt/keyrings/crystal.gpg` (sha256-pinned; the key expires 2027-09-22). The `crystal` meta package pulls `crystal1.21` (Crystal 1.21.1 with `/usr/bin/shards`; this host already runs it). `apps-crystal-upgrade` moves an older universe build (1.11.2) to the repo build, because the dpkg probe alone would count 1.11.2 as installed. Never add Ubuntu's `shards` package: it clashes with `/usr/bin/shards` from `crystal1.21` |

Brave is not touched. It is Zorin 18's default browser and comes from Zorin's apt source.

The `claude-desktop` package's postinst rewrites `/usr/share/keyrings/claude-desktop-archive-keyring.asc` on every
install and upgrade. That file is harmless. The `claude-desktop.list` written here has no `### Managed by the
claude-desktop package.` marker, so the postinst leaves it alone and it keeps pointing at the dearmored `.gpg`.

### `docker`

See [Docker instead of podman](#docker-instead-of-podman).

### `toolchains`: user-level, no sudo

| Tool | How | Where |
|---|---|---|
| Rust | rustup (sha256-pinned script, `--no-modify-path`) | `~/.cargo`, `~/.rustup` |
| cargo-binstall | Pinned upstream install script | `~/.cargo/bin` |
| Crates (cargo-binstall) | eza lsd fd-find bingrep hx just sd procs du-dust gping tree-sitter-cli macchina bottom broot | `~/.cargo/bin` |
| Go 1.27.1 | Official tarball, sha256-checked | `~/.go`, `GOPATH=~/.go-workspace` |
| SDKMAN | `get.sdkman.io` (sha256-pinned), run with **bash**, auto-answer on | `~/.sdkman` |
| SDKMAN candidates | java gradle maven sbt scala micronaut vertx visualvm (latest defaults) | `~/.sdkman/candidates` |
| nvm and Node LTS | nvm v0.40.7 (sha256-pinned), `nvm install --lts`, default alias `lts/*` | `~/.nvm` |
| pnpm | `get.pnpm.io` (`PNPM_HOME=~/.local/share/pnpm`) | `~/.local/share/pnpm/bin` (pnpm 11+ layout) |
| pyenv | `pyenv.run` (sha256-pinned) | `~/.pyenv` |
| poetry / uv | Official installers | `~/.local/bin` |
| Miniforge | Latest `Miniforge3-Linux-x86_64.sh`, batch mode | `~/.miniforge3` |
| juliaup | `install.julialang.org` (sha256-pinned) | `~/.juliaup` |
| kustomize / helm 4 | Upstream install scripts, no sudo (helm's script needs its dir on PATH, which the step sets) | `~/.apps/{kustomize,helm}/bin` |
| dotenvx | `dotenvx.sh` | `~/.local/bin` |

`hx` is sitkevij's hex viewer, not Helix.

### `binaries`

- **binstaller** (`config/binstaller.yaml`, mode `developer`, `appsDir: ~/.apps`): yazi v26.5.6, zig 0.15.2, minikube,
  xplr, kind v0.31.0, zellij v0.44.1, kubectl (stable), neovide (AppImage), neovim (latest), lazygit 0.61.0,
  jujutsu v0.40.0, dotbot v0.4.2, and **yq** (mikefarah, newly added). Every tool gets its own
  `~/.apps/<tool>/bin`.
- **nvim system links**: `/usr/local/bin/{nvim,neovim,vim}` point to `~/.apps/neovim/bin/nvim`, so `sudo vim` also
  opens your Neovim. `/usr/bin` belongs to dpkg and is not touched. binstaller's own sudo symlinks are turned off.
- **Nerd Fonts** (nerd-fonts-installer, `~/.local/share/fonts/NerdFonts`), installed in 4 batches because fluxion
  gives the kind a fixed 15-minute timeout:
  - `01-core`: JetBrainsMono, VictorMono, FiraCode, FiraMono, SymbolsOnly, CascadiaCode, Meslo, Hack, SourceCodePro,
    UbuntuMono, Ubuntu, ZedMono, GeistMono, CommitMono
  - `02-more`: MPlus, Terminus, FantasqueSansMono, HeavyData, 3270, LiberationMono, RobotoMono, Mononoki,
    DroidSansMono, Monoid, SpaceMono, ComicShannsMono, DaddyTimeMono, CodeNewRoman
  - `03-rest`: Hasklig, DejaVuSansMono, Inconsolata, Hermit, Agave, Monaspace, ShareTechMono, Recursive, D2Coding,
    EnvyCodeR, IosevkaTerm, Lekton, Lilex
  - `04-noto`: Noto, which is large

  The terminals rely on VictorMono (alacritty, ghostty, wezterm) and FiraCode (kitty).

### `shell`

oh-my-zsh (pinned revision and sha256), zsh-syntax-highlighting, zsh-autosuggestions, zsh-history-substring-search
(pinned commits), TPM (pinned), starship (`~/.local/bin`), and **kitty** from the upstream installer
(`~/.local/kitty.app`). kitty's desktop integration matches what I did by hand in bash: `kitty`/`kitten` links in
`~/.local/bin`, and `.desktop` files with absolute `Icon`/`Exec` paths. kitty is also registered and selected as the
`x-terminal-emulator` alternative (priority 60), which is what GNOME/GLib falls back to because `xdg-terminal-exec`
is not installed. The **ghostty** snap uses classic confinement. zsh itself comes from `base`, and the login shell change happens in `session`.

### `desktop-apps`

- **Flathub** remote (the descriptor is sha256-pinned; this is a no-op on Zorin, which already has it).
- **Flatpaks** (55 in total, one leaf phase per group, `continueOnError`):
  - browsers: LibreWolf, Chrome, Zen
  - communication: Discord, Zulip, **Vesktop**
  - media: Spotify, Audacity, AudioTube, ncspot, Decibels, Amberol, G4Music
  - graphics: Kdenlive, Inkscape, Krita, Blender, FreeCAD, Godot, LibreCAD, BambuStudio, Exhibit
  - writing: TextPieces, Apostrophe, Bookup, Censor, Logseq
  - dev: Ptyxis, WezTerm, VSCodium
  - system: Extension Manager, Flatseal, Flatsweep, Warehouse, Resources, Refine, Mission Center, Gradia, List,
    Authenticator, Polari, D-Spy, Rewaita, Emblem, Mozilla VPN, NetPeek, **GNOME Boxes**, **Gear Lever**
  - productivity: Sessions, Blanket, Packet, LocalSend, NewsFlash, Dosage, Health
- **Snaps**: `theia-ide` (classic) and `telegram-desktop`.
- **AI CLIs**: Claude Code (`claude.ai/install.sh`), OpenAI Codex (`chatgpt.com/codex/install.sh`), and Kimi Code
  (`code.kimi.com`, run with bash, since running it with zsh failed on this host).
- **Home-dir apps**: Zed (`zed.dev/install.sh`) and **Paseo**, in the layout Gear Lever gave it on this host:
  `~/AppImages/paseo.appimage`, icon `~/AppImages/.icons/paseo` (extracted from the AppImage), launcher
  `~/.local/share/applications/paseo.desktop` (`paseo://` URL handler, `StartupWMClass=Paseo`) and the
  `~/.local/bin/paseo` link. An existing launcher is kept, and nothing is downloaded when the AppImage is already
  there.

Items in **bold** were found in this host's history or package logs. Several flatpaks come preinstalled with Zorin
Pro, so installing them does nothing there.

### `gnome`

Turns off dynamic workspaces and sets 9 workspaces. `Super+1..9` switches workspace and `Super+Shift+1..9` moves the
window there, as on Fedora. The default `switch-to-application-N` bindings are cleared, and screenshot UI is on
`Super+Print` and `Print`. The `hot-keys` setting of **Zorin Dash** (`zorin-dash@zorinos.com`, the enabled dock on
Zorin OS 18 Pro, `hot-keys=true` by default) and of Zorin Taskbar is turned off, because both grab `Super+1..9` and
`Shift+Super+1..9` to launch pinned apps; without that the workspace bindings never fire. The probe (and
`tests/assertions/gnome.sh`) also scans every gsettings key for any other holder of those shortcuts. The module has to
run inside the logged-in GNOME session and asserts that `DBUS_SESSION_BUS_ADDRESS` is set.

It also sets the dash/taskbar favourites to what I pinned by hand: Brave, Files, Software, Terminal, Vesktop,
ChatGPT, Claude and Paseo (`org.gnome.shell favorite-apps`). `gnome` runs after `apps` and `desktop-apps`, so those
`.desktop` IDs exist by then.

### `vicinae`

See [Vicinae launcher](#vicinae-launcher).

### `dotfiles` and `session`

See [Dotfiles with dotbot](#dotfiles-with-dotbot) and [Agent skills](#agent-skills). `session` sets `/usr/bin/zsh`
as your login shell and adds you to `docker`, `libvirt` and `kvm`. It then asks you to log out.

---

## Docker instead of podman

The old Fedora setup used podman, podman-docker, toolbox and buildah. On Zorin, these are replaced by **Docker CE
from Docker's official apt repository**. Ubuntu's `docker.io` is not used.

| What | Value |
|---|---|
| Repo | `deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable` in `/etc/apt/sources.list.d/docker.list` |
| Key | `https://download.docker.com/linux/ubuntu/gpg`, sha256-pinned, fingerprint `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88` |
| Packages | `docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` |
| Services | `docker` and `containerd` enabled and started |
| Conflicts | `docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc` are removed first, if present |
| Group | `docker`, added in `session`. It takes effect after you **log out and back in** |
| Toolbox replacement | `distrobox` 1.8.2.5 from the upstream release tarball (sha256-pinned), installed with `--prefix ~/.local` into `~/.local/bin`; `uidmap` comes from apt. It uses docker automatically |

Notes:

- distrobox is **not** taken from apt: Ubuntu's `distrobox` package depends on `podman | docker.io`, and
  `docker.io` conflicts with `docker-ce`, so apt would pull podman back in. Bump it via `distroboxVersion` /
  `distroboxSha256` in `profiles/20-docker.yaml`.
- The suite is the literal `noble`. Zorin's own codename is not an Ubuntu suite.
- Compose is the v2 plugin, so use `docker compose ...` rather than `docker-compose`. The oh-my-zsh `docker` and
  `docker-compose` plugins stay enabled in `.zshrc`.
- `kind` and `minikube` (from binstaller) use the **docker driver**. Until you log in again, `docker` needs `sudo`
  or `newgrp docker`.
- Being in the `docker` group is equivalent to having root access. That is the usual trade-off, and the same one the
  old podman-docker socket setup made. If you would rather avoid it, consider Docker's rootless mode.
- Check it with `./bootstrap.sh --only post-checks`, which runs `docker run --rm hello-world`.

---

## Dotfiles with dotbot

**The original repo is the source of truth.** [w0rxbend/system-bootstrap](https://github.com/w0rxbend/system-bootstrap)
is cloned to `~/.system-bootstrap`, and dotbot links the dotfiles straight out of that clone. This repo keeps no
copies: `dotfiles/` holds only what has no equivalent in the original repo.

### The clone

`scripts/system-bootstrap-sync.sh` (phase `system-bootstrap-clone` of `dotfiles`, or `just dotfiles-pull`):

- clones over **https**, so it works before any SSH key exists, and sets
  `remote.origin.pushurl = git@github.com:w0rxbend/system-bootstrap.git`, so pushes go over SSH once you have a key;
- when the clone exists, only **fast-forwards** it (`git fetch` + `git merge --ff-only`). Local commits, uncommitted
  edits, another branch, a detached HEAD or a diverged history are left alone with a warning; nothing is reset,
  stashed or overwritten. A path that is not a clone of that repo is an error and is not touched;
- `--check` (the fluxion probe) passes when the clone already contains the remote `HEAD`, so a re-run only pulls when
  GitHub has new commits.

### The two dotbot configs

dotbot here is the Go version (**dotbot-go** v0.4.2, `~/.apps/dotbot/bin/dotbot`, or fluxion's verified cached
copy). `scripts/dotfiles-link.sh` runs it once per config, each with its own base directory:

| Config (in this repo) | Base directory | Links |
|---|---|---|
| `dotfiles/system-bootstrap.conf.yaml` | `~/.system-bootstrap/.files` | `~/.zshrc`, `~/.tmux.conf`, `~/.ideavimrc`, `~/.wezterm.lua`, `~/.hidden`, `~/.config/{starship.toml, alacritty/{alacritty,theme}.toml, kitty/kitty.conf, nvim, btop, ghostty, zathura/zathurarc, zellij/{config.kdl, layouts/*}, lazygit, lsd, yazi, bottom}`; `~/.config/paperwm/paperwm.conf` **only when PaperWM is installed** |
| `dotfiles/install.conf.yaml` | `~/.zorin-bootstrap/dotfiles` | `~/.custom.zsh`, `~/system-update.sh`, `~/.config/{,zorin-,GNOME-}xdg-terminals.list` (kitty), `~/.config/environment.d/90-session.conf`, `~/.config/binstaller/config.yaml` and `~/.config/nerd-fonts-installer/config.yaml` (the files fluxion applies, in `config/`), and the [agent skills](#agent-skills) links |

Deliberately not linked from the clone: `niri.conf.yaml` and everything it links (niri, DankMaterialShell,
danksearch, `90-dms.conf`, `mimeapps.list`, its Alacritty `xdg-terminals.list`), `arch/` and `fedora/` (their
`install.conf.yaml` and `*-system-update.sh`), the old binstaller/nerd-fonts configs (fluxion applies the Zorin ones in
`config/`), and `vencord-settings-backup.json` (imported by hand). `paperwm.conf` is a `dconf dump`; after PaperWM
is installed and linked, load it with `dconf load /org/gnome/shell/extensions/paperwm/ < ~/.config/paperwm/paperwm.conf`.

The link defaults are `relink: true, create: true, force: true`. Before dotbot runs, `dotfiles-link.sh` copies every
**real** file or directory at a link target (and every symlink that points elsewhere) with `cp -a` to
**`~/.zorin-bootstrap-backup/`**, keeping its path relative to `$HOME` (`~/.zshrc` ->
`~/.zorin-bootstrap-backup/.zshrc`, `~/.claude/skills` -> `~/.zorin-bootstrap-backup/.claude/skills`). An older
backup is never overwritten; a newer, different copy gets a `.YYYYmmdd-HHMMSS` suffix. `create:` gives explicit
modes (0755, and 0700 for `~/.vim/undo-history`), because dotbot-go v0.4.2 otherwise creates directories as 0777.

### `.zshrc` on Zorin: the `~/.custom.zsh` overlay

`~/.zshrc` is the shared file from the clone. It ends with `[ -f ~/.custom.zsh ] && source ~/.custom.zsh`, and
`dotfiles/custom.zsh` is linked there. It carries the Zorin/Ubuntu differences that used to be edits in a copied
`.zshrc`: `~/.cargo/env`, `~/.local/bin` first on PATH (Claude Code, Codex, uv, poetry, starship), `~/.kimi-code/bin`,
pnpm 11's `$PNPM_HOME/bin`, `~/.apps/yq/bin`, the oh-my-zsh `ubuntu` plugin (the shared plugin list has `dnf`), and
the `bootstrap` / `dotfiles` aliases. So the tools the old hand-edited `~/.zshrc` put on PATH (claude, codex, kimi)
stay on PATH; `tests/assertions/dotfiles.sh` checks that an interactive zsh finds them.

### Everyday workflow: edit and commit in `~/.system-bootstrap`

```bash
nvim ~/.config/kitty/kitty.conf          # the link points into ~/.system-bootstrap/.files
cd ~/.system-bootstrap && git add -p && git commit -m "kitty: ..." && git push   # SSH pushurl
just dotfiles-pull                       # later, on any machine: fast-forward the clone
just dotfiles                            # re-link after adding a file or editing a dotbot config (idempotent)
just dotfiles-dry                        # preview (backups + dotbot -n)
just dotfiles-check                      # every link resolves to its source?
```

Zorin-only files (`dotfiles/`) are edited and committed in this repo. A new shared dotfile goes into
`~/.system-bootstrap/.files` (commit it there) plus a `link:` line in `dotfiles/system-bootstrap.conf.yaml`. The
fluxion `dotbot` phase re-runs whenever its probe (`dotfiles-link.sh --check`) finds a missing or wrong link, so
`./bootstrap.sh --only dotfiles` picks up config edits too.

`~/.system-bootstrap/.files/.config/vesktop/vencord-settings-backup.json` is deliberately **not linked**. It is a
backup that you import by hand; see the manual steps below.

---

## Agent skills

My agent skills live in **one real, git-tracked folder**, `dotfiles/agents/skills/`, and every coding agent links
to it (dotbot, `dotfiles/install.conf.yaml`):

| Link | Agent | When |
|---|---|---|
| `~/.agents/skills` | Codex (reads it natively) and the shared location | always |
| `~/.claude/skills` | Claude Code | always |
| `~/.cursor/skills`, `~/.gemini/skills`, `~/.copilot/skills`, `~/.config/opencode/skills` | Cursor, Gemini CLI, Copilot CLI, opencode | only when that agent's directory exists (dotbot `if:`) |

Layout: one folder per skill, and the **folder name must equal the `name:` in its `SKILL.md`** front matter (the
file is always called `SKILL.md`). `dotfiles/agents/skills/README.md` has the details and an example.

```
dotfiles/agents/skills/
├── README.md          # not a skill (outside any skill folder)
├── .gitignore         # ignores synced/ (Claude Code's own cache of claude.ai skills)
└── my-skill/
    ├── SKILL.md       # ---\nname: my-skill\ndescription: ...\n---
    └── scripts/  references/   # optional
```

Verify loop (also run by `tests/assertions/dotfiles.sh`):

```bash
cd ~/.zorin-bootstrap/dotfiles/agents/skills
for d in */; do d=${d%/}; [ "$d" = synced ] && continue
  n=$(sed -n 's/^name:[[:space:]]*//p' "$d/SKILL.md" 2>/dev/null | head -n1 | tr -d "\"'")
  [ "$n" = "$d" ] && echo "ok   $d" || echo "FAIL $d (name: '${n:-missing SKILL.md}')"; done
```

`scripts/link-skills.sh` (POSIX `sh`, `just skills`) does the linking without dotbot, for example after installing
an agent: it points `~/.agents/skills` at the repo folder and `<agent>/skills` at `~/.agents/skills` with
`ln -sfn`, skips agents that are not installed, leaves correct links alone, and **never overwrites a real
directory** (it reports it and exits 1; move it to `~/.zorin-bootstrap-backup/` yourself). `--check` and `--dry-run`
only report.

Notes:

- The first `dotfiles` run replaces the real `~/.claude/skills` directory, after backing it up to
  `~/.zorin-bootstrap-backup/.claude/skills`. It held only `synced/`, Claude Code's cache of claude.ai skills, which
  Claude Code recreates inside the linked folder (git-ignored).
- Codex's bundled skills (`~/.codex/skills/.system`) are never touched. `~/.codex/skills/onboard-new-user` was not
  moved either: it is the Codex app's first-run onboarding skill (it calls app-only tools such as
  `setup_codex_step`), not a skill of mine, and it would not work in the other agents.

---

## Vicinae launcher

Module `vicinae` (`profiles/75-vicinae.yaml`, default sequence, after `gnome`):

| Piece | How |
|---|---|
| Vicinae v0.29.0 | There is no .deb/PPA, and the release tarball is built against Arch's Qt6. The official AppImage (sha256-pinned) is extracted into `/usr/local` by the official install script pinned to tag v0.29.0 (sha256-pinned), run **as root** with `--appimage` and `TERM=dumb` (the script aborts without `TERM`). As root it also sets `cap_dac_override` on `vicinae-input-server` and loads `uinput` (snippets, paste). The probe is `vicinae version` = v0.29.0 |
| Server | The systemd **user** unit the installer ships (`/usr/local/lib/systemd/user/vicinae.service`, `vicinae server --replace`, `WantedBy=graphical-session.target`), enabled and started; `vicinae ping` must answer. `vicinae toggle` does not start a server by itself |
| GNOME extension | `vicinae@dagimg-dot` v1.7.2 (EGO 8594, shells 46-50), needed on GNOME Wayland for clipboard history, the window switcher, paste, centring and close-on-focus-loss. Installed from the pinned GitHub release zip into `~/.local/share/gnome-shell/extensions/`, schemas compiled, added to `enabled-extensions`, all without the GNOME Shell confirmation dialog. **Active after the next log out/in** (the `session` checkpoint) |
| `Super+D` | A GNOME custom shortcut running `/usr/local/bin/vicinae toggle` (Vicinae's own global shortcuts need X11 or ext-hotkey-v1, which Mutter lacks). Zorin's schema override binds `Super+D` to show-desktop, so `show-desktop` is set to `['<Primary><Super>d', '<Primary><Alt>d']` first (undo: `gsettings reset org.gnome.desktop.wm.keybindings show-desktop`) |

After the re-login, press `Super+D` and type straight away: the launcher should open centred and focused (GNOME's
`focus-new-windows` is `smart`). Do not start "Vicinae" from the app grid: its launcher runs
`vicinae server --replace` and fights the systemd copy. Logs: `journalctl --user -u vicinae`. Bumping and undoing are
described in the profile header.

---

## Testing

`tests/` exercises **the same orchestration** (`bootstrap.sh`) on test profiles that mirror production 1:1:

- `tests/gen-test-profiles.sh` generates `tests/generated/<same path>` from every file in `profiles/`
  (python3 + PyYAML, `tests/lib/gen_test_profiles.py`). The only changes: `prompt-logout` / `requires-new-shell`
  restart policies are removed, `interrupt` / `manual` / `shell-reload` steps are removed (and phases left empty,
  with their `dependsOn` references), `confirm:` guards are dropped, and relative `config:` paths become absolute.
  Each generated file starts with a comment that lists exactly what changed. Today that is the `session` logout
  checkpoint and the three manual reminders in `post-checks`.
- `tests/generated/` is **git-ignored**: it is derived data, regenerated by `bootstrap.sh --test` and
  `tests/run-tests.sh` before every use (and `--check` shows a diff if it were stale), so it cannot drift.
- `./bootstrap.sh --test ...` runs those profiles with state names `test-NAME`, so production state
  (`~/.local/share/fluxion/state/NAME.json`) is untouched.

`tests/run-tests.sh` stages (all by default, `--stages a,b` to pick):

| Stage | What passes |
|---|---|
| `validate` | `fluxion validate --strict` + lint of each selected test profile, and `bootstrap.sh --test --dry-run` exits 0 with no checkpoint |
| `apply` | `bootstrap.sh --test --only MODULES` exits 0 for every module |
| `idempotency` | The same run again: every module exits 0 and fluxion's summary reports **`0 ok · 0 failed`** (nothing ran). `--strict-idempotency` adds `--re-probe`, so recorded state is ignored and every item must be satisfied by its live probe. Items with no probe by design (`assert` steps, and package `actions` such as apt `update`) always run and are not counted; the items that did run again are listed in `reprobe-ran-MODULE.txt` in the log dir |
| `assert` | `tests/assertions/MODULE.sh`: the real outcome. Packages from the profile's own lists, commands at their pinned versions, apt sources and keyrings, docker/containerd active and `docker run --rm hello-world` (with `sudo -n` until the docker group is active), `~/.system-bootstrap` clone and pushurl, every dotbot link resolving into the clone or this repo, skills links + the name check, an interactive zsh finding claude/codex/kimi, gsettings for `Super+1..9` (plus a scan for any other holder), `Super+D` -> vicinae and show-desktop, the vicinae user service and `ping`, login shell and group membership in `/etc/group` |

```bash
tests/run-tests.sh --list                          # modules, generated profiles, GUI needed?
tests/run-tests.sh --stages validate --with-optional   # read-only (just test-validate)
tests/run-tests.sh --assert-only --only gnome,vicinae  # read-only (just test-assert ...)
tests/run-tests.sh --only gnome,vicinae            # apply + idempotency + assert for two modules
tests/run-tests.sh                                 # the whole default sequence
tests/run-tests.sh --container                     # base,apps,toolchains,binaries,shell,dotfiles,wallpapers
                                                   # in a throwaway ubuntu:24.04 container (needs docker)
FLUXION_BIN=~/Projects/Github/fluxion.cr-zorin-fixes/bin/fluxion tests/run-tests.sh ...   # another fluxion
```

- `FLUXION_BIN` defaults to the patched dev build `~/Projects/Github/fluxion.cr-zorin-fixes/bin/fluxion` when it
  exists, else the fluxion on PATH. `ASSERT_NETWORK=0` skips checks that need the network (`apt-get update`,
  `docker run`, the clone's `ls-remote`).
- Logs, the per-stage `--report` files and `summary.tsv` go to `tests/logs/<timestamp>/` (git-ignored; `--log-dir`
  to change).
- Each assertion file also runs on its own: `tests/assertions/vicinae.sh`.
- Container mode builds `tests/container/Dockerfile` (same user name, uid and home path as the host, passwordless
  sudo **inside the image only**) and runs the non-GUI modules there with `ASSERT_CONTEXT=container`, which skips
  checks that need systemd, snapd, flatpak or a GNOME session. Modules that need the desktop session are refused.
- fluxion 0.3.1 reports every **apt package as "not installed"** in its probes (it replaces the tab in
  `dpkg-query`'s output with a space before parsing it; see the caveats table). Plain idempotency is unaffected (the
  second run skips completed phases), but `--strict-idempotency` needs a fluxion with that fixed.

---

## Adding or changing items

Put a new item in the module where it belongs, keep it in the right phase, then validate:

| To add | Where | How |
|---|---|---|
| An Ubuntu-archive package | `profiles/00-base.yaml` | Add the name to the matching `apt-*` phase list. Check it exists first: `apt-cache policy NAME` |
| A third-party apt app | `profiles/10-apps.yaml` | New leaf phase `dependsOn: [host-check]` with an `apt-repository` step (pin `checksum` of the key: `curl -fsSL KEY_URL \| sha256sum`) followed by an `apt-packages` step |
| A flatpak | `profiles/60-desktop-apps.yaml` | Add the full app ID to a `flatpak-*` category phase (`flatpak remote-info flathub ID` to check it) |
| A snap | `profiles/60-desktop-apps.yaml`, phase `snaps` | Strict snaps: `tool-packages` with `backend: snap`. Classic snaps: a `commands` item with `sudo: true`, `run: snap install NAME --classic` and `unless: snap list NAME` |
| A Rust CLI | `profiles/30-toolchains.yaml`, phase `rust-crates` | Add the crate name (installed with cargo-binstall) |
| A release binary in `~/.apps` | `config/binstaller.yaml` | Add a binstaller entry (pin `version` + `checksum` when possible), then add its path to the `binaries-binstaller` probe in `profiles/40-binaries.yaml`, its `bin` dir to PATH (shared: `~/.system-bootstrap/.files/.zshrc`; Zorin-only: `dotfiles/custom.zsh`), and a check to `tests/assertions/binaries.sh` |
| A Nerd Font | `config/nerd-fonts/0N-*.yaml` and `all.yaml` | Keep each batch under ~15 families (fixed 15 min timeout per batch) |
| A curl/installer script | the module that owns the tool | Prefer `shell-scripts` with `url` + `sha256` (+ `shell: bash` if it needs bash). Otherwise a `commands` item with `creates:` and a `probeCommand` so re-runs skip it |
| A shared dotfile | `~/.system-bootstrap/.files/` + `dotfiles/system-bootstrap.conf.yaml` | Add and commit the file in the clone (push from there), add a `link:` entry here, then `just dotfiles` |
| A Zorin-only dotfile | `dotfiles/` + `dotfiles/install.conf.yaml` | Add the file and a `link:` entry, then `just dotfiles` |
| An agent skill | `dotfiles/agents/skills/<name>/SKILL.md` | Folder name = `name:` in the front matter; commit it. Every agent sees it through the links |
| A GNOME setting | `profiles/70-gnome.yaml` | Add a `gsettings set` line to the script and extend its `probeCommand` if it matters |

Rules the existing profiles follow:

- Step names are unique across **all** profiles (prefix them with the module: `apps-...`, `docker-...`).
- Every phase lists its real prerequisites in `dependsOn` (at least `host-check`). Lists that may partly fail go in a
  **leaf phase** (nothing depends on it) with `execution: { continueOnError: true }`.
- Shell text must not contain `${...}` profile variables; pass them through `args:` / `env:` and use plain `$HOME`.
- Anything that needs root uses `sudo: true` (fluxion calls `sudo -n`; `bootstrap.sh` keeps the ticket warm).
- Every module has post-conditions in `tests/assertions/<module>.sh`; extend them when you add something that
  matters. The test profiles regenerate themselves.
- A brand-new module file: add it to `DEFAULT_PROFILES` (or `OPTIONAL_PROFILES`) in `bootstrap.sh`, add
  `tests/assertions/<module>.sh` (function `assert_<module with _ for ->`), copy the
  `host-check` phase from any existing profile, and give it a unique `metadata.name`.

Then check it:

```bash
just validate                                   # or: scripts/validate-all.sh (prod + test profiles, scripts)
./bootstrap.sh --dry-run --only NAME            # exact commands, no changes
tests/run-tests.sh --only NAME                  # apply + idempotency + assertions on the test profile
./bootstrap.sh --only NAME                      # apply
```

---

## Re-running and idempotency

- `bootstrap.sh` always applies with **`--skip-already-installed`**. An item is skipped when the fluxion state
  records it as succeeded, or when its probe reports it as present. Probes include `dpkg-query`, `flatpak info`,
  `snap list`, file existence checks and the `probeCommand` of each step.
- A phase that completed with an unchanged fingerprint (a hash of its config, including delegated config files and
  inline scripts) is skipped outright. When you change anything in a phase, it is walked again, but with
  `--skip-already-installed` each item whose probe passes is still skipped. For steps with a coarse probe (binstaller,
  Nerd Fonts) use `just refresh-binaries` / `just refresh-fonts`, or run `fluxion apply ... --phase NAME` without
  `--skip-already-installed`.
- A failed phase is never recorded as complete, so the next run retries it.
- Each module keeps its own state:

  ```bash
  fluxion state show docker                     # what was recorded
  fluxion state path docker                     # ~/.local/share/fluxion/state/docker.json
  fluxion state forget --profile docker --phase docker-engine   # re-run one phase next time
  fluxion state reset docker --force            # forget everything for the module (just state-reset docker)
  ```

- `tests/run-tests.sh` checks this for real: after the test apply, a second run must report `0 ok · 0 failed` for
  every module (see [Testing](#testing)).
- `--re-probe` ignores the recorded state and trusts only live probes. It is useful after removing something by
  hand.
- To run one module: `./bootstrap.sh --only toolchains`. To resume after a failure: `./bootstrap.sh --from shell`.
- To run fluxion directly without the wrapper, use the same state name and export the same PATH (see
  `bootstrap.sh`):

  ```bash
  sudo -v && fluxion apply -c profiles/30-toolchains.yaml --profile toolchains --skip-already-installed
  ```

---

## fluxion 0.3.1 caveats handled here

| Caveat | How this repo handles it |
|---|---|
| **Zorin is not detected as `ubuntu`** (`ID=zorin`) | `target.os` says ubuntu/noble, and no step uses `when: {distribution: ubuntu}`. Every profile's `host-check` asserts noble and `apt-get` |
| **`dotfiles-apply` is broken**: it passes `--config`, but dotbot-go only accepts `-c` (and it takes one config, while two base directories are needed here) | `80-dotfiles` runs `scripts/dotfiles-link.sh` from a `shell-scripts` step: `dotbot -d ~/.system-bootstrap/.files -c dotfiles/system-bootstrap.conf.yaml`, then `dotbot -d dotfiles -c dotfiles/install.conf.yaml`, with `--check` as the probe |
| **apt package probes always say "not installed"**: the output sanitizer turns the tab in `dpkg-query -f='${Status}\t${Version}'` into a space, so the probe never sees `install ok installed` (in 0.3.1 and current main, `src/fluxion/executor/probe.cr` + `redaction.cr`) | `--skip-already-installed` still skips completed phases, and `apt-get install` of an installed package changes nothing. Assertions check packages with `dpkg-query` directly. `tests/run-tests.sh --strict-idempotency` needs a fluxion with this fixed |
| **fluxion never prompts for sudo**: it only uses `sudo -n` | `bootstrap.sh` runs `sudo -v` once, then a keep-alive loop runs until exit. Ubuntu's sudo ticket lasts 15 minutes and TeX Live alone takes longer |
| **PATH is read once, at start-up** | One fluxion process per module, and `bootstrap.sh` exports all future tool directories up front, so later modules see earlier installs |
| **`when:` is evaluated at load time** | Profiles do not use `commandExists` guards on tools that the same run installs |
| **SDKMAN's installer needs bash**, but the `toolchain` kind uses `sh` | SDKMAN, nvm and pyenv use `shell-scripts` with `url`, `sha256` and `shell: bash` |
| **A failed phase blocks everything that depends on it** | `dependsOn` lists only real prerequisites, fragile lists sit in leaf phases, and list phases use `continueOnError: true` |
| **`${...}` is refused in shell text** | Scripts use plain `$HOME` and take profile values through `args`/`env` |
| **`apt-repository`/`gpg-key` always dearmor** | Every keyring path ends in `.gpg`. An `.asc` path would end up holding binary data and break apt |
| **`prompt-logout` stops the run** (in dry-run too) | It appears only in the last module, `session`; the generated test profiles drop it |
| **`gext install` pops a GNOME Shell confirmation dialog** (D-Bus backend) and blocks the run | `gnome-extensions` uses `gext -F install` (filesystem backend); Vicinae's extension is unpacked from a pinned zip. Probes check files + `enabled-extensions`, because `gnome-extensions info` only knows new extensions after a re-login |
| **No `DEBIAN_FRONTEND`** | Debconf is preseeded for mscorefonts and wireshark |
| **Checksum pins go stale** when upstream scripts change | The run fails loudly with a digest mismatch. Recompute the pin (see [Updating](#updating)) |

---

## Manual steps after the bootstrap

0. **Log out and back in (or reboot)** after the `session` checkpoint. Until then you are not in the `docker`,
   `libvirt` and `kvm` groups (use `sudo docker ...` or `newgrp docker`), and new terminals still start your old
   login shell. If `session` failed, change the shell by hand with `chsh -s /usr/bin/zsh`. Then run
   `./bootstrap.sh --only post-checks`.

`./bootstrap.sh --only post-checks` reminds you about the next three.

1. **GitHub CLI:** run `gh auth login`.
2. **SSH key:** run `ssh-keygen -t ed25519 -C "balyszyn@gmail.com"`, then `gh ssh-key add ~/.ssh/id_ed25519.pub`.
   Never copy `~/.ssh` into this repo; `.gitignore` blocks `id_*`, `*.pem` and `*.key`.
3. **Telegram duplicate:** this host has Telegram both as a snap and as the flatpak `org.telegram.desktop`. The
   bootstrap keeps the **snap**, so remove the flatpak with `flatpak uninstall org.telegram.desktop`.
4. **Sign in** to 1Password, Claude Desktop, ChatGPT, Claude Code (`claude`), Codex (`codex`), Kimi (`kimi`), VS
   Code settings sync, Spotify, Discord/Vesktop and Telegram.
5. **Vesktop:** open Vencord settings, go to *Backup & Restore*, and import
   `~/.system-bootstrap/.files/.config/vesktop/vencord-settings-backup.json`.
6. **Brave "GitHub" web app:** in Brave, open github.com, then go to menu → *Cast, save and share* → *Install page as
   app*. Browsers create these web apps themselves, so they cannot be scripted in any sensible way.
7. **Regional formats:** en_GB formats and A4 paper were set in *Settings → Region & Language*, which writes
   `~/.pam_environment`. Set them again there; the file is not managed here.
8. **Claude keyring `.asc`: leave it.** The `claude-desktop` package rewrites
   `/usr/share/keyrings/claude-desktop-archive-keyring.asc` on every upgrade, so deleting it achieves nothing. It is
   harmless: the `claude-desktop.list` written by `apps` has no package marker, so the package leaves it pointing at
   the dearmored `.gpg`.
9. **Optional: 1Password debsig policy.** Ubuntu's dpkg only enforces package signatures when `debsig-verify` is
   set up. To enable verification for 1Password:

   ```bash
   sudo apt install -y debsig-verify
   sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22 /usr/share/debsig/keyrings/AC2D62742012EA22
   curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null
   curl -sS https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
   ```

10. **Neovim:** start `nvim` once so lazy.nvim installs the plugins listed in `lazy-lock.json`.
11. **tmux:** the plugins are already installed by `dotfiles`. Inside tmux, `prefix + I` re-installs them.
12. **droidcam alias:** it needs `scrcpy` 2.2 or newer, which the bootstrap does not install.
13. **Vicinae:** after the re-login press `Super+D` and type straight away; the launcher should open centred with
    keyboard focus. `gnome-extensions info vicinae@dagimg-dot` should now say ACTIVE (clipboard history needs it).
14. **Backups:** anything dotbot replaced is in `~/.zorin-bootstrap-backup/` (same paths as in `$HOME`). Delete it
    once you are happy.

---

## Optional modules

```bash
./bootstrap.sh --only obs                 # OBS Studio + 10 plugins (flatpak)
./bootstrap.sh --only zorin-pro-parity    # the Zorin OS Pro flatpak set, for Core / non-Pro reinstalls
./bootstrap.sh --only gnome-extensions    # gext -F + 6 extensions (run in the GNOME session)
./bootstrap.sh --only wallpapers          # ~109 MB of wallpapers from the old repo
./bootstrap.sh --only post-checks         # after re-login
```

- `obs`: most of the plugins are OBS flatpak extensions. OBS Studio itself comes preinstalled with Zorin Pro, so
  installing it does nothing there.
- `zorin-pro-parity`: installs the 35 flatpaks that Zorin Pro ships (Warp, Foliate, Minder, Xournal++, HandBrake,
  Darktable, Ardour, Mixxx, Scribus, Secrets, and others), split into small phases. It is kept complete on purpose,
  so 12 IDs overlap with `desktop-apps` (Audacity, Kdenlive, Inkscape, Krita, Blender, FreeCAD, Apostrophe, Logseq,
  Gradia, Blanket, NewsFlash) and `obs` (OBS Studio). Already-installed flatpaks are skipped, so the overlap costs
  nothing.
- `gnome-extensions`: dash-to-dock (conflicts with the Zorin Taskbar), tilingshell (tiling) and
  appindicator/status-icons (Zorin ships them) are deliberately left out. `gext -F install` unpacks each extension
  and adds it to `enabled-extensions` without the GNOME Shell confirmation dialog that plain `gext install` shows.
  Log out and back in afterwards: GNOME Shell on Wayland only loads new extensions at login.
- `wallpapers`: the images stay out of this repo.

---

## Not ported, and why

| Item | Reason |
|---|---|
| niri, DankMaterialShell/dms/danksearch, PaperWM itself, sway, waybar, fuzzel, rofi, hypr*, COSMIC/SDDM tweaks, the `multibg-wayland` crate, `assets/icons`, `niri.conf.yaml` | Tiling and Arch desktop setup. Zorin keeps its own GNOME desktop. (`paperwm.conf` is still linked from the clone, but only if you install PaperWM yourself) |
| dash-to-dock, tilingshell extensions | Conflict with the Zorin Taskbar and layouts; tiling is out of scope |
| podman, podman-docker, toolbox, buildah | Replaced by Docker CE and distrobox |
| RPM Fusion, the ffmpeg swap, fedora-workstation-repositories, the Fedora/Arch dotbot overlays, `fedora-/arch-system-update.sh` | Only apply to Fedora or Arch. Ubuntu's `ubuntu-restricted-extras` covers the codecs, and `zorin-system-update.sh` replaces the update scripts |
| Brave flatpak | Brave is Zorin's default browser (apt) |
| `dev.zed.Zed` flatpak | Zed comes from `zed.dev/install.sh`, as on the host |
| `org.telegram.desktop` flatpak | The snap is kept |
| `com.oguzhaninan.Stacer` flatpak | Removed from Flathub. Stacer comes from apt instead |
| apt `kitty`, `neovim` (0.9.5), `yq` (Python flavour), `fd-find`, `gnome-shell-extension-manager` | Replaced by upstream kitty, binstaller's neovim and mikefarah yq, cargo's `fd`, and the Extension Manager flatpak |
| `mimeapps.list` | Only the niri config links it in the old repo, and Zorin/GNOME manages it |
| coursier, platformio, deno, nimble, JetBrains Toolbox, Android SDK, opencode, mill, envman, `~/.fzf.zsh`, scrcpy | Referenced by the old `.zshrc`, but nothing installed them and they do not appear in the host history. The `.zshrc` lines stay behind guards, so installing any of them later just works |
| Automatic 1Password debsig policy | Not enforced by dpkg on Ubuntu unless you set up debsig-verify (see the manual steps) |
| The old repo's formatting CI (shfmt, stylua, prettier, ...) | fluxion `validate`/`lint` together with `scripts/validate-all.sh` is the quality gate here |

---

## Updating

**Day to day:** run `update` (a zsh alias for `~/system-update.sh`) or `just update`. It updates apt, snap, flatpak,
rustup, juliaup, SDKMAN, nvm/Node LTS, mamba, uv, pnpm, Poetry, oh-my-zsh and, optionally, the cargo crates. Each section
is skipped when its tool is missing, and one failure does not stop the rest.

**`~/.apps` binaries and Nerd Fonts:** `./bootstrap.sh --only binaries` does **not** refresh them. bootstrap.sh
always passes `--skip-already-installed`, and in that mode fluxion skips an item whose probe passes, even when the
phase's config changed. The binstaller probe passes as soon as all 13 executables exist, and each font probe passes
once `fc-list` finds its family. Run the phases without that flag instead (no sudo needed):

```bash
just refresh-binaries   # fluxion apply -c profiles/40-binaries.yaml --profile binaries --phase binstaller --no-tui
just refresh-fonts      # ... --phase fonts-core,fonts-more,fonts-rest,fonts-noto --no-tui
```

So to bump a tool, edit its version (and checksum) in `config/binstaller.yaml`, then run `just refresh-binaries`.
The `latest-url` tools (minikube, xplr, kubectl, neovide, neovim, yq) move to the newest release on every refresh.

**Bumping pins** (installer scripts, keys, tarballs). Most remote scripts and keys are pinned by sha256, and git
repos by commit. When upstream changes them, fluxion fails with a digest mismatch, which is intended. To bump a pin:

```bash
curl -fsSL https://sh.rustup.rs | sha256sum                  # installer scripts / keys / descriptors
git ls-remote https://github.com/tmux-plugins/tpm HEAD       # git-repo refs (40-hex)
```

Then edit the value in the profile and run `just validate`.

| Pin | File |
|---|---|
| Go version and tarball sha256 (`spec.vars`). **Also** change the literal `go1.27.1 ` in the `go-toolchain` probeCommand: probes cannot use `${...}`, and a stale probe re-downloads Go on every run | `profiles/30-toolchains.yaml` |
| rustup, cargo-binstall script (commit and sha), SDKMAN, nvm tag and sha, pyenv, juliaup | `profiles/30-toolchains.yaml` |
| oh-my-zsh revision and sha, zsh plugin commits, TPM commit | `profiles/50-shell.yaml` |
| Docker / GitHub CLI / Claude Desktop key sha256; Microsoft / 1Password key fingerprints | `profiles/20-docker.yaml`, `profiles/10-apps.yaml` |
| distrobox version and tarball sha256 (`spec.vars`). **Also** change the literal `distrobox: 1.8.2.5` in the `docker-distrobox` probeCommand | `profiles/20-docker.yaml` |
| Crystal OBS key sha256 (the key expires 2027-09-22) | `profiles/10-apps.yaml` |
| Flathub descriptor sha256 | `profiles/60-desktop-apps.yaml`, `profiles/optional/obs.yaml`, `profiles/optional/zorin-pro-parity.yaml` |
| binstaller tool versions | `config/binstaller.yaml` |
| Vicinae version, AppImage and install-script sha256, GNOME extension zip version and sha256 (also the literal versions in the probes) | `profiles/75-vicinae.yaml` |
| fluxion itself | `FLUXION_VERSION` in `bootstrap.sh`. Read the fluxion changelog before bumping it, because the caveats above are specific to 0.3.1 |

---

## Troubleshooting

**Finding what failed:**

```bash
./bootstrap.sh --failed --only docker                           # missing / failed items (just failed docker)
fluxion explain -c profiles/20-docker.yaml --profile docker --phase docker-engine
fluxion status  -c profiles/20-docker.yaml --profile docker --failed
fluxion state show docker                                       # ~/.local/share/fluxion/state/docker.json
./bootstrap.sh --only docker --show-output --no-tui            # re-run, echoing each command's output
```

**`apt-get update` fails with `crystal ... does not have a Release file` (exit 100):** the Crystal installer was
piped to `sudo zsh`. zsh keeps the backslashes of `${OBS_PROJECT//:/:\/}`, so
`/etc/apt/sources.list.d/crystal.list` contains `devel:\/languages:\/crystal` (a 404) and
`/etc/apt/trusted.gpg.d/devel_languages_crystal.gpg` is empty. `base` moves both files to `/var/backups` first (phase
`apt-sources-repair`) and `apps` adds the correct repo. To fix it by hand:
`sudo rm -f /etc/apt/sources.list.d/crystal.list /etc/apt/trusted.gpg.d/devel_languages_crystal.gpg`. If you use
that installer again, pipe it to `bash`, not `zsh`.

**A module shows `ok` but nothing was installed:** with `--tui`, pressing `q` at the selector backs out of that module,
and fluxion exits 0. Re-run it without `--tui`.

**"a password is required" / sudo failures part-way:** the keep-alive loop stopped, for example because the
terminal was closed or the machine suspended. Re-run the module, and finished items are skipped.

**Flatpak installs fail with an authorization error:** you are probably running over SSH, or outside the active
local session. Re-run `./bootstrap.sh --only desktop-apps` from a terminal in the GNOME session.

**`gnome` fails its `gnome-session-check`:** the same cause: `gsettings` needs `DBUS_SESSION_BUS_ADDRESS`, which
only the local session has.

**apt or dpkg hangs, or a debconf question appears:** a package asked something that is not preseeded. Finish it by
hand with `sudo dpkg --configure -a`, add a `debconf-set-selections` line to `base-debconf-preseed` in
`profiles/00-base.yaml`, and re-run.

**The dpkg lock is held:** GNOME Software or unattended-upgrades is running. Wait for it, or check with
`sudo lsof /var/lib/dpkg/lock-frontend`, then re-run.

**v4l2loopback DKMS build fails:** the module has to build against the running HWE kernel, 7.0 at the moment.
Check that `linux-headers-$(uname -r)` is installed and look at `sudo dkms status`. Secure Boot may ask you to
enrol a MOK key on the next boot. A failure here only affects the `apt-media` phase.

**`docker: permission denied ... docker.sock`:** the `docker` group only applies after you log out and back in. For
the current shell, use `newgrp docker`.

**The `session` module failed and there was no log-out prompt:** adding the groups failed, usually because docker
was not installed and the `docker` group does not exist. Fix `./bootstrap.sh --only docker` first, then run
`./bootstrap.sh --only session`.

**`git status` in `~/.system-bootstrap` shows changes in `.files/.zshrc`:** an installer ran after dotbot and
appended to the linked file. Check with `git -C ~/.system-bootstrap diff .files/.zshrc`. Move what you want to keep
into `dotfiles/custom.zsh` (Zorin-only) or commit it in the clone (shared), and discard the rest with
`git -C ~/.system-bootstrap checkout .files/.zshrc`. `system-bootstrap-sync.sh` never overwrites such edits: a
fast-forward that would touch them is refused with a warning.

**`dotfiles` fails with "~/.system-bootstrap exists but is not a git clone" (or a clone of another repo):** move that
directory away and re-run `./bootstrap.sh --only dotfiles`; the script never deletes it.

**`Super+1..9` does nothing:** something else still grabs the keys. `tests/assertions/gnome.sh` lists every gsettings
key holding `Super+N`; the usual culprit is a Zorin Dash/Taskbar `hot-keys=true` after a Zorin update. Re-run
`./bootstrap.sh --only gnome`.

**`Super+D` still shows the desktop / does nothing:** check `gsettings get org.gnome.desktop.wm.keybindings
show-desktop` (must not contain `<Super>d`) and `systemctl --user status vicinae` (`vicinae toggle` needs the
server). `tests/assertions/vicinae.sh` checks all of it.

**`tool-packages` says its backend is missing** (`cargo-binstall`, `pipx`, ...): fluxion was started without the
exported PATH. Always go through `./bootstrap.sh` or `just`.

**A checksum or digest mismatch:** an upstream installer changed. Verify the new file and update the pin (see
[Updating](#updating)).

**The profile is refused as invalid (exit 3):** run `just validate` to see every error at once, together with its
YAML path.

---

Old repo: [w0rxbend/system-bootstrap](https://github.com/w0rxbend/system-bootstrap) ·
fluxion docs: <https://worxbend.github.io/fluxion.cr/>
