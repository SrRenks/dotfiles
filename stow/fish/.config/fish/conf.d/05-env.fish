# dotfiles · environment
#
# Cheap variables only: nothing here spawns a process. Everything is guarded by
# `status is-interactive` except EDITOR, which non-interactive tools (git, yazi,
# crontab, sudo -e) also need.

set -gx EDITOR nvim
set -gx VISUAL nvim

if status is-interactive
    # Pager: quiet, colour passthrough, quit-if-one-screen, keep history out.
    set -gx PAGER less
    set -gx LESS '-R -i -M -F -X'
    set -gx LESSHISTFILE -
    set -gx MANPAGER 'sh -c "col -bx | bat --style=plain --pager=never --language=man"'

    # bat follows the terminal palette instead of shipping its own colours, so
    # it moves with the Glyph palette like everything else.
    set -gx BAT_THEME ansi
    set -gx BAT_STYLE 'numbers,grid,header-filename'
    set -gx BAT_PAGER 'less -RF'

    # eza: one palette, icons from the Nerd Font already installed.
    set -gx EZA_CONFIG_DIR ~/.config/eza

    # fzf: ANSI indices, never hex. The Ghostty palette is rewritten by the
    # shell when the wallpaper changes, so fzf follows for free.
    #   1 = red accent · 8 = grey separators · -1 = terminal default
    set -gx FZF_DEFAULT_OPTS "
        --height=60% --layout=reverse --info=inline-right --border=none
        --color=fg:-1,bg:-1,hl:1,fg+:-1,bg+:8,hl+:1
        --color=pointer:1,marker:1,spinner:1,prompt:8,header:8,info:8,border:8
        --color=query:-1,disabled:8,preview-fg:-1,preview-bg:-1
    "
    # ripgrep reads its defaults from here: smart case, hidden files, and the
    # usual build directories skipped.
    set -gx RIPGREP_CONFIG_PATH ~/.config/ripgrep/config

    # fd when present, ripgrep otherwise. Both skip .git and dotfiles noise.
    if type -q fd
        set -gx FZF_DEFAULT_COMMAND "fd --type f --hidden --follow --exclude .git --exclude node_modules"
    else if type -q rg
        set -gx FZF_DEFAULT_COMMAND "rg --files --hidden --follow --glob '!.git' --glob '!node_modules'"
    end
    set -gx FZF_CTRL_T_COMMAND $FZF_DEFAULT_COMMAND
    set -gx FZF_ALT_C_COMMAND "fd --type d --hidden --follow --exclude .git . 2>/dev/null; or find . -maxdepth 2 -type d"
end
