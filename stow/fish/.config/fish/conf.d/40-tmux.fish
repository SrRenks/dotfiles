# tmux on login, with SSH kept apart.
#
# Every interactive shell that is not already inside tmux attaches to a session,
# creating it on first use. A local terminal lands in "main". An SSH login gets a
# session of its own, named after the machine that connected, so a second client
# never joins the first one's session and neither can detach the other.
#
# Detaching from tmux closes the shell, which is the point: the session keeps
# living and the window is free.
#
# Opt out with `set -gx TMUX_AUTOSTART 0` (for example in
# ~/.config/fish/local.fish, which is not tracked here). With no tmux installed
# this block does nothing at all.

if not status is-interactive
    return
end

if set -q TMUX
    return
end

if set -q TMUX_AUTOSTART
    and test "$TMUX_AUTOSTART" = 0
    return
end

if not type -q tmux
    return
end

# Guard against re-entry when this file is sourced twice.
if set -q TMUX_AUTOSTART_ARMED
    return
end
set -gx TMUX_AUTOSTART_ARMED 1

set -l session main
if set -q SSH_CONNECTION
    # "<client ip> <client port> <server ip> <server port>". The client address
    # is what tells two remote sessions apart.
    set -l parts (string split ' ' -- $SSH_CONNECTION)
    set -l origin (string replace -a '.' '-' -- $parts[1])
    set session "ssh-$origin"
end

# tmux keeps its socket in $TMUX_TMPDIR (default /tmp) under tmux-<uid>. If that
# directory is missing and cannot be created, every command fails with
#   error creating /tmp/tmux-1000/default (No such file or directory)
# which says nothing about the fix. Check it first, so the message does.
set -l sockdir (set -q TMUX_TMPDIR; and echo $TMUX_TMPDIR; or echo /tmp)/tmux-(id -u)
if not test -d $sockdir
    mkdir -p $sockdir 2>/dev/null
end
# tmux refuses a socket directory that is visible to anyone else:
#   directory /tmp/tmux-1000 has unsafe permissions
# Its own creation uses 0700; one made by hand or by an older tool can be 755.
if test -d $sockdir
    and test (stat -c %a $sockdir 2>/dev/null) != 700
    chmod 700 $sockdir 2>/dev/null
end
if not test -d $sockdir
    echo "tmux: cannot use $sockdir" >&2
    echo "      tmux wants it owned by you and mode 700: sudo rm -rf $sockdir" >&2
    return
end

# -A attaches when the session exists and creates it otherwise. Running it in the
# foreground means a failed start (broken config, no terminal) falls through to a
# normal shell instead of taking the session down with it.
if not tmux new-session -A -s $session
    echo "tmux did not start; staying in fish" >&2
end
