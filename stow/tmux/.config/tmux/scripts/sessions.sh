#!/usr/bin/env sh
# dotfiles · tmux session picker
#
# Runs inside `display-popup`. Lists live sessions first, then the directories
# zoxide remembers, and either switches to the session or starts one there.
# Dependencies: tmux + fzf (zoxide optional).
#
#   sessions.sh        pick a session or a directory
#   sessions.sh --new  only offer directories (always creates)
set -u

new_only=0
[ "${1:-}" = "--new" ] && new_only=1

command -v fzf >/dev/null 2>&1 || { printf 'sessions: fzf not installed\n' >&2; exit 1; }
# fzf needs a terminal. Without one this exits instead of printing a page of
# broken-pipe errors, which is what happened when it was run from a pipe.
[ -t 0 ] || { printf 'sessions: no terminal\n' >&2; exit 1; }

# tag <TAB> marker <TAB> label. Field 1 is the action, 2.. is what you see.
rows() {
  if [ "$new_only" -eq 0 ]; then
    tmux list-sessions -F '#{session_name}' 2>/dev/null |
      while IFS= read -r s; do
        printf 'session\t\033[38;2;215;25;33m●\033[0m\t%s\n' "$s"
      done
  fi

  dirs=""
  if command -v zoxide >/dev/null 2>&1; then
    dirs=$(zoxide query --list --score 2>/dev/null | sed 's/^[0-9.]* //' | head -80)
  fi
  [ -n "$dirs" ] || dirs=${HOME}

  printf '%s\n' "$dirs" |
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      printf 'dir\t\033[38;2;110;110;110m·\033[0m\t%s\n' "${d/#$HOME/~}"
    done
}

pick=$(rows | fzf \
  --delimiter='\t' --with-nth=2.. \
  --height=100% --reverse --exact --ansi --no-info \
  --prompt='  ›  ' --pointer='›' --marker='·' \
  --header='  session · directory' \
  --color=fg:#F2F2F2,bg:#0E0E0E,hl:#D71921,fg+:#F2F2F2,bg+:#1A1A1A,hl+:#D71921 \
  --color=pointer:#D71921,marker:#D71921,prompt:#8A8A8A,header:#4A4A4A,info:#4A4A4A) ||
  exit 0

tag=$(printf '%s\n' "$pick" | cut -f1)
label=$(printf '%s\n' "$pick" | cut -f3)

[ -n "$label" ] || exit 0

case "$tag" in
  session)
    tmux switch-client -t "=$label"
    ;;
  dir)
    # Expand the ~ we collapsed for display.
    path=$(printf '%s\n' "$label" | sed "s|^~|$HOME|")
    [ -d "$path" ] || { tmux display-message "no such directory: $path"; exit 0; }
    # Reuse a session rooted there if one exists, otherwise start one.
    existing=$(tmux list-sessions -F '#{session_name}:#{session_path}' 2>/dev/null |
      awk -F: -v p="$path" '$0 ~ ":"p"$" { print $1; exit }')
    if [ -n "$existing" ]; then
      tmux switch-client -t "=$existing"
    else
      name=$(basename "$path" | tr -c 'a-zA-Z0-9_-' '_' | cut -c1-32)
      name=${name:-session}
      tmux new-session -d -s "$name" -c "$path" 2>/dev/null ||
        tmux new-session -d -c "$path" 2>/dev/null
      tmux switch-client -t "=$name" 2>/dev/null || tmux attach -t "=$name"
    fi
    ;;
esac
