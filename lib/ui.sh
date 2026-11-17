#!/usr/bin/env bash
# lib/ui.sh - presentation only. No logic, no side effects on the system.
#
# Shape follows the house install.sh convention: a `=== title ===` header, then
# aligned `key : value` lines, phases numbered `N)`, and one result tag per line
# ([ok], [info], [warn], [skip], [fail]) so a piped log stays readable and
# greppable. Colour is decoration on the tag; it never carries meaning that the
# tag does not already carry.

# Whether stdout is a terminal, captured before the log redirect turns stdout
# into a pipe. Everything that needs a TTY asks this, not `[ -t 1 ]`.
UI_TTY=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    UI_TTY=1
    UI_RED=$'\e[38;2;215;25;33m'
    UI_WHITE=$'\e[38;2;242;242;242m'
    UI_GREY=$'\e[38;2;138;138;138m'
    UI_DIM=$'\e[38;2;74;74;74m'
    UI_BOLD=$'\e[1m'
    UI_OFF=$'\e[0m'
    UI_HIDE=$'\e[?25l'
    UI_SHOW=$'\e[?25h'
    UI_SEL=$'\e[48;2;242;242;242m\e[38;2;14;14;14m'
else
    UI_RED='' UI_WHITE='' UI_GREY='' UI_DIM='' UI_BOLD='' UI_OFF=''
    UI_HIDE='' UI_SHOW='' UI_SEL=''
fi

# ── log ─────────────────────────────────────────────────────────────────────
# Every line, including pacman's own output, is duplicated into a file. On
# failure the trap points at it and shows the tail, so the useful part is one
# path away instead of scrolled off the top of the terminal.
UI_LOG="${XDG_STATE_HOME:-${HOME}/.local/state}/dotfiles/install-$(date +%Y%m%d-%H%M%S).log"
# A log is nice to have, never required: a read-only $HOME or a sandboxed state
# directory must not stop an install. If the file cannot be created, the run
# continues unlogged and the header says so.
ui_log_init() {
    local dir
    dir="$(dirname "${UI_LOG}")"
    if ! { mkdir -p "${dir}" && : > "${UI_LOG}"; } 2>/dev/null; then
        UI_LOG=""
        return 0
    fi
    exec > >(tee -a "${UI_LOG}") 2>&1
}

ui_log_short() { # for a panel: the full path goes in the header, this fits
    if [ -n "${UI_LOG:-}" ]; then
        printf '%s' "$(basename "${UI_LOG}")"
    else
        printf 'off'
    fi
}

ui_log_label() {
    if [ -n "${UI_LOG:-}" ]; then printf '%s' "${UI_LOG}"; else printf 'disabled (state dir not writable)'; fi
}

# ── terminal size ───────────────────────────────────────────────────────────
# /dev/tty, not $LINES: the variable is not exported by every shell or pty, and a
# menu that thinks the terminal is 24 rows on a 50-row screen scrolls the frame
# out of view.
ui_term_size() {
    # `stty size` answers "0 0" on a pty with no window size set (script, some CI
    # runners, docker exec without -t). Zero is not a size: fall back to the
    # environment, then to 80x24.
    local size rows cols
    size="$(stty size 2>/dev/null </dev/tty || true)"
    rows="${size%% *}"
    cols="${size##* }"
    case "${rows}" in ''|0|*[!0-9]*) rows="${LINES:-24}" ;; esac
    case "${cols}" in ''|0|*[!0-9]*) cols="${COLUMNS:-80}" ;; esac
    UI_ROWS="${rows}"
    UI_COLS="${cols}"
}

