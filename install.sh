#!/usr/bin/env bash
# SrRenks dotfiles, the whole machine in one run.
#
#   ./install.sh              interactive: pick what you want, see the plan, run it
#   ./install.sh --all        everything, optional groups included, no questions
#   ./install.sh --only base,terminal,reddoted,links,wiring
#   ./install.sh --profile full       everything, optional integrations included
#   ./install.sh --profile terminal   the hub alone: no reddoted, no Hyprland
#   ./install.sh --check      audit only, changes nothing
#   ./install.sh --update     move ~/Projects/reddoted to the pinned revision
#   ./install.sh --dry-run    print every command instead of running it
#   ./install.sh --yes        accept the defaults without the menu
#   ./install.sh --no-tui     plain output (logs, CI)
#
# Package names live in deps/deps.toml and nowhere else. The two exceptions are
# declared where they are used: the tools needed to *read* that file, and the
# services a group needs.
set -eEuo pipefail

DOTS="$(cd "$(dirname "$0")" && pwd)"
TOTAL_STEPS=9
VERSION="1.0.0"
DRY=0
ASSUME_YES=0
NO_TUI=0

. "$DOTS/lib/ui.sh"

trap 'ui_err_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR
ui_log_init
ui_term_size
trap 'printf "%s" "${UI_SHOW:-}"' EXIT INT TERM
. "$DOTS/lib/detect.sh"
. "$DOTS/lib/steps.sh"

# ── menu definition ─────────────────────────────────────────────────────────
# The rows come from the manifests, one per package, so the checklist cannot
# drift from what will actually be installed. Format: type|id|label|desc|sets.
mapfile -t MENU_ROWS < <(python3 "${DOTS}/deps/query.py" checklist)

# The default is the desktop preset: its sets are the ids it would check.
DEFAULT_PICKS="$(python3 "${DOTS}/deps/query.py" checklist |
    awk -F'|' '$2 == "preset:desktop" { print $5 }')"
IFS=',' read -r -a MENU_ON <<<"${DEFAULT_PICKS}"


# ── args ────────────────────────────────────────────────────────────────────
MODE="install"
ONLY=""
PROFILE=""
STOW_UNITS=""
OPTIONAL_FLAG=0
PRE_PICKED=0

# Profiles are the answer to "I don't use all of this": the minimum that still
# gives a working desktop, the full rice, or everything including the optional
# integrations.
# A profile is a preset id now: the same sets the checklist rows carry, so a
# profile cannot disagree with what the menu would check.
declare -A PROFILES=(
    [terminal]="preset:terminal"
    [standard]="preset:desktop"
    [full]="__all__"
)
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   MODE="check" ;;
        --update)  MODE="update" ;;
        --deps)    MODE="deps" ;;
        --links)   MODE="links" ;;
        --all)     ONLY="__all__" ;;
        --full)    PROFILE="full" ;;
        --stow)    shift; MODE="stow"; STOW_UNITS="${1:-}" ;;
        --profile) shift; PROFILE="${1:-}"; [ -n "${PROFILES[$PROFILE]:-}" ] || ui_die "unknown profile: $PROFILE (terminal, standard, full)" ;;
        --only)    shift; ONLY="${1:-}" ;;
        --dry-run) DRY=1 ;;
        --yes|-y)  ASSUME_YES=1 ;;
        --no-tui)  NO_TUI=1 ;;
        -h|--help) usage; exit 0 ;;
        -V|--version) printf 'dotfiles %s\n' "$VERSION"; exit 0 ;;
        *)         ui_die "unknown option: $1 (try --help)" ;;
    esac
    shift
done

confirm() { # $1 = question
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ "$NO_TUI" -eq 1 ] && return 0
    local reply
    read -rp "  $1 [Y/n] " reply || true
    case "${reply:-y}" in [Nn]*) return 1 ;; *) return 0 ;; esac
}

