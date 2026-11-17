# dotfiles

Everything this machine is, in one run: an installer that brings up
[reddoted](https://github.com/SrRenks/reddoted), the Glyph desktop for Hyprland,
together with every package its configs call, and stows the result into `$HOME`.

Made for an `archinstall` minimal: nothing but `base`, your user, and `git`.

```sh
sudo pacman -S --needed git
git clone https://github.com/SrRenks/dotfiles ~/Projects/dotfiles
cd ~/Projects/dotfiles
./install.sh --dry-run        # see the plan
./install.sh                  # or: ./install.sh --stow reddoted --all
```

It runs on a machine that has none of `python`, `curl`, `stow`, `base-devel` or
`sudo`: the first phase installs them, through `su` when `sudo` does not exist
yet, and refuses to start when there is no network to install with.

Two things it cannot do for you: know your `sudo` password, and make `input` and
`video` membership apply without a re-login.

## The interactive installer

```
=== dotfiles install ===
  repo      : /home/renks/Projects/dotfiles
  mode      : Arch, reddoted, Hyprland

=== machine ===
  system    : Arch Linux  x86_64 7.3.4-arch1-2
  gpu       : Advanced Micro Devices [AMD/ATI] HawkPoint1 (amd)
  tooling   : pacman ok, stow ok, git ok, aur yay

=== state ===
  packages  : 8 of 74 required packages missing

  what should this machine have?

    [x] base      build tools, stow, python, AUR helper
    [x] desktop   hyprland, quickshell, portals, keyring
  > [x] terminal  ghostty, fish, tmux, yazi, starship
    [ ] sddm      login greeter + glyph theme

  j/k or arrows move, space toggles, a picks all, enter confirms, q quits
```

It reads the machine first (the GPU family picks the driver set), lets you pick
components, prints the plan, and only then touches anything.

The two rows at the top are presets, and toggling one checks every row it would
install, in place. Uncheck one of its members afterwards and the preset shows
`[~]`, so the menu always says exactly what is selected:

```
  ─ presets
  [~] desktop   reddoted and everything it needs, 74 packages
    [x] terminal  the hub alone, no Hyprland, 23 packages
  ─ system
    [x] base      build tools, stow, python, AUR helper
``` Every phase asks
"is this already true?" first, so a second run is a report and not a reinstall.

Every run writes a log to `${XDG_STATE_HOME:-~/.local/state}/dotfiles/` and prints
its path in the header. When a phase fails, `set -eE` fires an ERR trap that names
the command, the line, and the last lines of that log, so a failed install leaves
something to read instead of a terminal that scrolled away. A read-only state
directory turns the log off and the header says so; it never stops the install.

| Phase | |
| --- | --- |
| tools | `python git curl sudo`, plus `stow`. The only hardcoded list, because `python3` is needed to read the file that lists the packages |
| packages | required packages for the selected groups, plus the ones reddoted forgets |
| aur | bootstraps `yay-bin` when there is no AUR helper |
| services | NetworkManager, Bluetooth, TLP and the user units, skipping what is not installed |
| groups | `input` and `video` |
| reddoted | clone at the pinned revision, then the root-owned ThinkPad helper |
| stow | links `$HOME` (see below) |
| wiring | `fisher update`, `ya pkg install`, `inode/directory` to yazi |
| verify | `deps/check.py` prints what is still missing |

## Commands

```sh
./install.sh                     the menu: packages and configs in one list
./install.sh --profile terminal  the hub alone, no Hyprland
./install.sh --profile standard  reddoted and what it needs
./install.sh --profile full      plus the optional integrations
./install.sh --only a,b,c        explicit list, no menu
./install.sh --stow fish,tmux    the same list, components only
./install.sh --check             audit only, changes nothing
./install.sh --update            move ~/Projects/reddoted to the pinned revision
./install.sh --all               include the optional groups
./install.sh --dry-run           print every command instead of running it
./install.sh --yes               defaults, no menu
./install.sh --no-tui            plain output for logs
```

## Two repositories, one owner per job

```
~/Projects/dotfiles/     this repo   bootstrap, manifest, personal overrides
~/Projects/reddoted/     cloned      the desktop: shell, Hyprland, themes, terminals
```

This repo does not contain reddoted's files. It brings them in and owns the one
list of packages that must exist first. `deps/reddoted.lock` pins the revision,
so a fresh machine gets the desktop you tested and not whatever `main` became.
`./install.sh --update` moves it, one command at a time.

## How the linking works

`stow`, with one rule that matters: `--no-folding`.

| | |
| --- | --- |
| `stow --no-folding -d reddoted -t ~/.config --ignore=fonts --ignore=sddm --ignore=xdg config` | every file in `reddoted/config/*` becomes a file symlink in `~/.config/*` |
| `stow --no-folding -d dotfiles/stow -t ~ personal` | the hub's own packages |

Folding would turn `~/.config/fish` into one symlink to reddoted, and then
`fisher update` would write plugins into reddoted's working tree, with `ya pkg`
doing the same for yazi. `--no-folding` keeps those directories real, which is
also what reddoted's own installer did.

Three paths cannot be stowed, because stow maps names one to one and these are
renames. They get a plain symlink, with the same backup rule:

| source | target |
| --- | --- |
| `reddoted/config/fonts` | `~/.local/share/fonts/glyph` |
| `reddoted/config/quickshell/rice/rice` | `~/.local/bin/rice` |
| `reddoted/config/xdg/yazi.desktop` | `~/.local/share/applications/yazi.desktop` |
| `reddoted/.../glyph/term/*` | `~/.config/{starship.toml,fastfetch,btop,cava,gtk-3.0}` from reddoted's own `term/links` |

Anything replaced is moved to `~/.dots-backup-<timestamp>/`, never deleted.

## What the hub owns

| Package | Target | Used when |
| --- | --- | --- |
| `stow/ghostty` | `~/.config/ghostty/config` | standalone only, with its own palette |
| `stow/fish` | `~/.config/fish` | standalone only |
| `stow/starship` | `~/.config/starship.toml` | standalone only |
| `stow/tmux` | `~/.config/tmux` | standalone only |
| `stow/yazi` | `~/.config/yazi` | standalone only |
| `stow/fastfetch` | `~/.config/fastfetch/config.jsonc` | both |
| `stow/core` | `~/.gitconfig`, `~/.config/{bat,ripgrep,git/ignore}` | always, even when no unit is named |
| `stow/personal` | `~/.config/hypr/user.lua` | reddoted only |

The terminal packages are stowed only when reddoted is not, because the two trees
would otherwise claim the same paths. `--profile terminal` is that mode.

`core` is marked `always` in `deps/units.toml`: naming any unit draws it in, the
same way naming no unit does in the desktop profiles. It is not an add-on, it is
the git/bat/ripgrep layer this machine always carries.

## Login, tmux and SSH

`conf.d/40-tmux.fish` starts tmux on every interactive shell that is not already
inside it, and keeps sessions apart by origin:

| login | session |
| --- | --- |
| local terminal | `main` |
| ssh from 192.168.1.20 | `ssh-192-168-1-20` |

`new-session -A` attaches when the session exists and creates it otherwise, so a
dropped connection comes back to the same place and two clients never share one.
The session name is what the tmux bar shows on the left, and `host_short` on the
right names the machine you are actually on.

Detaching closes the shell and leaves the session running. To turn it off:
`set -gx TMUX_AUTOSTART 0` in `~/.config/fish/local.fish`. Without tmux installed
the block does nothing.

Every file in the hub tree asks for colours by ANSI index and never by hex, so
the same config follows the wallpaper under reddoted and keeps the static
Nothing palette on its own. See [docs/THEMING.md](docs/THEMING.md).

## Layout

| Path | |
| --- | --- |
| [`install.sh`](install.sh) | entry point, component menu, orchestration |
| [`lib/ui.sh`](lib/ui.sh) | output, phases, keyboard, the multi-select menu |
| [`lib/detect.sh`](lib/detect.sh) | machine facts: distro, GPU family, session, AUR helper |
| [`lib/steps.sh`](lib/steps.sh) | the phases, including the stow engine |
| [`deps/deps.toml`](deps/deps.toml) | the dependency manifest, the only place a package name appears |
| [`deps/units.toml`](deps/units.toml) | the boundary: one stow package plus the packages it needs |
| [`deps/usage.toml`](deps/usage.toml) | the evidence: package, caller, consequence |
| [`deps/reddoted.lock`](deps/reddoted.lock) | which reddoted commit this repo pins |
| [`deps/check.py`](deps/check.py) | audits a machine against the manifest |
| [`deps/query.py`](deps/query.py) | answers manifest questions for the shell script |
| [`deps/by-package.py`](deps/by-package.py) | renders `docs/BY-PACKAGE.md` |
| [`deps/lint.sh`](deps/lint.sh) | every check in one command |
| [`stow/`](stow/) | hub-owned packages |
| [`docs/`](docs/) | dependencies, integrations, theming, side effects, per package, standalone |

The menu is one checklist, and every row is a package you will actually get.
Sections are package groups; the group header toggles the whole group and shows
`3/6`; the two preset rows at the top check a whole selection at once and go
half-lit `[~]` when you take a member out.

```
  ─ presets
  [x] desktop   reddoted e o que ele precisa
  [ ] terminal  o hub sozinho, sem Hyprland
  ─ base 6/6
  [x] base-devel  install.sh builds yay-bin from the AUR; also c…
  [x] git         install.sh (clone reddoted), fisher, ya pkg, i…
```

Keys: `↑↓`/`jk` move, `enter` or `space` toggles the row under the cursor, `i`
starts the run, `a` checks everything, `n` clears, `q` quits without touching
anything. Unchecking a single package really does drop it: the installer builds
its command line from what is left checked, not from the group lists.

## What it costs

Measured on the ThinkPad that runs this, not estimated.

| | |
| --- | --- |
| fish startup | 7 ms, of which 3 ms is the config |
| starship prompt, project dir (git + one runtime) | 10 ms |
| starship prompt, with a `Cargo.toml` (adds `rustc --version`) | 15 ms |
| tmux server, three panes, 20000 lines of history | 4 MiB |
| ghostty scrollback | capped at 20 MB per window, where the default is 50 MB |
| yazi, idle with previews loaded | 33 MiB |

Two of those exist because the terminal and the multiplexer would otherwise pay
twice for the same thing:

- Ghostty defaults to 50000000 bytes of scrollback with no line limit. tmux keeps
  its own history inside the pane, so the terminal's copy is a duplicate. 20 MB
  is still tens of thousands of lines and bounds the worst case.
- tmux defaulted to 50000 lines per pane in the earlier config. 20000 is about
  4 MiB of grid and is where copy-mode search still works the same.

The prompt is the only thing that costs CPU on every command. `git_metrics` (the
`+12 -3` counter) runs `git diff --shortstat` every prompt and is off by default
here: it was 7 ms for a number that git status already implies. Language versions
only cost anything in a real project, because the detector looks for
`pyproject.toml` and `Cargo.toml`, not for a stray `.py` or `.rs`.

```toml
[git_metrics]
disabled = false   # put the diff counter back, at about 7 ms per prompt
```

## Checking it

```sh
./deps/lint.sh          # no root, no network, about five seconds
```

It runs `bash -n` on every script, `shellcheck` when present, parses the three
manifests, checks that every package still has usage evidence, and dry-runs every
mode. Without shellcheck, either `pacman -S shellcheck` or drop the static binary
from [the release tarball](https://github.com/koalaman/shellcheck/releases) in
`$PATH`.

## Design rules

- One package list: `deps.toml`, nowhere else.
- Required means broken. A group is mandatory only if a committed config breaks
  without it; optional groups degrade a feature and are reported.
- No silent fallbacks. What the checker cannot verify, such as a service bus
  behind a sandbox, is printed as unverifiable and never as satisfied.
- Nothing is deleted. Conflicts are moved into a dated backup directory.
- Idempotent. Every phase asks whether it is already true.