# ── error trap ──────────────────────────────────────────────────────────────
# -E makes this fire inside functions and subshells too, which is where most
# steps actually fail. One guard variable keeps a failure inside the handler
# from re-entering it.
UI_ERR_TRAPPED=0
ui_err_trap() {
    local status="$1" line="$2" cmd="$3"
    [ "${UI_ERR_TRAPPED}" -eq 1 ] && return
    UI_ERR_TRAPPED=1

    # Snapshot the log before printing anything: the handler's own output goes
    # through tee into the same file, so a tail taken later quotes itself.
    local -a tail=()
    if [ -n "${UI_LOG:-}" ] && [ -f "${UI_LOG}" ]; then
        mapfile -t tail < <(tail -6 "${UI_LOG}" 2>/dev/null || true)
    fi

    printf '%s' "${UI_SHOW}"
    {
        printf '\n'
        printf '  %s[fail]%s %s\n' "${UI_RED}" "${UI_OFF}" "${cmd}"
        printf '         exit %s, line %s\n' "${status}" "${line}"
        printf '         log: %s\n' "$(ui_log_label)"
        local l
        for l in "${tail[@]}"; do printf '         | %s\n' "${l}"; done
        printf '\n'
    } >&2
    exit "${status}"
}

# ── result lines ────────────────────────────────────────────────────────────
ui_ok()   { printf '  %s[ok]%s %s\n'   "${UI_GREY}" "${UI_OFF}" "$*"; }
ui_info() { printf '  %s[info]%s %s\n' "${UI_DIM}"  "${UI_OFF}" "$*"; }
ui_skip() { printf '  %s[skip]%s %s\n' "${UI_DIM}"  "${UI_OFF}" "$*"; }
ui_warn() { printf '  %s[warn]%s %s\n' "${UI_RED}"  "${UI_OFF}" "$*" >&2; }
ui_fail() { printf '\n  %s[fail]%s %s\n\n' "${UI_RED}" "${UI_OFF}" "$*" >&2; exit 1; }
ui_die()  { ui_fail "$*"; }   # older name, same behaviour

# ui_report STATUS "ok text" "fail text". One place decides success wording, so
# no call site has to write `cmd && ok || warn`, which runs the fallback when the
# middle command fails for an unrelated reason (SC2015).
ui_report() {
    if [ "$1" -eq 0 ]; then ui_ok "$2"; else ui_warn "$3"; fi
}

# ── visible width ───────────────────────────────────────────────────────────
# Escape sequences occupy bytes but no columns. Every box measurement goes
# through this, which is why the right border lines up.
ui_vislen() {
    printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g' | LC_ALL=C.UTF-8 wc -m | tr -d ' '
}

# ── truecolor gradient ──────────────────────────────────────────────────────
ui_truecolor() {
    [ "${UI_TTY}" -eq 1 ] || return 1
    case "${COLORTERM:-}" in *truecolor*|*24bit*) return 0 ;; esac
    case "${TERM:-}" in *direct*|*truecolor*) return 0 ;; esac
    return 1
}

