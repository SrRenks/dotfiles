# dotfiles · fish
#
# Everything that has to exist before the first prompt lives in conf.d/ so the
# order is explicit and each block can be disabled on its own:
#
#   05-env.fish      EDITOR, pager, bat, fzf defaults
#   10-shell.fish    starship, zoxide, direnv
#   20-aliases.fish  eza, cava, colours
#   30-yazi.fish     yazi as the picker for everything
#
# This file keeps what belongs to the interactive session itself: path, greeting,
# abbreviations. Unabridged git abbrs stay here because they are muscle memory,
# not configuration.
#
# Ghostty ships shell integration for fish, so no OSC 133 marks are emitted by
# hand here, the terminal already does prompt jumping, cursor shape and
# command-finish notifications.

# rice and other install.sh helpers live in ~/.local/bin, which Arch does not add to PATH
fish_add_path -g ~/.local/bin

if status is-interactive
    # ── git ──────────────────────────────────────────────────────────────
    abbr lg 'lazygit'
    abbr gd 'git diff'
    abbr ga 'git add .'
    abbr gc 'git commit -am'
    abbr gl 'git log'
    abbr gs 'git status'
    abbr gst 'git stash'
    abbr gsp 'git stash pop'
    abbr gp 'git push'
    abbr gpl 'git pull'
    abbr gsw 'git switch'
    abbr gsm 'git switch main'
    abbr gb 'git branch'
    abbr gbd 'git branch -d'
    abbr gco 'git checkout'
    abbr gsh 'git show'

    # ── directories ──────────────────────────────────────────────────────
    # ls/ll/la/lla/lt are aliases in 20-aliases.fish, not abbrs: an abbr that
    # expands to itself is a loop.
    abbr l 'ls'
    abbr .. 'cd ..'
    abbr ... 'cd ../..'
    abbr .... 'cd ../../..'

    # ── the rest of the alphabet, only where it saves typing ─────────────
    abbr c 'clear'
    abbr e 'exit'
    abbr q 'exit'
    abbr v 'nvim'
    abbr pac 'sudo pacman -Syu'
    abbr xdg 'xdg-open'
end
