# ==============================
# PATH
# ==============================
export PATH="$HOME/.local/bin:$PATH"
export LC_CTYPE=pt_BR.UTF-8
# ==============================
# TMUX auto start
# ==============================
if command -v tmux >/dev/null && [[ -z "$TMUX" && -o interactive ]]; then
    if [[ -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
        session_name="ssh-${HOSTNAME}"
    else
        session_name="main"
    fi
    exec tmux new-session -A -s "$session_name"
fi

# ==============================
# Powerlevel10k Instant Prompt
# ==============================
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ==============================
# Zinit
# ==============================
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

if [[ ! -d "$ZINIT_HOME" ]]; then
  mkdir -p "$(dirname "$ZINIT_HOME")"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

source "$ZINIT_HOME/zinit.zsh"

# ==============================
# Plugins
# ==============================
zinit ice depth=1
zinit light romkatv/powerlevel10k

zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-history-substring-search

zinit light Aloxaf/fzf-tab
zinit light jeffreytse/zsh-vi-mode

zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::docker
zinit snippet OMZP::command-not-found

autoload -Uz compinit
compinit -u

zinit cdreplay -q

# ==============================
# Powerlevel10k config
# ==============================
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# ==============================
# Environment
# ==============================
export EDITOR="nvim"
export VISUAL="nvim"
export SUDO_EDITOR="nvim"
export FCEDIT="nvim"

export TERMINAL="alacritty"
export BROWSER="com.brave.Browser"

# ==============================
# bat pager
# ==============================
if command -v bat >/dev/null; then
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
  export PAGER=bat
fi

# ==============================
# FZF
# ==============================
if command -v fzf >/dev/null; then
  export FZF_DEFAULT_OPTS="
    --info=inline-right
    --ansi
    --layout=reverse
    --border=rounded
  "
fi

# ==============================
# History
# ==============================
HISTSIZE=10000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE

setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups

# ==============================
# Completion
# ==============================
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' menu select

# ==============================
# zoxide
# ==============================
if command -v zoxide >/dev/null; then
  alias zi >/dev/null 2>&1 && unalias zi
  eval "$(zoxide init zsh)"
fi

# ==============================
# Functions
# ==============================

function y() {
  local tmp="$(mktemp /tmp/yazi-cwd.XXXXXX)"
  trap "rm -f '$tmp'" EXIT INT TERM QUIT
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(cat "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    cd "$cwd"
  fi
  rm -f "$tmp"
  trap - EXIT INT TERM QUIT
}

function runfree() {
  "$@" >/dev/null 2>&1 & disown
}

function mkdirg() {
  mkdir -p "$@" && cd "$@"
}

# ==============================
# Aliases
# ==============================

alias c='clear'
alias q='exit'
alias ..='cd ..'

alias mkdir='mkdir -pv'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'

alias grep='grep --color=auto'

if command -v nvim >/dev/null; then
  alias vi='nvim'
  alias vim='nvim'
  alias svi='sudo nvim'
fi

if command -v lsd >/dev/null; then
  alias ls='lsd -F --group-dirs first'
  alias ll='lsd --all --header --long'
  alias tree='lsd --tree'
fi

if command -v bat >/dev/null; then
  alias cat='bat'
fi

if command -v lazygit >/dev/null; then
  alias lg='lazygit'
fi

if command -v xdg-open >/dev/null; then
  alias open='runfree xdg-open'
fi

alias iplocal="ip -br -c a"

if command -v curl >/dev/null; then
  alias ipexternal="curl -s ifconfig.me && echo"
fi

# ==============================
# envman
# ==============================
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh" || true

# ==============================
# Bitwarden SSH Agent socket
# ==============================
if [[ -S "$HOME/snap/bitwarden/current/.bitwarden-ssh-agent.sock" ]]; then
    export SSH_AUTH_SOCK="$HOME/snap/bitwarden/current/.bitwarden-ssh-agent.sock"
elif [[ -S "$HOME/.bitwarden-ssh-agent.sock" ]]; then
    export SSH_AUTH_SOCK="$HOME/.bitwarden-ssh-agent.sock"
elif [[ -S "/run/user/$(id -u)/bitwarden-ssh-agent.sock" ]]; then
    export SSH_AUTH_SOCK="/run/user/$(id -u)/bitwarden-ssh-agent.sock"
fi
