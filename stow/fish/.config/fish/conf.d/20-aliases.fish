# dotfiles · aliases
#
# Only shells around tools that exist. Each one is guarded, so nothing here can
# shadow a missing binary with a confusing error.

if not status is-interactive
    return
end

# ── eza ─────────────────────────────────────────────────────────────────────
# `--icons` needs the Nerd Font; `--git` is a cheap read.
if type -q eza
    alias ls 'eza --icons --group-directories-first'
    alias ll 'eza --long --icons --group-directories-first --git --time-style=long-iso'
    alias la 'eza --long --all --icons --group-directories-first --git'
    alias lla 'eza --long --all --icons --group-directories-first --git --time-style=long-iso'
    alias lt 'eza --tree --level=2 --icons --group-directories-first'
else
    alias ll 'ls -l'
    alias la 'ls -A'
    alias lla 'ls -lA'
end

# ── the rest ────────────────────────────────────────────────────────────────
# cat: bat with the palette, no pager, no decoration, output stays diffable.
type -q bat; and alias cat 'bat --style=plain --paging=never'
type -q dust; and alias du 'dust'
type -q procs; and alias ps 'procs'

# cava as dots, like Glyph Matrix (~/.config/cava/dots); plain bars: command cava
type -q cava; and alias cava ~/.config/cava/dots

# ── colour ─────────────────────────────────────────────────────────────────
# Keep the tools that honour it on the terminal palette; nothing forces colour
# when the output is piped.
set -gx CLICOLOR 1