# d o t f i l e s in a gradient from ink to red. Falls back to bold white, so a
# 256-colour terminal or a pipe gets the same wordmark without the maths.
ui_wordmark() {
    local text="$1" i n r g b out=""
    n=${#text}
    if ! ui_truecolor; then
        printf '  %s%s%s\n' "${UI_BOLD}${UI_WHITE}" "$text" "${UI_OFF}"
        return 0
    fi
    for ((i = 0; i < n; i++)); do
        r=$(( 242 - (242 - 215) * i / (n > 1 ? n - 1 : 1) ))
        g=$(( 242 - (242 - 25)  * i / (n > 1 ? n - 1 : 1) ))
        b=$(( 242 - (242 - 33)  * i / (n > 1 ? n - 1 : 1) ))
        out+=$'\e[38;2;'"${r};${g};${b}m${text:i:1}"
    done
    printf '  %s%s\n' "${out}" "${UI_OFF}"
}

# ── panels ──────────────────────────────────────────────────────────────────
# Rounded box, right border aligned by visible width. ui_kv buffers into the
# open panel, so call sites do not change: open, emit keys, close.
UI_PANEL_OPEN=0
UI_PANEL_TITLE=""
UI_PANEL=()
UI_PANEL_W=66

ui_panel_open() {
    UI_PANEL_TITLE="$1"
    UI_PANEL=()
    UI_PANEL_OPEN=1
    ui_mark "=== $1 ==="
}

ui_panel_close() {
    [ "${UI_PANEL_OPEN}" -eq 1 ] || return 0
    local width=${UI_PANEL_W} line len pad head
    local -a out=()

    head="${UI_PANEL_TITLE}"
    pad=$(( width - ${#head} - 3 ))
    [ "$pad" -lt 2 ] && pad=2
    out+=("${UI_DIM}╭─${UI_OFF} ${UI_BOLD}${head}${UI_OFF} ${UI_DIM}$(printf '─%.0s' $(seq 1 "$pad"))╮${UI_OFF}")

    for line in "${UI_PANEL[@]}"; do
        len=$(ui_vislen "$line")
        if [ "$len" -ge "$width" ]; then
            out+=("${UI_DIM}│${UI_OFF} ${line}")
            continue
        fi
        out+=("${UI_DIM}│${UI_OFF} ${line}$(printf '%*s' $((width - len)) '') ${UI_DIM}│${UI_OFF}")
    done

    out+=("${UI_DIM}╰$(printf '─%.0s' $(seq 1 $((width + 1))))╯${UI_OFF}")

    printf '\n'
    for line in "${out[@]}"; do printf '  %s\n' "$line"; done
    UI_PANEL_OPEN=0
}

# ── structure ───────────────────────────────────────────────────────────────
ui_blank()  { printf '\n'; }

# ── timing and animation ────────────────────────────────────────────────────
UI_T0=$(date +%s)
UI_ANIM=1
[ -n "${NO_COLOR:-}" ] && UI_ANIM=0

ui_elapsed() { # seconds since the run started, as m:ss
    local s=$(( $(date +%s) - UI_T0 ))
    printf '%dm%02ds' $((s / 60)) $((s % 60))
}

# Markers go straight to the log file, not through stdout: the log is already a
# tee of stdout, and a marker the user has to read on screen is noise. This is the
# timeline you want when a phase fails and the screen has scrolled.
ui_mark() {
    [ -n "${UI_LOG:-}" ] || return 0
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"${UI_LOG}" 2>/dev/null || true
}

# Characters arrive one at a time. Off for pipes, NO_COLOR and --no-tui, and the
# delay is small enough that a slow terminal does not turn it into a pause.
ui_typewrite() {
    local text="$1" i
    if [ "${UI_TTY}" -eq 1 ] && [ "${UI_ANIM}" -eq 1 ]; then
        for ((i = 0; i < ${#text}; i++)); do
            printf '%s' "${text:i:1}"
            sleep 0.010
        done
        printf '\n'
        return 0
    fi
    printf '%s\n' "${text}"
}
ui_indent() { printf '    '; }   # continuation line under a phase

ui_header() { # $1 = title. Opens a panel; pair with ui_panel_close.
    ui_panel_open "$1"
}

ui_kv() { # $1 = key, $2 = value. Buffered into the open panel, or printed.
    if [ "${UI_PANEL_OPEN}" -eq 1 ]; then
        UI_PANEL+=("${UI_GREY}$(printf '%-9s' "$1")${UI_OFF} : $2")
        return 0
    fi
    printf '  %-9s : %s\n' "$1" "$2"
}

PHASE=0
ui_step() { # $1 = phase name. TOTAL_STEPS=0 means "not numbered": a preamble that
            # must not consume a phase number, so counted phases run 1..N.
    if [ "${TOTAL_STEPS:-0}" -eq 0 ]; then
        # preamble: no number, no timer, so its "done" is not reported at all
        PHASE_T0=""
        PHASE_NAME="$1"
        printf '\n  %s── %s%s\n' "${UI_DIM}" "$1" "${UI_OFF}"
        return 0
    fi
    PHASE=$((PHASE + 1))
    PHASE_NAME="$1"
    PHASE_T0=$(date +%s)
    ui_mark "phase ${PHASE}/${TOTAL_STEPS} ${1}, started"
    local filled empty bar done=$((PHASE * 10 / TOTAL_STEPS))
    filled=$(printf '█%.0s' $(seq 1 "$done"))
    empty=$(printf '░%.0s' $(seq 1 $((10 - done))))
    bar="${UI_RED}${filled}${UI_DIM}${empty}${UI_OFF}"
    printf '\n  %s%s/%s%s %s%s%s %s\n' \
        "${UI_DIM}" "$PHASE" "$TOTAL_STEPS" "${UI_OFF}" "${UI_BOLD}" "$1" "${UI_OFF}" "$bar"
}

ui_phase_done() { # closes the phase ui_step opened, so the log has durations
    [ -n "${PHASE_T0:-}" ] || return 0
    local took=$(( $(date +%s) - PHASE_T0 ))
    ui_mark "phase ${PHASE:-?} ${PHASE_NAME:-?}, finished in ${took}s"
}

# ── keys ────────────────────────────────────────────────────────────────────
ui_read_key() { # sets UI_KEY; returns 1 at EOF. Recognises arrows, space, enter.
    local k
    IFS= read -rsn1 k || return 1
    case "$k" in
        $'\x1b')
            # Terminals disagree on escape sequences: arrows are 2 bytes after
            # ESC, Home/End/PageUp/PageDown are 3 ("[H") or 4 ("[1~"). Read up to
            # four with a short timeout and match the longest form first.
            local rest=''
            IFS= read -rsn4 -t 0.05 rest || true
            case "$rest" in
                '[A'|'[a') UI_KEY=up ;;
                '[B'|'[b') UI_KEY=down ;;
                '[C'|'[c') UI_KEY=right ;;
                '[D'|'[d') UI_KEY=left ;;
                '[H'|'[1~'|'[7~') UI_KEY=home ;;
                '[F'|'[4~'|'[8~') UI_KEY=end ;;
                '[5~') UI_KEY=pgup ;;
                '[6~') UI_KEY=pgdn ;;
                '[Z')  UI_KEY=backtab ;;
                *)     UI_KEY=esc ;;
            esac
            ;;
        '')     UI_KEY=enter ;;
        $'\n')  UI_KEY=enter ;;
        ' ')    UI_KEY=space ;;
        k)      UI_KEY=up ;;
        j)      UI_KEY=down ;;
        g)      UI_KEY=home ;;
        G)      UI_KEY=end ;;
        a)      UI_KEY=all ;;
        n)      UI_KEY=none ;;
        i)      UI_KEY=start ;;
        q)      UI_KEY=quit ;;
        *)      UI_KEY=other ;;
    esac
    return 0
}

