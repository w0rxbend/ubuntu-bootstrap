# zorin-bootstrap

This repo sets up my workstation on **Zorin OS 18 Pro** (Ubuntu 24.04 "noble" base, GNOME, amd64) using
[fluxion](https://worxbend.github.io/fluxion.cr/) 0.3.1.

It ports the Arch and Fedora scripts from
[w0rxbend/system-bootstrap](https://github.com/w0rxbend/system-bootstrap) to declarative fluxion profiles. It also
reproduces everything I installed by hand on the current Zorin install, as found in the bash and zsh history, the
apt log, and the snap and flatpak lists. The same tools stay in charge of their own jobs:

- **dotbot** (dotbot-go) links the dotfiles.
- **nerd-fonts-installer** installs the Nerd Fonts.
- **cargo-binstall** installs the Rust CLI tools.
- **binstaller** installs the pinned release binaries in `~/.apps`.
- **SDKMAN**, **nvm**, **pyenv** and the other language installers work as before.

The desktop is Zorin's own GNOME. Nothing from the tiling or Arch desktop setup is included (niri, DMS, sway,
PaperWM, waybar and so on), and **Docker CE replaces podman**.

---

## Contents

- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [Layout](#layout)
- [Modules](#modules)
- [Full inventory](#full-inventory)
- [Docker instead of podman](#docker-instead-of-podman)
- [Dotfiles with dotbot](#dotfiles-with-dotbot)
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
a **log-out checkpoint** (fluxion exit code 75). Log out and back in, or reboot, then run:

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
               [--only a,b | --from NAME] [--yes] [--no-tui] [--show-output] [--re-probe]
```

| Flag | Effect |
|---|---|
| *(none)* | Runs `fluxion apply --profile NAME --skip-already-installed` for every default module, in order |
| `--dry-run` | Runs `fluxion dry-run --no-tui`: prints the exact commands and changes nothing. No sudo |
| `--validate` | Runs `fluxion validate --strict` and `fluxion lint` on each selected module |
| `--plan` | Runs `fluxion plan --format tree` |
| `--status` / `--failed` | Runs `fluxion status --summary` / `--failed`: read-only live probes |
| `--list` | Lists the modules and their files |
| `--only a,b` | Selects only these modules, default or optional. They always run in table order |
| `--from NAME` | Resumes the default sequence at `NAME` |
| `--yes`, `--no-tui`, `--show-output`, `--re-probe` | Passed through to fluxion |

Before any module runs, the script does these checks and setup steps:

- It refuses to run as root.
- It warns if the repo is not at `~/.zorin-bootstrap`, if you are connected over SSH, or if the host is not
  noble-based.
- It installs fluxion when it is missing and warns if the version is not 0.3.1.
- It exports a PATH that includes every tool location the modules create: `~/.cargo/bin`, `~/.local/bin`,
  `~/.go/bin`, `~/.apps/{dotbot,neovim,yq}/bin`, pnpm and juliaup.
- It runs `sudo -v` once and then refreshes the ticket with `sudo -n -v` every 50 s until the script exits.

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
| `just dotfiles` / `just dotfiles-dry` | Runs dotbot directly: re-links everything, or previews without changing anything |
| `just update` | `~/system-update.sh` (apt, snap, flatpak, rustup, SDKMAN, nvm, ...) |
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
  short.
- `dotfiles` runs late on purpose. Several installers (SDKMAN, juliaup, pnpm, codex, kimi) append lines to
  `~/.zshrc`. Running dotbot after them means those lines land in the throwaway oh-my-zsh template, and dotbot then
  replaces that template with the symlink to `dotfiles/.zshrc`. If dotbot ran first, the installers would edit the
  repo's copy.

Every profile begins with a `host-check` assert that the host is noble-based with `apt-get`. Profiles never use
`when: {distribution: ubuntu}`, because fluxion does not map `ID=zorin` to ubuntu.

---

## Layout

```
~/.zorin-bootstrap/
├── README.md
├── Justfile                      # shortcuts (just is installed by `toolchains`)
├── bootstrap.sh                  # ordered runner: preflight, sudo keep-alive, summary
├── .gitignore  .editorconfig
├── scripts/
│   └── validate-all.sh           # validate --strict + lint on every profile, bash -n on scripts
├── profiles/
│   ├── 00-base.yaml              # base
│   ├── 10-apps.yaml              # apps
│   ├── 20-docker.yaml            # docker
│   ├── 30-toolchains.yaml        # toolchains
│   ├── 40-binaries.yaml          # binaries
│   ├── 50-shell.yaml             # shell
│   ├── 60-desktop-apps.yaml      # desktop-apps
│   ├── 70-gnome.yaml             # gnome
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
└── dotfiles/                     # dotbot-go base directory
    ├── install.conf.yaml
    ├── zorin-system-update.sh    # linked to ~/system-update.sh
    ├── .zshrc .tmux.conf .ideavimrc .wezterm.lua .hidden
    ├── starship.toml alacritty.toml alacritty_theme.toml kitty.conf zathurarc
    ├── nvim/                     # AstroNvim config
    └── .config/{btop,ghostty,zellij,lazygit,lsd,yazi,bottom,vesktop,environment.d,xdg-terminals.list}
```

Relative paths inside a profile resolve from the profile file's own directory. That is why `profiles/*.yaml` refer
to `../config/...` and `profiles/optional/*.yaml` refer to `../../...`.

---

## Modules

Default sequence (`./bootstrap.sh`):

| # | Module | File | What it does |
|---|---|---|---|
| 1 | `base` | `profiles/00-base.yaml` | `apt full-upgrade`, debconf preseeds, about 190 Ubuntu-archive packages (CLI, build, debug, GUI-dev, media, fonts, TeX, desktop, virtualisation), libvirtd, global git config, NTP clock, `bat` symlink |
| 2 | `apps` | `profiles/10-apps.yaml` | Third-party apt apps: GitHub CLI, Claude Desktop, VS Code, 1Password (repo and key), ChatGPT and fastfetch (`.deb`) |
| 3 | `docker` | `profiles/20-docker.yaml` | Docker CE, buildx and the compose plugin from Docker's apt repo, the docker/containerd services, distrobox |
| 4 | `toolchains` | `profiles/30-toolchains.yaml` | rustup, cargo-binstall and 14 crates, Go 1.27.1, SDKMAN and 8 candidates, nvm and Node LTS, pnpm, pyenv, poetry, uv, Miniforge, juliaup, kustomize, helm 4, dotenvx |
| 5 | `binaries` | `profiles/40-binaries.yaml` | binstaller profile (13 tools in `~/.apps`), `nvim`/`vim` links in `/usr/local/bin`, Nerd Fonts in 4 batches |
| 6 | `shell` | `profiles/50-shell.yaml` | oh-my-zsh (pinned) and 3 plugins, TPM, starship, kitty (upstream build and desktop integration), ghostty snap |
| 7 | `desktop-apps` | `profiles/60-desktop-apps.yaml` | Flathub remote, 54 flatpaks in category groups, theia-ide and telegram snaps, Claude Code, Codex and Kimi CLIs, Zed, Paseo |
| 8 | `gnome` | `profiles/70-gnome.yaml` | 9 fixed workspaces, `Super+N` / `Super+Shift+N` bindings, screenshot keys, Zorin Taskbar hot-keys turned off |
| 9 | `dotfiles` | `profiles/80-dotfiles.yaml` | Links the dotfiles with dotbot-go, installs the tmux plugins through TPM, sets up the broot launcher |
| 10 | `session` | `profiles/90-session.yaml` | zsh as login shell, `docker`/`libvirt`/`kvm` groups, **log-out checkpoint** |

Optional modules (`./bootstrap.sh --only NAME`):

| Module | What it does |
|---|---|
| `obs` | OBS Studio and 10 flatpak plugins (DroidCam, background removal, VAAPI, PipeWire video, ...) |
| `zorin-pro-parity` | The 35 flatpaks that Zorin OS **Pro** preinstalls, for a Zorin Core install or a reinstall without Pro |
| `gnome-extensions` | `gext` (pipx) plus user-theme, battery-indicator-icon, notification-icons, tophat, space-bar, AlphabeticalAppGrid |
| `wallpapers` | Sparse clone of the wallpapers from the old repo into `~/.local/share/backgrounds/system-bootstrap` (about 109 MB) |
| `post-checks` | Run after logging back in. Checks the docker group, `docker run hello-world`, the zsh login shell, fonts, nvim and the core CLIs, then reminds you of the manual steps |

---

## Full inventory

The profile files have the exact spec for each item. This section is a quick summary.

### `base`: Ubuntu archive

| Group | Packages |
|---|---|
| core | ca-certificates curl wget gnupg git zsh unzip zip xz-utils fontconfig fuse3 libfuse2t64 software-properties-common debconf-utils apt-transport-https |
| CLI | alacritty bat btop fzf htop tmux wl-clipboard jq net-tools hyperfine asciinema gdu xsensors lm-sensors stress zoxide tig mtr nmap httpie ripgrep pipx stacer tree mediainfo libimage-exiftool-perl imagemagick poppler-utils ffmpegthumbnailer 7zip python3-venv python3-pip python3-dev |
| build | build-essential gcc g++ pkg-config clang clangd clang-format clang-tidy clang-tools llvm llvm-dev libclang-dev libclang-rt-dev lld lldb make cmake meson ninja-build ccache flex bison gperf, plus the -dev libraries that pyenv, Python and Rust builds need (readline, ffi, ssl, zlib, bz2, sqlite3, lzma, tk, ncurses, xml2, xmlsec1, secret) and dfu-util |
| debug | gdb valgrind strace ltrace linux-tools-common linux-tools-generic-hwe-24.04 tshark protobuf-compiler |
| GUI dev | GTK 3/4 and GObject-introspection dev packages, WebKitGTK 6, X11/Xcursor/Xrandr/Xi/Xinerama dev, Mesa/GL/EGL/GBM dev, mesa-utils, mesa-vdpau-drivers |
| media | vlc mpv imv ffmpeg, libav* dev packages, the GStreamer plugin sets (base/good/bad/ugly/libav/vaapi/pipewire), libopenh264-7, VA-API/VDPAU and vainfo, radeontop (AMD GPU), PipeWire and wireplumber, easyeffects, power-profiles-daemon, upower, **ubuntu-restricted-extras** (EULA preseeded), **v4l2loopback-dkms** and HWE headers |
| fonts / TeX | fonts-firacode fonts-font-awesome fonts-noto-core fonts-noto-color-emoji fonts-roboto, texlive-base/latex-base/latex-recommended/fonts-recommended/xetex |
| desktop | gnome-tweaks, shell-extension prefs and extensions, gnome-browser-connector, xdg-desktop-portal-gtk, gnome-keyring, libpam-gnome-keyring, seahorse, gcr, gcr4, zathura (+pdf-poppler), mupdf |
| virt | qemu-system-x86 qemu-utils ovmf libvirt-daemon-system libvirt-clients virtinst virt-manager bridge-utils dnsmasq-base vde2 netcat-openbsd cpu-checker, plus `libvirtd` enabled and started |
| config | git `user.email`, `user.name` = w0rxbend, `pull.rebase=true`, `init.defaultBranch=main`, `core.autocrlf=input`; NTP on and RTC in UTC; `~/.local/bin/bat` pointing to `batcat` |

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

Brave is not touched. It is Zorin 18's default browser and comes from Zorin's apt source.

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
| pnpm | `get.pnpm.io` | `~/.local/share/pnpm` |
| pyenv | `pyenv.run` (sha256-pinned) | `~/.pyenv` |
| poetry / uv | Official installers | `~/.local/bin` |
| Miniforge | Latest `Miniforge3-Linux-x86_64.sh`, batch mode | `~/.miniforge3` |
| juliaup | `install.julialang.org` (sha256-pinned) | `~/.juliaup` |
| kustomize / helm 4 | Upstream install scripts, no sudo | `~/.apps/{kustomize,helm}/bin` |
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
`~/.local/bin`, and `.desktop` files with absolute `Icon`/`Exec` paths. The **ghostty** snap uses classic
confinement. zsh itself comes from `base`, and the login shell change happens in `session`.

### `desktop-apps`

- **Flathub** remote (the descriptor is sha256-pinned; this is a no-op on Zorin, which already has it).
- **Flatpaks** (54 in total, one leaf phase per group, `continueOnError`):
  - browsers: LibreWolf, Chrome, Zen
  - communication: Discord, Zulip, **Vesktop**
  - media: Spotify, Audacity, AudioTube, ncspot, Decibels, Amberol, G4Music
  - graphics: Kdenlive, Inkscape, Krita, Blender, FreeCAD, Godot, LibreCAD, BambuStudio, Exhibit
  - writing: TextPieces, Apostrophe, Bookup, Censor, Logseq
  - dev: Ptyxis, WezTerm, VSCodium
  - system: Extension Manager, Flatseal, Flatsweep, Warehouse, Resources, Refine, Mission Center, Gradia, List,
    Authenticator, Polari, D-Spy, Rewaita, Emblem, Mozilla VPN, NetPeek, **GNOME Boxes**
  - productivity: Sessions, Blanket, Packet, LocalSend, NewsFlash, Dosage, Health
- **Snaps**: `theia-ide` (classic) and `telegram-desktop`.
- **AI CLIs**: Claude Code (`claude.ai/install.sh`), OpenAI Codex (`chatgpt.com/codex/install.sh`), and Kimi Code
  (`code.kimi.com`, run with bash, since running it with zsh failed on this host).
- **Home-dir apps**: Zed (`zed.dev/install.sh`) and **Paseo** (AppImage in `~/Apps`, linked as `~/.local/bin/paseo`).

Items in **bold** were found in this host's history or package logs. Several flatpaks come preinstalled with Zorin
Pro, so installing them does nothing there.

### `gnome`

Turns off dynamic workspaces and sets 9 workspaces. `Super+1..9` switches workspace and `Super+Shift+1..9` moves the
window there. The default `switch-to-application-N` bindings are cleared, and screenshot UI is on `Super+Print` and
`Print`. Zorin Taskbar's `hot-keys` setting is turned off because it grabs `Super+1..9`. The module has to run inside
the logged-in GNOME session and asserts that `DBUS_SESSION_BUS_ADDRESS` is set.

### `dotfiles` and `session`

See [Dotfiles with dotbot](#dotfiles-with-dotbot). `session` sets `/usr/bin/zsh` as your login shell and adds you
to `docker`, `libvirt` and `kvm`. It then asks you to log out.

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

dotbot here is the Go version (**dotbot-go** v0.4.2), installed by binstaller as `~/.apps/dotbot/bin/dotbot`. The
base directory is `dotfiles/` and the config is `dotfiles/install.conf.yaml`. The link defaults are
`relink: true, create: true, force: true`, so an existing file or directory at a target is replaced by the symlink.
That includes the oh-my-zsh template `~/.zshrc` and the empty `~/.config/ghostty/` and `~/.config/kitty/`.

| Linked into `$HOME` | From the repo |
|---|---|
| `~/.zshrc`, `~/.tmux.conf`, `~/.ideavimrc`, `~/.wezterm.lua`, `~/.hidden` | `dotfiles/` |
| `~/system-update.sh` | `dotfiles/zorin-system-update.sh` (the `update` alias) |
| `~/.config/{starship.toml, alacritty/, kitty/kitty.conf, zathura/zathurarc}` | `dotfiles/` |
| `~/.config/nvim` (AstroNvim, with `lazy-lock.json`) | `dotfiles/nvim` |
| `~/.config/{btop, ghostty, zellij, lazygit, lsd, yazi, bottom}` | `dotfiles/.config/...` |
| `~/.config/xdg-terminals.list` (kitty) and `~/.config/environment.d/90-session.conf` | `dotfiles/.config/...` |
| `~/.config/binstaller/config.yaml` | `config/binstaller.yaml` |
| `~/.config/nerd-fonts-installer/config.yaml` | `config/nerd-fonts/all.yaml` |

fluxion and your manual runs therefore **share the same config files**. `binstaller --config
~/.config/binstaller/config.yaml` and `nerd-fonts-installer --config ~/.config/nerd-fonts-installer/config.yaml`
read the repo's files.

The `.zshrc` changes compared with the Fedora version:

- the `ubuntu` oh-my-zsh plugin replaces `dnf`;
- `~/.cargo/env` is sourced;
- every `/home/worxbend` path became `$HOME`;
- pyenv, broot and starship are guarded;
- `~/.apps/yq/bin` and `~/.kimi-code/bin` were added to PATH;
- the `bootstrap` alias now points at this repo.

**Everyday use:**

```bash
just dotfiles        # re-link after editing install.conf.yaml or adding files (idempotent)
just dotfiles-dry    # preview (dotbot -n)
# without just:
~/.apps/dotbot/bin/dotbot -d ~/.zorin-bootstrap/dotfiles -c ~/.zorin-bootstrap/dotfiles/install.conf.yaml
```

Because the targets are symlinks, editing `~/.config/...` edits the repo directly. Commit those changes as usual.

The fluxion `dotfiles` phase only notices changes to its own inline script. Editing `install.conf.yaml` does **not**
make fluxion re-run it, so use `just dotfiles` after such edits.

`dotfiles/.config/vesktop/vencord-settings-backup.json` is deliberately **not linked**. It is a backup that you
import by hand; see the manual steps below.

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
| A release binary in `~/.apps` | `config/binstaller.yaml` | Add a binstaller entry (pin `version` + `checksum` when possible), then add its path to the `binaries-binstaller` probe in `profiles/40-binaries.yaml` and its `bin` dir to PATH in `dotfiles/.zshrc` |
| A Nerd Font | `config/nerd-fonts/0N-*.yaml` and `all.yaml` | Keep each batch under ~15 families (fixed 15 min timeout per batch) |
| A curl/installer script | the module that owns the tool | Prefer `shell-scripts` with `url` + `sha256` (+ `shell: bash` if it needs bash). Otherwise a `commands` item with `creates:` and a `probeCommand` so re-runs skip it |
| A dotfile | `dotfiles/` + `dotfiles/install.conf.yaml` | Add the file and a `link:` entry, then `just dotfiles` |
| A GNOME setting | `profiles/70-gnome.yaml` | Add a `gsettings set` line to the script and extend its `probeCommand` if it matters |

Rules the existing profiles follow:

- Step names are unique across **all** profiles (prefix them with the module: `apps-...`, `docker-...`).
- Every phase lists its real prerequisites in `dependsOn` (at least `host-check`). Lists that may partly fail go in a
  **leaf phase** (nothing depends on it) with `execution: { continueOnError: true }`.
- Shell text must not contain `${...}` profile variables; pass them through `args:` / `env:` and use plain `$HOME`.
- Anything that needs root uses `sudo: true` (fluxion calls `sudo -n`; `bootstrap.sh` keeps the ticket warm).
- A brand-new module file: add it to `DEFAULT_PROFILES` (or `OPTIONAL_PROFILES`) in `bootstrap.sh`, copy the
  `host-check` phase from any existing profile, and give it a unique `metadata.name`.

Then check it:

```bash
just validate                                   # or: scripts/validate-all.sh
./bootstrap.sh --dry-run --only NAME            # exact commands, no changes
./bootstrap.sh --only NAME                      # apply
```

---

## Re-running and idempotency

- `bootstrap.sh` always applies with **`--skip-already-installed`**. An item is skipped when the fluxion state
  records it as succeeded, or when its probe reports it as present. Probes include `dpkg-query`, `flatpak info`,
  `snap list`, file existence checks and the `probeCommand` of each step.
- A phase that completed with an unchanged fingerprint (a hash of its config, including delegated config files and
  inline scripts) is skipped outright. When you change anything in a phase, it runs again.
- A failed phase is never recorded as complete, so the next run retries it.
- Each module keeps its own state:

  ```bash
  fluxion state show docker                     # what was recorded
  fluxion state path docker                     # ~/.local/share/fluxion/state/docker.json
  fluxion state forget --profile docker --phase docker-engine   # re-run one phase next time
  fluxion state reset docker --force            # forget everything for the module (just state-reset docker)
  ```

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
| **`dotfiles-apply` is broken**: it passes `--config`, but dotbot-go only accepts `-c` | `80-dotfiles` runs dotbot from a `shell-scripts` step (`dotbot -d dotfiles -c dotfiles/install.conf.yaml`) |
| **fluxion never prompts for sudo**: it only uses `sudo -n` | `bootstrap.sh` runs `sudo -v` once, then a keep-alive loop runs until exit. Ubuntu's sudo ticket lasts 15 minutes and TeX Live alone takes longer |
| **PATH is read once, at start-up** | One fluxion process per module, and `bootstrap.sh` exports all future tool directories up front, so later modules see earlier installs |
| **`when:` is evaluated at load time** | Profiles do not use `commandExists` guards on tools that the same run installs |
| **SDKMAN's installer needs bash**, but the `toolchain` kind uses `sh` | SDKMAN, nvm and pyenv use `shell-scripts` with `url`, `sha256` and `shell: bash` |
| **A failed phase blocks everything that depends on it** | `dependsOn` lists only real prerequisites, fragile lists sit in leaf phases, and list phases use `continueOnError: true` |
| **`${...}` is refused in shell text** | Scripts use plain `$HOME` and take profile values through `args`/`env` |
| **`apt-repository`/`gpg-key` always dearmor** | Every keyring path ends in `.gpg`. An `.asc` path would end up holding binary data and break apt |
| **`prompt-logout` stops the run** (in dry-run too) | It appears only in the last module, `session` |
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
   `~/.zorin-bootstrap/dotfiles/.config/vesktop/vencord-settings-backup.json`.
6. **Brave "GitHub" web app:** in Brave, open github.com, then go to menu → *Cast, save and share* → *Install page as
   app*. Browsers create these web apps themselves, so they cannot be scripted in any sensible way.
7. **Regional formats:** en_GB formats and A4 paper were set in *Settings → Region & Language*, which writes
   `~/.pam_environment`. Set them again there; the file is not managed here.
8. **Optional: stale Claude keyring.** The host's original `claude-desktop.list` pointed at
   `/usr/share/keyrings/claude-desktop-archive-keyring.asc`. The `apps` module rewrites the list to use a dearmored
   `.gpg` keyring, so the old file is no longer used and can be removed:
   `sudo rm /usr/share/keyrings/claude-desktop-archive-keyring.asc`.
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

---

## Optional modules

```bash
./bootstrap.sh --only obs                 # OBS Studio + 10 plugins (flatpak)
./bootstrap.sh --only zorin-pro-parity    # the Zorin OS Pro flatpak set, for Core / non-Pro reinstalls
./bootstrap.sh --only gnome-extensions    # gext + 6 extensions (run in the GNOME session)
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
  appindicator/status-icons (Zorin ships them) are deliberately left out. Log out and back in afterwards, or restart
  GNOME Shell, then enable the extensions in Extension Manager if needed.
- `wallpapers`: the images stay out of this repo.

---

## Not ported, and why

| Item | Reason |
|---|---|
| niri, DankMaterialShell/dms/danksearch, PaperWM (`paperwm.conf`), sway, waybar, fuzzel, rofi, hypr*, COSMIC/SDDM tweaks, the `multibg-wayland` crate, `assets/icons`, `niri.conf.yaml` | Tiling and Arch desktop setup. Zorin keeps its own GNOME desktop |
| dash-to-dock, tilingshell extensions | Conflict with the Zorin Taskbar and layouts; tiling is out of scope |
| podman, podman-docker, toolbox, buildah | Replaced by Docker CE and distrobox |
| RPM Fusion, the ffmpeg swap, fedora-workstation-repositories, the Fedora/Arch dotbot overlays, `fedora-/arch-system-update.sh` | Only apply to Fedora or Arch. Ubuntu's `ubuntu-restricted-extras` covers the codecs, and `zorin-system-update.sh` replaces the update scripts |
| Brave flatpak | Brave is Zorin's default browser (apt) |
| `dev.zed.Zed` flatpak | Zed comes from `zed.dev/install.sh`, as on the host |
| `org.telegram.desktop` flatpak | The snap is kept |
| `com.oguzhaninan.Stacer` flatpak | Removed from Flathub. Stacer comes from apt instead |
| apt `kitty`, `neovim` (0.9.5), `yq` (Python flavour), `fd-find`, `gnome-shell-extension-manager` | Replaced by upstream kitty, binstaller's neovim and mikefarah yq, cargo's `fd`, and the Extension Manager flatpak |
| `mimeapps.list` | The old scripts never actually linked it, and Zorin/GNOME manages it |
| coursier, platformio, deno, nimble, JetBrains Toolbox, Android SDK, opencode, mill, envman, `~/.fzf.zsh`, scrcpy | Referenced by the old `.zshrc`, but nothing installed them and they do not appear in the host history. The `.zshrc` lines stay behind guards, so installing any of them later just works |
| Automatic 1Password debsig policy | Not enforced by dpkg on Ubuntu unless you set up debsig-verify (see the manual steps) |
| The old repo's formatting CI (shfmt, stylua, prettier, ...) | fluxion `validate`/`lint` together with `scripts/validate-all.sh` is the quality gate here |

---

## Updating

**Day to day:** run `update` (a zsh alias for `~/system-update.sh`) or `just update`. It updates apt, snap, flatpak,
rustup, juliaup, SDKMAN, nvm/Node LTS, mamba, uv, pnpm, Poetry, oh-my-zsh and, optionally, the cargo crates. Each section
is skipped when its tool is missing, and one failure does not stop the rest.

**`~/.apps` binaries:** edit the versions in `config/binstaller.yaml`, then run `./bootstrap.sh --only binaries`.
The changed file changes the phase fingerprint, so the phase runs again. The `latest-url` tools only move when the
phase re-runs. To force that: `fluxion state forget --profile binaries --phase binstaller && ./bootstrap.sh --only
binaries`.

**Bumping pins** (installer scripts, keys, tarballs). Most remote scripts and keys are pinned by sha256, and git
repos by commit. When upstream changes them, fluxion fails with a digest mismatch, which is intended. To bump a pin:

```bash
curl -fsSL https://sh.rustup.rs | sha256sum                  # installer scripts / keys / descriptors
git ls-remote https://github.com/tmux-plugins/tpm HEAD       # git-repo refs (40-hex)
```

Then edit the value in the profile and run `just validate`.

| Pin | File |
|---|---|
| Go version and tarball sha256 (`go-toolchain` args) | `profiles/30-toolchains.yaml` |
| rustup, cargo-binstall script (commit and sha), SDKMAN, nvm tag and sha, pyenv, juliaup | `profiles/30-toolchains.yaml` |
| oh-my-zsh revision and sha, zsh plugin commits, TPM commit | `profiles/50-shell.yaml` |
| Docker / GitHub CLI / Claude Desktop key sha256; Microsoft / 1Password key fingerprints | `profiles/20-docker.yaml`, `profiles/10-apps.yaml` |
| distrobox version and tarball sha256 (`spec.vars`) | `profiles/20-docker.yaml` |
| Flathub descriptor sha256 | `profiles/60-desktop-apps.yaml`, `profiles/optional/obs.yaml`, `profiles/optional/zorin-pro-parity.yaml` |
| binstaller tool versions | `config/binstaller.yaml` |
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

**`git status` shows changes in `dotfiles/.zshrc`:** an installer ran after dotbot and appended to the linked file.
Check with `git -C ~/.zorin-bootstrap diff dotfiles/.zshrc`. Either keep the lines you want (most are already
covered by the guarded blocks) or discard them with `git checkout dotfiles/.zshrc`.

**`tool-packages` says its backend is missing** (`cargo-binstall`, `pipx`, ...): fluxion was started without the
exported PATH. Always go through `./bootstrap.sh` or `just`.

**A checksum or digest mismatch:** an upstream installer changed. Verify the new file and update the pin (see
[Updating](#updating)).

**The profile is refused as invalid (exit 3):** run `just validate` to see every error at once, together with its
YAML path.

---

Old repo: [w0rxbend/system-bootstrap](https://github.com/w0rxbend/system-bootstrap) ·
fluxion docs: <https://worxbend.github.io/fluxion.cr/>
