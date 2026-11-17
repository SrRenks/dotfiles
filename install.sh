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
# id|label|description, the ids are deps.toml group ids, except the last three,
# which are actions rather than packages.
# The two presets are computed from units.toml, never hand-listed: toggling one
# checks exactly the rows it would install, and the count in the description is
# the same query the installer uses.
PRESET_DESKTOP="reddoted,personal,$(python3 "${DOTS}/deps/query.py" unit-groups --units reddoted | paste -sd, -)"
PRESET_DESKTOP_N=$( { python3 "${DOTS}/deps/query.py" pacman --groups "$(python3 "${DOTS}/deps/query.py" unit-groups --units reddoted | paste -sd, -)"
                       python3 "${DOTS}/deps/query.py" unit-packages --units core
                       python3 "${DOTS}/deps/query.py" gaps; } | awk '!seen[$0]++' | grep -c . || true)
PRESET_HUB="$(python3 "${DOTS}/deps/query.py" unit-ids | grep -vxE 'reddoted|personal' | paste -sd, -)"
PRESET_HUB_N=$(python3 "${DOTS}/deps/query.py" unit-packages --units "$(python3 "${DOTS}/deps/query.py" unit-ids | grep -vxE 'reddoted|personal' | paste -sd, -)" | grep -c . || true)

MENU_ROWS=(
    "head||─ presets|"
    "preset|preset:desktop|desktop|reddoted and everything it needs, ${PRESET_DESKTOP_N} packages|${PRESET_DESKTOP}"
    "preset|preset:terminal|terminal|the hub alone, no Hyprland, ${PRESET_HUB_N} packages|${PRESET_HUB}"
    "head||─ system|"
    "item|base|base|build tools, stow, python, AUR helper"
    "item|graphics|graphics|mesa + vulkan, drivers for the GPU found"
    "item|session|desktop|hyprland, quickshell, portals, keyring"
    "item|audio|audio|pipewire, wireplumber"
    "item|network|network|networkmanager, bluetooth"
    "item|power|power|tlp (power-profiles-daemon excluded on purpose)"
    "head||─ surface|"
    "item|shell-core|tools|screenshots, clipboard, brightness, media"
    "item|shell-extras|tools+|swappy, recorder, qalc, trash, libvips"
    "item|fonts|fonts|jetbrains mono nerd, space mono, cjk, emoji"
    "item|icons|theming|papirus, adw-gtk3"
    "item|audio-tools|audio-app|pavucontrol, easyeffects"
    "item|apps|apps|dolphin, vscodium"
    "head||─ terminal|"
    # these are stow units, not package groups: picking one stows its config
    "item|core|core|git, bat, ripgrep: always stowed with anything else"
    "item|fish|fish|fish, starship, eza, zoxide, direnv, fzf"
    "item|tmux|tmux|tmux with popups, and login start with SSH separation"
    "item|ghostty|ghostty|the terminal profile"
    "item|starship|starship|the prompt"
    "item|yazi|yazi|file manager: openers, plugins, theme"
    "item|fastfetch|fastfetch|logo off, ANSI keys"
    "head||─ desktop|"
    "item|reddoted|reddoted|the whole rice: clone, pin, stow, greeter"
    "item|personal|personal|~/.config/hypr/user.lua, your monitors"
    "head||─ optional|"
    "item|tty|mouse|mouse on the virtual console, via gpm"
    "item|input|input|ydotool + input group (paste into field)"
    "item|yazi-extras|yazi+|udisks2, exiftool (mount, EXIF)"
    "item|greeter|sddm|login greeter + glyph theme"
    "item|flatpak-apps|flatpak|zen browser, via flathub"
    "item|geo|geoclue|weather location"
    "item|updates|checkupdates|faster update widget"
    "item|aur-theming|qt-theme|qtengine + darkly (AUR, Qt follows palette)"
    "item|thinkpad|thinkfan|fan curve + LEDs (ThinkPad; thinkfan is AUR)"
    "item|aur-cursor|cursor|bibata cursor (AUR)"
)