# ── multi-select menu ───────────────────────────────────────────────────────
# Input:  MENU_ROWS   array of "type|id|label|description"; type is head or item
#         MENU_ON     ids that start checked
#         MENU_VISIBLE rows visible at once
# Output: MENU_PICKED ids left checked
#
# Every frame is built into an array first, then emitted under a single "move up
# N lines and clear" escape. No arithmetic about how many lines a frame uses.
ui_menu() {
    local title="$1"
    MENU_ACTION=0
    local -a picked=() buf=()
    local cursor=0 total=${#MENU_ROWS[@]} visible=${MENU_VISIBLE:-18}
    local top=0 last=0 i row type id label desc sets check r count=0

    for r in "${MENU_ON[@]}"; do [ -n "$r" ] && picked+=("$r"); done

    while [ "$cursor" -lt "$total" ] && [ "${MENU_ROWS[$cursor]%%|*}" = head ]; do
        cursor=$((cursor + 1))
    done

    printf '%s' "$UI_HIDE"
    while true; do
        [ "$cursor" -lt "$top" ] && top=$cursor
        [ "$cursor" -ge $((top + visible)) ] && top=$((cursor - visible + 1))
        [ "$top" -lt 0 ] && top=0
        local lastrow=$((total - 1))

        # the count is recomputed per frame: it is the feedback that space did
        # something, even when the toggled row is scrolled out of view
        count=0
        for r in "${picked[@]}"; do [ -n "$r" ] && count=$((count + 1)); done
        buf=()
        buf+=("  ${UI_BOLD}$1${UI_OFF}  ${UI_DIM}${count} selected${UI_OFF}")
        buf+=("")

        for ((i = top; i < top + visible && i < total; i++)); do
            IFS='|' read -r type id label desc sets <<<"${MENU_ROWS[$i]}"
            if [ "$type" = head ]; then
                if [ -n "${sets}" ]; then
                    local total=0 have=0 m
                    for m in ${sets//,/ }; do
                        total=$((total + 1))
                        printf '%s\n' "${picked[@]}" | grep -qxF -- "$m" && have=$((have + 1))
                    done
                    local mark=' '
                    [ "$have" -eq "$total" ] && mark='x'
                    if [ "$have" -gt 0 ] && [ "$have" -lt "$total" ]; then mark='~'; fi
                    local counted
                    counted="$(printf '%s/%s' "$have" "$total")"
                    buf+=("  ${UI_DIM}──${UI_OFF} ${UI_BOLD}${label}${UI_OFF} ${UI_DIM}${counted}${UI_OFF}")
                else
                    buf+=("  ${UI_DIM}── ${label}${UI_OFF}")
                fi
                continue
            fi

            # A row with a `sets` list is a preset: it cannot be checked on its
            # own, its state is derived from the members it would add. Three
            # states, so you can see exactly what a preset brings and what you
            # have taken out of it afterwards.
            check=' '
            if [ "$type" = action ]; then
                check=' '
            elif [ -n "${sets}" ]; then
                local total=0 have=0 m
                for m in ${sets//,/ }; do
                    total=$((total + 1))
                    printf '%s\n' "${picked[@]}" | grep -qxF -- "$m" && have=$((have + 1))
                done
                if [ "${have}" -eq "${total}" ]; then check='x'
                elif [ "${have}" -gt 0 ]; then check='~'
                fi
            elif [ ${#picked[@]} -gt 0 ] && [ -n "$id" ]; then
                printf '%s\n' "${picked[@]}" | grep -qxF -- "$id" && check='x'
            fi

            # The cursor row is a filled bar: ink on a light band, the one place
            # the menu inverts. Everything else stays dim so the bar is the only
            # thing competing for attention.
            local row_text pad
            row_text="$(printf '[%s] %-9s %s' "$check" "$label" "$desc")"
            pad=$(( 58 - ${#row_text} ))
            [ "$pad" -lt 1 ] && pad=1
            row_text="$(printf '%s%*s' "$row_text" "$pad" '')"

            if [ "$i" -eq "$cursor" ]; then
                if [ "${UI_TTY}" -eq 1 ] && [ -n "${UI_WHITE}" ]; then
                    buf+=("  ${UI_SEL}${row_text}${UI_OFF}")
                else
                    buf+=("  > ${row_text}")
                fi
            elif [ "$check" = x ]; then
                buf+=("    ${UI_GREY}${row_text}${UI_OFF}")
            else
                buf+=("    ${UI_DIM}${row_text}${UI_OFF}")
            fi
        done

        buf+=("")
        buf+=("  ${UI_DIM}↑↓ move · enter toggle · i install · a all · n none · q quit${UI_OFF}")

        [ "$last" -gt 0 ] && printf '\033[%dA' "$last"
        for row in "${buf[@]}"; do printf '\033[2K%s\n' "$row"; done
        last=${#buf[@]}

        ui_read_key || { printf '\033[%dA\033[J%s' "$last" "$UI_SHOW"; ui_fail "no input on stdin; use --yes for unattended installs"; }

        case "$UI_KEY" in
            home)
                cursor=0
                while [ "$cursor" -lt "$lastrow" ]; do
                    IFS='|' read -r type _ _ _ _ <<<"${MENU_ROWS[$cursor]}"
                    [ "$type" = head ] || break
                    cursor=$((cursor + 1))
                done
                ;;
            end)
                cursor=$lastrow
                while [ "$cursor" -gt 0 ]; do
                    IFS='|' read -r type _ _ _ _ <<<"${MENU_ROWS[$cursor]}"
                    [ "$type" = head ] || break
                    cursor=$((cursor - 1))
                done
                ;;
            pgup)   cursor=$((cursor > 8 ? cursor - 8 : 0)) ;;
            pgdn)   cursor=$((cursor + 8 < lastrow ? cursor + 8 : lastrow)) ;;
            up)
                cursor=$((cursor - 1))
                [ "$cursor" -lt 0 ] && cursor=0
                while [ "$cursor" -gt 0 ] && [ "${MENU_ROWS[$cursor]%%|*}" = head ]; do cursor=$((cursor - 1)); done
                while [ "$cursor" -lt "$total" ] && [ "${MENU_ROWS[$cursor]%%|*}" = head ]; do cursor=$((cursor + 1)); done
                ;;
            down)
                cursor=$((cursor + 1))
                [ "$cursor" -ge "$total" ] && cursor=$((total - 1))
                while [ "$cursor" -lt "$total" ] && [ "${MENU_ROWS[$cursor]%%|*}" = head ]; do cursor=$((cursor + 1)); done
                [ "$cursor" -ge "$total" ] && cursor=$((total - 1))
                ;;
            space|enter)
                IFS='|' read -r type id label desc sets <<<"${MENU_ROWS[$cursor]}"
                # Enter on the action row starts the run; everywhere else Enter
                # and space both toggle, which is what a checklist should do
                if [ "$UI_KEY" = enter ] && [ "$type" = action ]; then
                    MENU_ACTION=1
                    break
                fi
                [ "$type" = head ] && [ -z "${sets}" ] && continue
                if [ -n "${sets}" ]; then
                    local m have=0 total=0
                    for m in ${sets//,/ }; do
                        total=$((total + 1))
                        printf '%s\n' "${picked[@]}" | grep -qxF -- "$m" && have=$((have + 1))
                    done
                    local -a next=()
                    if [ "${have}" -eq "${total}" ]; then
                        for m in "${picked[@]}"; do
                            case ",${sets}," in *",${m},"*) continue ;; esac
                            next+=("$m")
                        done
                    else
                        next=("${picked[@]}")
                        for m in ${sets//,/ }; do
                            printf '%s\n' "${next[@]}" | grep -qxF -- "$m" && continue
                            next+=("$m")
                        done
                    fi
                    picked=("${next[@]}")
                    continue
                fi
                if printf '%s\n' "${picked[@]}" | grep -qxF -- "$id"; then
                    local -a keep=()
                    for r in "${picked[@]}"; do [ "$r" != "$id" ] && keep+=("$r"); done
                    picked=("${keep[@]}")
                else
                    picked+=("$id")
                fi
                ;;
            start)
                MENU_ACTION=1
                break
                ;;
            none)
                picked=()
                ;;
            all)
                picked=()
                for row in "${MENU_ROWS[@]}"; do
                    IFS='|' read -r type id label desc <<<"$row"
                    [ "$type" = item ] && picked+=("$id")
                done
                ;;
            quit)
                printf '\033[%dA\033[J%s' "$last" "$UI_SHOW"
                ui_fail "cancelled"
                ;;
        esac
    done

    printf '\033[%dA\033[J%s' "$last" "$UI_SHOW"
    MENU_PICKED=("${picked[@]}")
    return 0   # a function whose last command is a failing test kills `set -e`
}

ui_in_picked() {
    local x
    for x in "${MENU_PICKED[@]}"; do [ "$x" = "$1" ] && return 0; done
    return 1
}