# ── plan ────────────────────────────────────────────────────────────────────
plan_panel() { # $1 = comma list of group ids, $2 = 1 if gaps are included
    local groups="$1" gaps="$2"
    local n_pacman n_aur n_red=0 n_links=0 n_wiring=0

    # groups and units both contribute packages; the count has to match what
    # step_packages will actually install
    n_pacman=$( { printf '%s\n' ${PACMAN_CS:-}
                  printf '%s\n' ${AUR_CS:-}
                  [ -n "${SELECTED_UNITS_CS:-}" ] && python3 "${DOTS}/deps/query.py" unit-packages --units "${SELECTED_UNITS_CS}"
                } | awk '!seen[$0]++' | grep -c . || true)
    n_aur=$(printf '%s\n' ${AUR_CS:-} | grep -c . || true)
    n_units=${#SELECTED_UNITS[@]}
    n_red=${WANT_REDDOTED:-0}
    n_links=${WANT_LINKS:-0}
    n_wiring=${WANT_WIRING:-0}

    ui_header "plan"
    ui_kv "packages" "${n_pacman} required${n_aur:+, ${n_aur} aur}"
    ui_kv "groups" "$(printf '%s' "$groups" | tr ',' ' ' | cut -c1-52)"
    [ "${n_units:-0}" -gt 0 ] && ui_kv "units" "$(printf '%s ' "${SELECTED_UNITS[@]}" | cut -c1-52)"
    ui_kv "reddoted" "$([ "$n_red" -eq 1 ] && echo "clone at $(python3 "${DOTS}/deps/query.py" reddoted-rev)" || echo skip)"
    ui_kv "links" "$([ "$n_links" -eq 1 ] && echo "stow" || echo skip)"
    ui_kv "wiring" "$([ "$n_wiring" -eq 1 ] && echo "fisher, ya pkg, xdg-mime" || echo skip)"
    ui_panel_close
}

# ── main ────────────────────────────────────────────────────────────────────
[ "$EUID" -eq 0 ] && ui_die "run this as your user; it calls sudo itself"
[ -t 0 ] || ASSUME_YES=1

case "$MODE" in
    check)
        exec python3 "$DOTS/deps/check.py" ;;
    update)
        detect
        update_only() {
            local path rev
            path="$(python3 "$DOTS/deps/query.py" reddoted-path)"
            rev="$(python3 "$DOTS/deps/query.py" reddoted-rev)"
            [ -d "$path/.git" ] || ui_die "$path is not a clone"
            [ -z "$(git -C "$path" status --porcelain)" ] || ui_die "$path has local changes"
            ui_info "moving $path → $rev"
            git -C "$path" fetch --quiet origin
            git -C "$path" checkout --quiet "$rev"
            ui_ok "now at $(git -C "$path" rev-parse --short HEAD)"
        }
        ui_header "dotfiles update"
        ui_kv "repo" "$(python3 "${DOTS}/deps/query.py" reddoted-path)"
        ui_kv "pin" "$(python3 "${DOTS}/deps/query.py" reddoted-rev)"
        ui_panel_close
        update_only
        exit 0 ;;
esac

command -v pacman >/dev/null || ui_die "this bootstrap targets Arch (no pacman); deps.toml lists the packages elsewhere"


detect

# The banner says what this run is about, not what the repo is called: the repo
# is `dotfiles` and reddoted is one of its units.
case "$MODE" in
    links) BANNER_SUB="Arch, links only, stow" ;;
    deps)  BANNER_SUB="Arch, packages and services" ;;
    stow)  case "$STOW_UNITS" in
               *reddoted*) BANNER_SUB="Arch, reddoted, Hyprland" ;;
               *)          BANNER_SUB="Arch, terminal units, stow" ;;
           esac ;;
    install) if [ "$PROFILE" = terminal ]; then
                 BANNER_SUB="Arch, terminal units, stow"
             else
                 BANNER_SUB="Arch, reddoted, Hyprland"
             fi ;;
    *)     BANNER_SUB="Arch, reddoted, Hyprland" ;;
esac
ui_blank
ui_wordmark "d o t f i l e s"
# One line under the wordmark: what, where, and where the log is. The panel that
# used to hold these said the same thing in five lines.
printf '  %s%s%s  %s·%s  %s%s%s\n' \
    "${UI_DIM}" "${BANNER_SUB}" "${UI_OFF}" \
    "${UI_DIM}" "${UI_OFF}" \
    "${UI_DIM}" "log $(ui_log_short)" "${UI_OFF}"

# Everything below reads deps.toml with python3, so the tools come first:
# Arch's `base` ships none of python, git, curl, stow or sudo.
TOOLS=(python git curl sudo)
case "$MODE" in
    stow|links) TOOLS+=(stow) ;;
esac
TOTAL_STEPS=0                      # the tools preamble is not a numbered phase
step_tools "${TOOLS[@]}"
ui_phase_done
require_network

# ── selection ───────────────────────────────────────────────────────────────
# expand any preset id into the ids it stands for, so --profile, --only and the
# menu all mean the same thing
expand_presets() {
    local -a out=()
    local id row sets
    for id in "$@"; do
        [ -n "$id" ] || continue
        case "$id" in
            preset:*)
                sets="$(printf '%s\n' "${MENU_ROWS[@]}" | awk -F'|' -v k="$id" '$2 == k { print $5 }')"
                IFS=',' read -r -a _p <<<"$sets"
                out+=("${_p[@]}")
                ;;
            *) out+=("$id") ;;
        esac
    done
    printf '%s\n' "${out[@]}"
}

