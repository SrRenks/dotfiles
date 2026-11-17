# Installing one thing, without the desktop

This repository is split by **lifecycle**, not by taste:

| Layer | Lives in | Works on |
| --- | --- | --- |
| `stow/`, terminal units | this repo | any machine: any WM, any distro with these packages, no Hyprland |
| the desktop, Hyprland, Quickshell, GTK/Qt, fonts, greeter, pkexec helpers | [reddoted](https://github.com/SrRenks/reddoted) | this rice only |
| the package manifest + evidence | this repo | both |

The line is a test, not an opinion: **if a piece cannot run on a machine without
reddoted, it stays in reddoted.** Copying the desktop here would fork reddoted
instead of complementing it, and every colour rule behind `pkexec`, `thinkfan`,
`qtengine` and Papirus would immediately exist twice.

## The units

Each one is a self-contained stow package with its own dependency list
([`deps/units.toml`](../deps/units.toml)).

| unit | what it is | packages it pulls |
| --- | --- | --- |
| `ghostty` | Nothing palette, no chrome, splits, notifications | ghostty, ttf-jetbrains-mono-nerd |
| `fish` | `conf.d` fragments, six functions, fisher manifest | fish, starship, eza, zoxide, direnv, fzf, fd, bat, ripgrep, yazi |
| `starship` | ANSI-only prompt, transient, left/right split | starship, ttf-jetbrains-mono-nerd |
| `tmux` | 3.8 config, no plugin manager, popups | tmux, fzf, yazi, lazygit, btop |
| `yazi` | file manager: openers, 11 pinned plugins, Glyph theme | yazi, fd, fzf, ripgrep, bat, 7zip, ffmpeg, poppler, mpv, imagemagick, udisks2 |
| `fastfetch` | logo off, ANSI keys, swatches | fastfetch |
| `core` | git (merge style, aliases, pager), bat, ripgrep. Always stowed | git, bat, ripgrep |
| `reddoted` | **the full desktop**: Hyprland, Quickshell, GTK/Qt palette, fonts, terminal | 74 (see below) |
| `personal` | Hyprland monitors/binds, **needs reddoted** |, |

## reddoted is a unit too

The desktop is not a special case: it is the same vocabulary with a bigger
package list. `./install.sh --stow reddoted` is the whole rice, 74 packages +
`qtengine`/`darkly-bin` from the AUR, services, your `input`/`video` groups, the
clone at the pinned revision, the root-owned ThinkPad helper, the stow tree and
the wiring.

```sh
./install.sh --stow reddoted            # the desktop
./install.sh --stow reddoted --all      # + greeter, flatpak, geoclue, thinkfan, cursor
./install.sh --stow reddoted,fastfetch  # the desktop plus any unit that does not collide
```

Its groups live in [`deps/units.toml`](../deps/units.toml): everything a
`--profile standard` run does is described there, so there is one vocabulary, not
two. When reddoted is installed it keeps the terminal contracts (fish, ghostty,
tmux, yazi, starship), the hub versions are not stowed in that mode, because two
owners for `~/.config/fish` is a fight.

## With the installer

```sh
./install.sh --stow fish            # fish and the 10 packages it calls
./install.sh --stow yazi,tmux       # two units, no Hyprland anywhere
./install.sh --stow fish --dry-run  # see it first
```

It installs only that unit's packages, stows only that package, and runs only the
wiring that applies (fisher for `fish`, `ya pkg install` for `yazi`). No reddoted
clone, no desktop groups.

## Without the installer

A stranger does not need this repo's shell script at all:

```sh
git clone https://github.com/SrRenks/dotfiles ~/dotfiles
cd ~/dotfiles/stow

# pick one, install its packages, stow it, undo with stow -D
stow -t ~ tmux
sudo pacman -S --needed tmux fzf yazi lazygit btop
stow -D -t ~ tmux
```

`yazi` needs one extra step because plugins are not in git:

```sh
stow -t ~ yazi && (cd ~/.config/yazi && ya pkg install)
```

Every file uses ANSI colour indices only, so all of them follow whatever palette
the terminal already has, that is what makes them portable.

## What is deliberately **not** here

`hypr/`, `quickshell/`, `gtk-3.0/gtk.css`, `qtengine.colors`, the bundled fonts,
the SDDM theme, the ThinkPad helper, the Papirus folder colour and the cursor.

Those are one system. `Apply.qml` writes them together from one palette, three of
them sit behind `pkexec`, and one of them is a root-owned helper binary. There is
no meaningful way to install "just the GTK accent", and no reason for a stranger
to want to.
