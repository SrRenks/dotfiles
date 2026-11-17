# Dependencies and integrations

What has to exist on a machine before `reddoted` looks like the screenshots, and
what breaks, visibly or silently, when it does not.

This page is the audit behind [`deps/deps.toml`](../deps/deps.toml). The manifest
is the source of truth; this page is the reasoning. Verify any machine with:

```sh
python3 deps/check.py          # report
python3 deps/check.py --quiet  # only problems, exit 1 if a required one is missing
```

## Four findings that shaped this repo

1. **`reddoted/install.sh` does not describe the machine it runs on.** Ten
   packages it declares are not installed here (including `starship`, `direnv`,
   `swappy`, `trash-cli`, `ydotool`, `sddm`); 57 of its 67 do install correctly.
2. **It also misses things its own configs call**, `fd`, `udisks2`,
   `pacman-contrib`, `vscodium`, `flatpak`, and the whole terminal stack. A fresh
   machine gets a desktop with dead corners.
3. **`starship` is not installed on the dev machine.** `~/.config/starship.toml`
   is linked and correct, and `fish` silently skips the prompt because the
   `command -v starship` guard fails. The Glyph prompt has not actually been
   running.
4. **`power-profiles-daemon` and TLP are mutually exclusive**, and
   `reddoted` installs the former while the machine runs the latter.

## How this was measured

| |
| --- |
| `pacman -Q` / `pacman -T` for every declared package (`-T` resolves provides, so `codium` matches `vscodium`) |
| `grep` across `*.qml`, `*.lua`, `*.sh`, `*.fish` in `reddoted/` for every quoted command, plus `exec_cmd` / `execDetached` sites |
| `config/quickshell/glyph/system/package-updates.sh` read directly, it is the shell's own probe |
| `config/quickshell/glyph/prefs/pages/SystemPage.qml`, the shell already checks six optional dependencies; this repo must make that check pass |
| `systemctl is-enabled` for every service the shell enables |

## The groups

`deps/deps.toml` holds the full list with a rationale per group. Summary:

| Group | Required | Why it exists |
| --- | --- | --- |
| `base` | yes | `base-devel` (makepkg, for the AUR), git, curl, jq, python3 (the installer itself) |
| `graphics` | yes | Hyprland + Quickshell need a working GL stack; AMD 780M here |
| `session` | yes | compositor, idle, night light, picker, portals, shell, keyring, battery |
| `audio` | yes | PipeWire; `wpctl` is what the volume OSD calls |
| `network` | yes | NetworkManager + BlueZ; Prefs reads `nmcli`, the buds panel reads `bluetoothctl` |
| `power` | yes | TLP (see the conflict section) |
| `shell-tools` | yes | the ~15 CLIs the QML shell shells out to |
| `input` | yes | `ydotool` + `input` group, for "paste clipboard into the field" |
| `terminal` | yes | ghostty, fish, tmux, yazi, starship |
| `terminal-tools` | yes | eza/zoxide/direnv, fd/fzf, bat, 7zip/ffmpeg/poppler, lazygit/mpv/btop/cava/fastfetch |
| `fonts` | yes | JetBrains Mono Nerd + Space Mono + CJK + emoji |
| `icons` | yes | Papirus + adw-gtk3 |
| `apps` | yes | dolphin, pavucontrol, vscodium, named by `variables.lua`, checked by Prefs |
| `aur-theming` | yes | `qtengine`, `darkly-bin`, how Qt apps follow the palette |
| `yazi-extras` | no | `udisks2` (mount plugin), `perl-image-exiftool` (EXIF opener) |
| `updates` | no | `pacman-contrib` → `checkupdates`; without it the widget uses fakeroot |
| `geo` | no | geoclue demo agent, for the weather panel |
| `greeter` | no | SDDM + Glyph theme; this machine boots Hyprland directly |
| `aur-cursor` | no | Bibata cursor |
| `flatpak-apps` | no | Zen browser |

18 required groups, 6 optional, `python3 deps/check.py` prints the live verdict.

## Integration map

What actually calls what. Anything in the right column is a dependency even
though no package list mentions it.

