# Theming, and the rest of the integrations

Who writes colours, who reads them, what survives without reddoted, and the
small stuff around the edges (fastfetch, btop, cava, the folder icons).

## The writer

One file writes colours on this desktop: `config/quickshell/glyph/Apply.qml`.
Everything else either reads a file it produced, or reads ANSI indices.

```qml
Connections { target: GlyphPalette
    function onGreysChanged() { repaint.restart() } }   // palette or wallpaper tone
Connections { target: GlyphPalette.state
    function onTermThemeChanged() { repaint.restart() } }
Timer { interval: 300; onTriggered: { apply(); apps() } }
```

It emits three things:

| Output | Mechanism | Consumed by |
| --- | --- | --- |
| Hyprland live config | `hyprctl eval` with `hl.config{…}` | borders (active = `fg`, inactive = `s3`), gaps, rounding, opacity, blur, shadow, group bar, `misc.background_color` |
| `~/.config/demonshot/ghostty-colors` | `FileView.setText` | Ghostty, through `config-file = ?…`, background, foreground, cursor, selection, `palette 0..15` |
| `~/.local/state/rice/glyph/{gtk-3.0/gtk.css, gtk-4.0/gtk.css, qtengine.colors}` | `sed` swaps the palette inside the templates from `term/`, then `ln -sfn` repoints `~/.config/…` at the copy | GTK3, GTK4, Qt (via `qtengine`) |

The palette itself comes from `GlyphPalette.qml`: greys derived from the
wallpaper, ten static schemes in `schemes.js` (Catppuccin, Rosé Pine, Gruvbox,
Nord, Dracula, Tokyo Night, Everforest, Kanagawa, Nothing mono), plus light/dark
and the glass variants.

## The readers

| Consumer | Gets its colour from | Package | Without reddoted |
| --- | --- | --- | --- |
| Hyprland decorations | `hyprctl eval` | hyprland | falls back to `config/hypr` statics |
| Ghostty | generated include, else its own `palette` block | ghostty | **works**, the hub ships the static palette |
| GTK3 / GTK4 | generated `gtk.css` over `adw-gtk3-dark` | adw-gtk3-theme | dark scheme yes, accent no |
| Qt apps (incl. Quickshell itself) | `qtengine` + `darkly` reading `qtengine.colors` | qtengine, darkly-bin | default Qt palette |
| Cursor | `hyprctl setcursor` + `gsettings cursor-theme` | bibata-cursor-theme-bin | whatever the system has |
| Folder icons | `term/folders` → `grey`, applied by `rice` | papirus-icon-theme | stock Papirus |
| starship, fzf, bat, yazi, tmux | **ANSI indices only** |, | **works**, see below |
| fastfetch | its own config, ANSI numbers | fastfetch | **works** (hub has its own) |
| btop | `term/btop` | btop | template, follows ANSI |
| cava | `term/cava` (dot bars) | cava | template, follows ANSI |

## The ANSI contract

Every config the hub owns, `stow/{ghostty,fish,starship,tmux,yazi,fastfetch}`, asks for colours by index (`red` = 1, `bright-black` = 8, `-1` = default) and
never by hex. That is what makes the same files work in both modes:

- **with reddoted**: the generated `ghostty-colors` rewrites palette 0–15, so
  every one of those files follows the wallpaper.
- **standalone**: nothing rewrites anything, and the static Nothing palette in
  `stow/ghostty/.config/ghostty/config` is the source. Same files, same look.

This is also why the hub's ghostty config has **no** `config-file` include: it is
self-contained by design.

## The edge pieces

| Piece | Where it lives | Notes |
| --- | --- | --- |
| `starship.toml` | hub `stow/starship` | ANSI only; transience on |
| `fastfetch` config | hub `stow/fastfetch` | new: logo off, ANSI keys, palette swatches at the bottom |
| `btop` theme | reddoted `glyph/term/btop` | linked by `term/links` |
| `cava` dots | reddoted `glyph/term/cava` | `alias cava ~/.config/cava/dots` |
| `gtk-3.0/gtk.css`, `gtk-4.0/gtk.css` | reddoted `glyph/term/` | **templates**: the real file is the generated copy |
| `qtengine.colors` | reddoted `glyph/term/` | template, same mechanism |
| folder colour | `glyph/term/folders` = `grey` | applied by `rice`, not by install |
| cursor | `variables.lua` → `cursorTheme`, `cursorSize` | set through `hyprctl` + `gsettings` at startup |

## What the audit turned up

Three things that are wrong or dead in the current tree, found while mapping this:

1. **`fastfetch` is broken.** `config/quickshell/glyph/term/fastfetch/{config.jsonc,logo.txt}`
   are deleted in reddoted's working tree, but `glyph/term/links` still lists
   `fastfetch|fastfetch`, so `~/.config/fastfetch` is a symlink into a directory
   that no longer has content. The hub now ships its own config, and the
   standalone profile does not depend on that symlink at all.
2. **`matugen` is installed and unused.** It is an AUR package; nothing in the
   repo calls it. Safe to remove (`pacman -R matugen`).
3. **The GTK/Qt symlinks currently point at the templates**, not at
   `~/.local/state/rice/glyph/`. That is the "no colour diff" branch of
   `Apply.apps()`: it relinks to the template when the palette did not change, so
   this is expected right after a restart, not a bug.

## What a machine pays without reddoted

`./install.sh --profile terminal` installs the hub alone: ghostty, fish,
starship, tmux, yazi, fastfetch, plus their tools. What it does **not** get:
Hyprland border colours, the GTK accent, the Qt palette, the Papirus folder
colour, the cursor setting and every shell panel. Those are reddoted's, by
definition, and the terminal stack does not need any of them.

## The terminal palette

`stow/ghostty/.config/ghostty/config` states the theme in full, so the terminal
does not depend on the desktop config for colour. Every other config in the hub
picks from these 16 slots by ANSI index, which is why tmux, starship and fish
follow a palette change here without being edited.

| slot | | slot | |
| --- | --- | --- | --- |
| 0 | `#0D0D0D` background | 8 | `#696969` bright black |
| 1 | `#FF3F4F` red | 9 | `#FF9700` bright red |
| 2 | `#81F900` green | 10 | `#98C379` bright green |
| 3 | `#FFD945` yellow | 11 | `#E5A422` bright yellow |
| 4 | `#00A0E4` blue | 12 | `#56B6C2` bright blue |
| 5 | `#E542FF` magenta | 13 | `#E373CE` bright magenta |
| 6 | `#19D1E5` cyan | 14 | `#6AEBF7` bright cyan |
| 7 | `#F6F6F6` foreground | 15 | `#FFFFFF` bright white |

Cursor is `#F6F6F6` on `#0D0D0D`, selection `#3E4451` with `#FFFFFF` text.
