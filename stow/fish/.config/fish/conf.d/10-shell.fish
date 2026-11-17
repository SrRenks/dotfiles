# dotfiles · shells and hooks
#
# Loaded before config.fish. Nothing here starts a process: each hook is a
# string eval, and each tool is `type -q` away from being skipped so a fresh
# Arch install still gets a working shell before ./install.sh has run.

if not status is-interactive
    return
end

# ── prompt ──────────────────────────────────────────────────────────────────
# Starship draws the prompt from ~/.config/starship.toml (stow/starship in
# this repo). Transience is the reason a minimal prompt stays
# minimal: once a command runs, its prompt collapses to the bare character, so
# scrollback is commands and output, not a wall of paths.
if type -q starship
    function starship_transient_prompt_func --description 'Collapsed prompt for finished commands'
        starship module character
    end
    function starship_transient_rprompt_func --description 'Collapsed right prompt'
        # empty on purpose: timing and exit codes belong to the live prompt only
    end

    starship init fish | source
    enable_transience
end

# ── zoxide ──────────────────────────────────────────────────────────────────
# `z` keeps the original spelling, `cd` becomes the jump. Two evals, no process.
if type -q zoxide
    zoxide init fish --cmd z  | source
    zoxide init fish --cmd cd | source
end

# ── direnv ──────────────────────────────────────────────────────────────────
# Per-directory environments (.envrc). Silent unless a .envrc opts in.
type -q direnv; and direnv hook fish | source