if [ -n "$ONLY" ]; then
    if [ "$ONLY" = "__all__" ]; then
        MENU_PICKED=()
        IFS=',' read -r -a _all <<<"$(python3 "${DOTS}/deps/query.py" classify | cut -d'|' -f1 | paste -sd, -)"
        MENU_PICKED=("${_all[@]}")
    else
        IFS=',' read -r -a MENU_PICKED <<<"$ONLY"
        mapfile -t MENU_PICKED < <(expand_presets "${MENU_PICKED[@]}")
    fi
elif [ "$PRE_PICKED" -eq 1 ]; then
    :   # MENU_PICKED was built from the `reddoted` unit
elif [ -n "$PROFILE" ]; then
    if [ "${PROFILES[$PROFILE]}" = "__all__" ]; then
        IFS=',' read -r -a MENU_PICKED <<<"$(python3 "${DOTS}/deps/query.py" classify | cut -d'|' -f1 | paste -sd, -)"
    else
        IFS=',' read -r -a MENU_PICKED <<<"${PROFILES[$PROFILE]}"
        mapfile -t MENU_PICKED < <(expand_presets "${MENU_PICKED[@]}")
    fi
elif [ "$ASSUME_YES" -eq 1 ] || [ "$NO_TUI" -eq 1 ]; then
    MENU_PICKED=("${MENU_ON[@]}")
else
    # never draw more rows than the terminal can hold, or the redraw math scrolls
    MENU_VISIBLE=$(( UI_ROWS - 6 ))
    [ "$MENU_VISIBLE" -lt 6 ] && MENU_VISIBLE=6
    [ "$MENU_VISIBLE" -gt 26 ] && MENU_VISIBLE=26
    ui_menu "what should this machine have?"
    ui_blank
fi

# The menu mixes package groups and stow units. Split the pick into the two
# kinds, and let the actions the old menu had (links, wiring) be consequences:
# selecting anything that has files stows it, selecting anything that calls
# fisher or ya wires it.
# classify: id|pkg|group  or  id|unit|unit. One lookup, then the pick splits into
# an explicit package list, a group list for services, and the stow units.
declare -A KIND=() GROUP_OF=()
while IFS='|' read -r cid ckind cgroup; do
    [ -n "$cid" ] || continue
    KIND["$cid"]="$ckind"
    GROUP_OF["$cid"]="$cgroup"
done < <(python3 "${DOTS}/deps/query.py" classify)

AUR_ALL="$(python3 "${DOTS}/deps/query.py" aur | tr '\n' ' ')"
declare -A GROUP_PKGS=()
while IFS='|' read -r g_gid g_pkg _; do
    [ -n "$g_gid" ] || continue
    GROUP_PKGS["$g_gid"]="${GROUP_PKGS[$g_gid]:+${GROUP_PKGS[$g_gid]},}$g_pkg"
done < <(python3 "${DOTS}/deps/query.py" packages)

SELECTED_PKGS=()
SELECTED_UNITS=()
SELECTED_GROUPS=""
WANT_REDDOTED=0
add_group() { case ",${SELECTED_GROUPS}," in *",$1,"*) ;; *) SELECTED_GROUPS="${SELECTED_GROUPS:+$SELECTED_GROUPS,}$1" ;; esac; }
for id in "${MENU_PICKED[@]}"; do
    [ -n "$id" ] || continue
    case "${KIND[$id]:-}" in
        unit)
            local_unit="${GROUP_OF[$id]}"
            [ "$local_unit" = reddoted ] && { WANT_REDDOTED=1; continue; }
            SELECTED_UNITS+=("$local_unit")
            ;;
        pkg) SELECTED_PKGS+=("$id"); add_group "${GROUP_OF[$id]}" ;;
        group)
            # a bare group id on the command line means "all of its packages"
            IFS=',' read -r -a _gp <<<"${GROUP_PKGS[$id]:-}"
            for _p in "${_gp[@]}"; do
                [ -n "$_p" ] || continue
                case " ${SELECTED_PKGS[*]-} " in *" $_p "*) continue ;; esac
                SELECTED_PKGS+=("$_p")
                add_group "${GROUP_OF[$_p]:-$id}"
            done
            ;;
        *)   ui_warn "unknown component: $id" ;;
    esac
done

# reddoted carries its own package groups; asking for it is enough
if [ "$WANT_REDDOTED" -eq 1 ]; then
    while read -r gid; do
        [ -n "$gid" ] || continue
        case ",${SELECTED_GROUPS}," in *",${gid},"*) continue ;; esac
        SELECTED_GROUPS="${SELECTED_GROUPS:+$SELECTED_GROUPS,}$gid"
    done < <(python3 "${DOTS}/deps/query.py" unit-groups --units reddoted )
