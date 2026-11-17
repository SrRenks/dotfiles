# Against the community setups

What the well-known tmux, ghostty and fish setups ship, what this repo ships, and
what it refuses on purpose. Written so nobody has to re-derive the same decisions.

The reference sets: [gpakosz/.tmux](https://github.com/gpakosz/.tmux),
[tmux-plugins](https://github.com/tmux-plugins) (TPM, sensible, resurrect,
continuum, yank), [catppuccin/tmux](https://github.com/catppuccin/tmux),
[ThePrimeagen's sessionizer](https://github.com/ThePrimeagen/.dotfiles),
[fzf.fish](https://github.com/PatrickF1/fzf.fish),
[jorgebucaran/fisher](https://github.com/jorgebucaran/fisher), and the Ghostty
[option reference](https://ghostty.org/docs/config/reference).

## tmux

| What the popular setups do | Here | Why |
| --- | --- | --- |
| vi copy mode, `y` to the system clipboard | yes, `set-clipboard on` plus OSC 52 | works without `xclip` and without a plugin |
| true colour and image passthrough | yes, `terminal-features` and `allow-passthrough` | required for yazi's previews |
| status bar from a theme plugin (catppuccin) | no, custom with `theme detect` | one palette, chosen by the desktop; a theme plugin is a second source of colour |
| pane scrollbars | yes, `pane-scrollbars auto-hide` | native since 3.8; the plugin does not exist for the same reason any more |
| popups (fzf menus, lazygit, btop) | yes, `display-popup` | same idea as tmux-fzf, four binds instead of a plugin |
| a project session picker | yes, `scripts/sessions.sh` | the sessionizer, without a shell function per dotfile |
| **sessions survive a reboot** | **yes, resurrect + continuum** | the one real gap this page found; now cloned by the installer, sourced directly |
| TPM (plugin manager) | no | a manager that must install itself before it can install plugins, and it wants the network at every start |
| tmux-thumbs / extrakto (pick text in the pane) | no | copy-mode vi plus yazi covers the cases this machine hits; both add a daemon or a fork of the picker |
| powerline segments, rounded separators | no | the desktop is flat by design |
| vim-style seamless navigation (`C-hjkl` into nvim) | no, `Alt+hjkl` | the `C-hjkl` version needs a matching Neovim plugin, and breaks silently without it |

## ghostty

| What the popular setups do | Here | Why |
| --- | --- | --- |
| shell integration, prompt jumping, cursor shape | yes, fish integration with `ssh-env` and `ssh-terminfo` | the two ssh features are what make `xterm-ghostty` work on a remote host |
| command finished notifications | yes, `unfocused` plus the notification daemon | comes free with shell integration |
| splits, tabs, command palette | yes, defaults plus three extra binds | Ghostty's defaults already cover the rest |
| quick terminal dropdown | yes, on the overlay layer with a namespace | the namespace is what lets the compositor rule it |
| scrollback tuning | yes, 20 MB | the default is 50 MB per window |
| `custom-shader` (CRT, bloom, unixporn favourites) | no | it runs per frame on the GPU; the machine already spends its budget on the desktop |
| `background-blur` | no | Hyprland blurs through layer rules, so the terminal would blur twice |
| a theme from the built-in store | no | the palette comes from the desktop, and two palettes cannot both win |
| `font-feature` for ligatures | no, disabled | Space Mono has none, and mixing it with a ligature font in one cell grid looks broken |

## fish

| What the popular setups do | Here | Why |
| --- | --- | --- |
| plugin manager | fisher, three plugins | the smallest one that works |
| `Ctrl+R`, `Ctrl+T`, `Alt+C` from fzf | yes, fzf.fish | the canonical bindings, no reinvention |
| notification when a long command ends | yes, done | talks to the same daemon the desktop uses |
| a prompt framework (tide, bobthefish) | no, starship | one prompt, and it is the one the terminal palette follows |
| `z`/`cd` frecency | zoxide | `zoxide init` for both spellings |
| per-directory environments | direnv | hooked, silent unless a `.envrc` opts in |
| history hygiene (failed commands out of history) | yes, sponge | a typo should not come back on Up |
| autopair, puffer-fish (auto-close and path expansion) | no | personal taste, and every extra `bind` is a collision waiting to happen in an editor-backed prompt |
| bass (run bash scripts in fish) | no | nothing here ships a bash script that needs sourcing into the shell |
| nvm.fish | no | node comes from pacman; there is no nvm to manage |
| Oh My Fish | no | a framework that owns `$fish_function_path` and fights fisher |

## Mouse on a tty

A virtual console has no mouse events: nothing on a VT emits the escape sequences
a terminal emulator sends. `gpm` is the daemon that fills that gap, and it works
through libgpm, so the console programs that link it get mouse support: vim, less,
mc, links. tmux does not link libgpm and cannot: inside tmux on a tty the mouse
stays dead, and that is a property of the console, not of the tmux config.

It is an optional group (`tty`) rather than part of the terminal stack because gpm
grabs `/dev/input/mice`. When it conflicts with the compositor's own input, the
symptom is a touchpad that stutters or clicks by itself, and the fix is
`systemctl disable --now gpm`.

## What this page changed

Reading it against the configs produced exactly two additions, both of which
were real gaps rather than taste:

1. `tmux-resurrect` and `tmux-continuum`, sourced directly by `tmux.conf` with
   `if-shell` guards so a machine that has not cloned them yet starts clean. The
   installer clones them into `~/.config/tmux/plugins/`, outside the repo.
2. `sponge` in `fish_plugins`.

Everything else the popular setups carry is either already here in native form
(scrollbars, passthrough, popups, sessionizer) or is a colour or prompt framework
that would fight the palette.