MENU_ON=(${PRESET_DESKTOP//,/ })

usage() {
    cat <<EOF

  dotfiles $VERSION, Arch, stow, reddoted

  ${UI_BOLD}modes${UI_OFF}
    ./install.sh                     interactive: pick components, see the plan, run it
    ./install.sh --stow fish,tmux    only those units (no reddoted, no Hyprland)
    ./install.sh --stow reddoted     the whole desktop, as one unit
    ./install.sh --profile NAME      terminal | standard | full
    ./install.sh --only a,b,c        explicit group list, no menu
    ./install.sh --check             audit only, changes nothing
    ./install.sh --update            move ~/Projects/reddoted to the pinned revision

  ${UI_BOLD}options${UI_OFF}
    --all         include the optional groups (greeter, flatpak, geoclue, thinkfan…)
    --optional    same, for the interactive path
    --dry-run     print every command instead of running it
    --yes         accept the defaults, no menu, no questions
    --no-tui      plain output, for logs and CI
    -h, --help    this
    -V, --version print the version

  ${UI_BOLD}units${UI_OFF}
    $(python3 "$DOTS/deps/query.py" unit-ids 2>/dev/null | sed 's/^/    /' | paste -sd' ' -)
EOF
}

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
declare -A PROFILES=(
    [terminal]="${PRESET_HUB}"
    [standard]="${PRESET_DESKTOP}"
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
    n_pacman=$( { [ -n "$groups" ] && python3 "${DOTS}/deps/query.py" pacman --groups "$groups"
                  [ -n "${SELECTED_UNITS_CS:-}" ] && python3 "${DOTS}/deps/query.py" unit-packages --units "${SELECTED_UNITS_CS}"
                  [ "$gaps" = 1 ] && python3 "${DOTS}/deps/query.py" gaps
                } | awk '!seen[$0]++' | grep -c . || true)
    n_aur=$(python3 "${DOTS}/deps/query.py" aur --groups "$groups" | grep -c . || true)
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
if [ -n "$ONLY" ]; then
    if [ "$ONLY" = "__all__" ]; then
        MENU_PICKED=()
        for row in "${MENU_ROWS[@]}"; do
            IFS='|' read -r type id label desc <<<"$row"
            [ "$type" = item ] && MENU_PICKED+=("$id")
        done
    else
        IFS=',' read -r -a MENU_PICKED <<<"$ONLY"
    fi
elif [ "$PRE_PICKED" -eq 1 ]; then
    :   # MENU_PICKED was built from the `reddoted` unit
elif [ -n "$PROFILE" ]; then
    if [ "${PROFILES[$PROFILE]}" = "__all__" ]; then
        MENU_PICKED=()
        for row in "${MENU_ROWS[@]}"; do
            IFS='|' read -r type id label desc <<<"$row"
            [ "$type" = item ] && MENU_PICKED+=("$id")
        done
    else
        IFS=',' read -r -a MENU_PICKED <<<"${PROFILES[$PROFILE]}"
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
GROUPS_ALL="$(python3 "${DOTS}/deps/query.py" ids)"
UNITS_ALL="$(python3 "${DOTS}/deps/query.py" unit-ids)"

in_list() { printf '%s\n' "$1" | grep -qx -- "$2"; }

SELECTED_GROUPS=""
SELECTED_UNITS=()
WANT_REDDOTED=0
for id in "${MENU_PICKED[@]}"; do
    [ -n "$id" ] || continue
    case "$id" in
        preset:*) continue ;;              # a preset is a shortcut, not a component
        reddoted) WANT_REDDOTED=1; continue ;;
        links|wiring) continue ;;          # kept for old command lines
    esac
    if in_list "${UNITS_ALL}" "$id"; then
        SELECTED_UNITS+=("$id")
    elif in_list "${GROUPS_ALL}" "$id"; then
        SELECTED_GROUPS="${SELECTED_GROUPS:+$SELECTED_GROUPS,}$id"
    else
        ui_warn "unknown component: $id"
    fi
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
    step_packages "$SELECTED_GROUPS" "$SELECTED_UNITS_CS" "$GAPS"; ui_phase_done
    step_aur "$SELECTED_GROUPS";              ui_phase_done
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