fi

# units marked `always` are this machine's own config: they ride along with any
# selection, including no selection at all
while read -r a; do
    [ -n "$a" ] || continue
    printf '%s\n' "${SELECTED_UNITS[@]}" | grep -qx -- "$a" && continue
    SELECTED_UNITS+=("$a")
done < <(python3 "${DOTS}/deps/query.py" unit-always)

SELECTED_UNITS_CS="$(IFS=,; echo "${SELECTED_UNITS[*]}")"
PACMAN_LIST=(); AUR_LIST=()
for _p in "${SELECTED_PKGS[@]}"; do
    case " ${AUR_ALL} " in
        *" $_p "*) AUR_LIST+=("$_p") ;;
        *)         PACMAN_LIST+=("$_p") ;;
    esac
done
PACMAN_CS="$(printf '%s ' "${PACMAN_LIST[@]}")"
AUR_CS="$(printf '%s ' "${AUR_LIST[@]}")"

WANT_LINKS=0
if [ ${#SELECTED_UNITS[@]} -gt 0 ] || [ "$WANT_REDDOTED" -eq 1 ]; then WANT_LINKS=1; fi

WANT_WIRING=0
if [ "$WANT_REDDOTED" -eq 1 ] ||
   printf '%s\n' "${SELECTED_UNITS[@]}" | grep -qxE 'fish|yazi|tmux'; then
    WANT_WIRING=1
fi

GAPS=0
case ",$SELECTED_GROUPS," in *,terminal,*) GAPS=1 ;; esac

if [ "$MODE" = "deps" ]; then WANT_REDDOTED=0; WANT_LINKS=0; WANT_WIRING=0; fi
if [ "$MODE" = "links" ]; then WANT_REDDOTED=1; WANT_LINKS=1; WANT_WIRING=1; fi

TOTAL_STEPS=1                      # verify, always (tools ran as the preamble)
if [ "$MODE" != "links" ]; then TOTAL_STEPS=$((TOTAL_STEPS + 4)); fi   # packages, aur, services, groups
[ "$WANT_REDDOTED" -eq 1 ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
[ "$WANT_LINKS" -eq 1 ]    && TOTAL_STEPS=$((TOTAL_STEPS + 1))
[ "$WANT_WIRING" -eq 1 ]   && TOTAL_STEPS=$((TOTAL_STEPS + 1))

plan_panel "$SELECTED_GROUPS" "$GAPS"
if [ "$DRY" -eq 1 ]; then
    ui_info "dry run, nothing will change"
elif [ "$MODE" = "install" ] && ! confirm "run this?"; then
    ui_die "cancelled"
fi

# ── run ─────────────────────────────────────────────────────────────────────
# (Tools already ran as phase 0, before anything read the manifest.)
if [ "$MODE" != "links" ]; then
    step_packages "${PACMAN_CS}" "$SELECTED_UNITS_CS"; ui_phase_done
    step_aur "${AUR_CS}"; ui_phase_done
    step_services "$SELECTED_GROUPS";         ui_phase_done
    step_groups "$SELECTED_GROUPS";           ui_phase_done
fi

if [ "$WANT_REDDOTED" -eq 1 ]; then step_reddoted; ui_phase_done; fi
if [ "$WANT_LINKS" -eq 1 ]; then step_stow; ui_phase_done; fi

if [ "$WANT_WIRING" -eq 1 ]; then step_wiring; ui_phase_done; fi
step_verify
ui_phase_done

# what was chosen becomes the scope of every future audit
if [ "$DRY" -eq 0 ] && [ -n "$SELECTED_GROUPS" ]; then
    sel_dir="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
    mkdir -p "$sel_dir"
    printf '%s\n' "$SELECTED_GROUPS" | tr ',' '\n' > "$sel_dir/groups"
fi

# ── closing ─────────────────────────────────────────────────────────────────
ui_blank
ui_header "done"
[ "${WANT_REDDOTED:-0}" -eq 1 ] && ui_kv "next" "reboot, or re-login if groups changed"
if [ "${WANT_REDDOTED:-0}" -eq 1 ]; then
    case ",${SELECTED_GROUPS}," in
        *,greeter,*) ui_kv "start" "SDDM lists Hyprland on boot" ;;
        *)           ui_kv "start" "tty1, then run Hyprland" ;;
    esac
fi
ui_kv "time" "$(ui_elapsed)"
ui_kv "check" "python3 deps/check.py"
ui_kv "update" "./install.sh --update, then --links"
ui_kv "undo" "~/${BACKUP##*/}"
ui_kv "log" "$(ui_log_short)"
ui_panel_close
ui_blank
