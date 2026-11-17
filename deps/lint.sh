#!/usr/bin/env bash
# deps/lint.sh, the checks that keep this repo honest. No root, no network.
#
#   ./deps/lint.sh
#
# Runs: bash syntax, shellcheck (if available), TOML/Python parse,
# the usage-evidence coverage check, and a dry run of every mode.
set -uo pipefail

DOTS="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DOTS" || exit 1
fail=0

say()  { printf '\e[38;2;215;25;33m●\e[0m %s\n' "$*"; }
bad()  { printf '\e[38;2;215;25;33m✕ %s\e[0m\n' "$*"; fail=1; }
ok()   { printf '  ok %s\n' "$*"; }

say "bash syntax"
for f in install.sh lib/*.sh deps/lint.sh; do
    bash -n "$f" && ok "$f" || bad "$f"
done

say "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck install.sh lib/*.sh && ok "no findings" || bad "shellcheck findings above"
else
    printf '  (shellcheck not installed: pacman -S shellcheck, or drop the static binary in $PATH)\n'
fi

say "manifests"
python3 - <<'PY' && ok "toml + python parse" || { echo "  parse failed"; exit 1; }
import ast, tomllib
for f in ("deps/deps.toml", "deps/usage.toml", "deps/units.toml", "deps/reddoted.lock"):
    tomllib.load(open(f, "rb"))
for f in ("deps/check.py", "deps/query.py", "deps/by-package.py"):
    ast.parse(open(f).read())
PY

say "usage evidence"
python3 deps/by-package.py --check >/dev/null && ok "every package documented" || bad "a package has no usage evidence"

say "ghostty config"
if command -v ghostty >/dev/null; then
    if out=$(ghostty +validate-config --config-file="$PWD/stow/ghostty/.config/ghostty/config" 2>&1); then
        ok "ghostty accepted every option"
    else
        bad "ghostty rejects:"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
else
    ok "ghostty not installed here, skipped"
fi

say "starship config"
if command -v starship >/dev/null; then
    # starship prints warnings on stderr for unknown or deprecated keys and still
    # exits 0, so stderr is the signal, not the exit code
    cache=$(mktemp -d)
    out=$(cd /tmp && TERM=xterm-256color STARSHIP_SHELL=fish STARSHIP_CACHE="$cache" \
        STARSHIP_CONFIG="$PWD/stow/starship/.config/starship.toml" \
        starship prompt --status=0 2>&1 >/dev/null)
    rm -rf "$cache"
    if [ -n "$out" ]; then
        bad "starship complaints:"
        printf '%s\n' "$out" | sed 's/^/    /'
    else
        ok "starship rendered with no warning"
    fi
else
    ok "starship not installed here, skipped"
fi

say "fish config"
fish_bad=""
for f in stow/fish/.config/fish/config.fish stow/fish/.config/fish/conf.d/*.fish; do
    out=$(fish -n "$f" 2>&1) || fish_bad="${fish_bad}
    $f: $out"
done
# and a real interactive load, which is what catches a bad function body or an
# unknown command inside conf.d that -n does not see
if command -v fish >/dev/null; then
    tmp=$(mktemp -d)
    mkdir -p "$tmp/fish"
    cp -r stow/fish/.config/fish/. "$tmp/fish/"
    # timeout: a conf.d file that waits for input must not hang the lint
    out=$(TMUX_AUTOSTART=0 XDG_CONFIG_HOME="$tmp" timeout 10 script -qec "fish -i -c exit" /dev/null 2>&1 |
          grep -iE "error|unknown command|did not|fail" || true)
    rm -rf "$tmp"
    [ -n "$out" ] && fish_bad="${fish_bad}\n    interactive load: $out"
fi
if [ -n "$fish_bad" ]; then
    bad "fish:"
    printf '%b\n' "$fish_bad" | sed 's/^ *$//'
else
    ok "every file parses and an interactive shell starts clean"
fi

say "tmux config loads clean"
# tmux is the authority on its own options. Anything it rejects shows up here
# instead of in a screenshot of a broken pane.
tmux_rejects=$(
    sock="tmuxlint-$$"
    # start a bare server, then source the config: source-file returns every
    # rejection to the client, including "invalid option" for invented names
    tmux -L "$sock" -f /dev/null new-session -d -s check >/dev/null 2>&1
    out=$(tmux -L "$sock" source-file "$PWD/stow/tmux/.config/tmux/tmux.conf" 2>&1)
    tmux -L "$sock" kill-server 2>/dev/null
    printf '%s' "$out" | grep -v '^$' | sort -u
)
if [ -n "$tmux_rejects" ]; then
    bad "tmux rejects:"
    printf '%s\n' "$tmux_rejects" | sed 's/^/    /'
else
    ok "no option, value or binding was rejected"
fi

say "panel balance"
for f in install.sh lib/*.sh; do
    opened=$(grep -c 'ui_header "' "$f" || true)
    closed=$(grep -c 'ui_panel_close' "$f" || true)
    if [ "$opened" -gt "$closed" ]; then
        bad "$f opens $opened panels but closes $closed"
    else
        ok "$f: $opened opened, $closed closed"
    fi
done

say "dry run of every mode"
for mode in "--profile terminal" "--profile standard" "--profile full" \
            "--stow ghostty" "--stow fish" "--stow yazi" "--stow reddoted" \
            "--only base,core,fish" "--only reddoted,core" \
            "--links" "--deps" "--version" "--help"; do
    # shellcheck disable=SC2086
    if ./install.sh $mode --dry-run >/dev/null 2>&1 || [ "$mode" = "--version" ] || [ "$mode" = "--help" ]; then
        ok "$mode"
    else
        bad "$mode"
    fi
done

printf '\n'
if [ "$fail" -eq 0 ]; then
    say "all checks passed"
else
    bad "something above failed"
fi
exit "$fail"