| Subsystem | Binary | Called from | If absent |
| --- | --- | --- | --- |
| Compositor control | `hyprctl` | 27 files (keybinds, rules, bar, OSD) | shell is dead weight |
| Shell IPC | `qs` | `rice` CLI, `Super+Shift+F` glass toggle | toggles do nothing |
| Screenshots | `grim`, `slurp`, `swappy` | `shot/`, keybind `Super+S` | no screenshots |
| Clipboard | `wl-copy`, `wl-paste`, `cliphist` | `clip/Clip.qml`, keybinds | clipboard panel empty |
| Backlight | `brightnessctl` | OSD, media keys | brightness keys dead |
| Media | `playerctl` (`mpris-proxy`), `wpctl` | bar, media panel | no now-playing, no volume |
| Notifications | `notify-send` | 8 files | shell notifications fail |
| Recording | `gpu-screen-recorder` | `shot/`, `Super+R` | no recording |
| Power/battery | `upower`, `tlp`, `reddot-tlp` | bar, Prefs BATTERY, THINKPAD | no battery %, no fan control |
| Radio | `rfkill` | network panel | no airplane mode |
| Location | geoclue agent | `execs.lua` at startup | weather has no city |
| Type into field | `ydotool` | `keybinds.lua:247` | paste-into-field silently fails |
| UPDATES widget | `pacman`, `checkupdates`/`fakeroot`, `yay\|paru`, `flatpak` | `system/package-updates.sh` | counts stay "?" |
| Qt theming | `qtengine`, `darkly-bin` | palette sync | Qt apps ignore the palette |
| Terminal → yazi | `yazi` | `SUPER+E`, `inode/directory`, tmux popup, fish `Ctrl+O` | no file manager |
| yazi previews | `7z`, `ffmpeg`, `pdftoppm`, `magick`, `bat`, `fd`, `jq` | `config/yazi/yazi.toml` | rows show "no preview" |
| yazi mount | `udisksctl` (udisks2) | `mount.yazi` | `M` opens an empty list |
| tmux popups | `yazi`, `lazygit`, `btop`, `fzf` | `config/tmux/tmux.conf` | popup exits immediately |
| fish pickers | `fzf`, `fd`, `rg`, `bat` | `conf.d/05-env.fish`, `fif.fish` | `Ctrl+T`/`Alt+C` degrade |
| Prompt | `starship` | `conf.d/10-shell.fish` | silently falls back to fish's prompt |
| Installer side | `fc-cache`, `gsettings`, `xdg-mime`, `update-desktop-database` | `install.sh` | fonts/mime not registered |

The last row of the terminal block is the important one: `reddoted`'s own
`install.sh` sets the palette but never installs the terminal tools it now
configures. That is exactly the gap this repo exists to close.

## Known gaps in `reddoted`

Recorded in the manifest as `[[gap]]`, so the bootstrap installs them and
upstream can be told.

| Missing | Breaks |
| --- | --- |
| `pacman-contrib` | UPDATES widget does a slow fakeroot refresh instead of `checkupdates` |
| `udisks2` | yazi mount plugin, Dolphin removable media |
| `fd` | yazi `search --via=fd`, fzf file list |
| `tmux yazi fzf bat 7zip ffmpeg poppler lazygit mpv` | the entire terminal stack added in `config/` |
| `vscodium` | `variables.lua` opens `codium`; Prefs reports it missing |
| `flatpak` | Zen browser, flatpak update count |

## Declared by `reddoted` but absent here

Ten, so a "run install.sh and you're done" story is not true today:
`sddm`, `geoclue`, `power-profiles-daemon`, `swappy`, `libqalculate`,
`ydotool`, `trash-cli`, `starship`, `direnv`, `fd`, plus the AUR pair
`qtengine`, `darkly-bin`.

## Conflicts

| Pair | Resolution |
| --- | --- |
| `tlp` ↔ `power-profiles-daemon` | Both own CPU/GPU power state. This machine runs TLP (`tlp` enabled, `reddot-tlp` present, ThinkPad fan curve in Prefs). The bootstrap installs TLP and skips PPD; `reddoted`'s `services()` enabling PPD is wrong for this machine. |
| `ydotool` ↔ `dotool` | Same job, both need `uinput`. The committed keybind says `ydotool`; `dotool` is what happens to be installed here. The manifest follows the config, not the accident. |

## Version floors

The configs are validated against these; below them something degrades silently.

| | Floor | Here | What needs it |
| --- | --- | --- | --- |
| hyprland | 0.55 | 0.57.2 | `bindin` catchall behaviour noted in `keybinds.lua` |
| quickshell | 0.3.2 | 0.3.2 | `ShellRoot`, `GlyphPalette` |
| ghostty | 1.4.0 | 1.4.0 | every option in `config/ghostty/config` |
| tmux | 3.8 | 3.8 | `theme detect`, `pane-scrollbars`, `pane-status-*` |
| yazi | 26.9.1 | 26.9.1 | config schema; `ya pkg` needs ≥ 25.5.31 |
| fish | 4.0 | 4.9.3 | `conf.d/` layout, current builtins |
| starship | 1.20 | **absent** | `right_format` in fish, `enable_transience` |

## What happens to the current `SrRenks/dotfiles`

The repo being replaced is small: `zsh/.zshrc` (zinit), `tmux/.tmux.conf`, and a
nested clone of `maboroshin/qBittorrentDarktheme` with its own `.git`.

Live symlinks that point into it right now:

| Link | Target | Fate |
| --- | --- | --- |
| `~/.tmux.conf` | `~/dotfiles/tmux/.tmux.conf` | repointed at `reddoted/config/tmux/tmux.conf` |
| `~/.zshrc` | `~/dotfiles/zsh/.zshrc` | **would dangle**, decide: keep a `zsh/` here, or drop it (fish is the shell) |
| `~/dotfiles/qBittorrentDarktheme` | own remote | not a dotfile; keep as its own clone or drop |

Nothing else in the old repo is live.
