#!/usr/bin/env bash
# lib/detect.sh, read-only facts about this machine. Sets DET_* variables.
# Every command here is cheap; nothing blocks on the network.

detect() {
    # shellcheck source=/dev/null
    DET_PRETTY="$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-unknown}")"
    DET_KERNEL="$(uname -r)"
    DET_ARCH="$(uname -m)"
    DET_HOST="$(cat /sys/class/dmi/id/product_name 2>/dev/null || hostname)"

    # CPU / GPU: picks the graphics package set, and tells the user we looked
    DET_CPU="$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)"
    DET_GPU="$(lspci 2>/dev/null | awk -F': ' '/VGA|3D|Display/ {print $2; exit}')"
    case "$DET_GPU" in
        *AMD*|*Radeon*|*ATI*) DET_GPU_FAMILY="amd" ;;
        *Intel*)              DET_GPU_FAMILY="intel" ;;
        *NVIDIA*)             DET_GPU_FAMILY="nvidia" ;;
        *)                    DET_GPU_FAMILY="unknown" ;;
    esac

    DET_SHELL="$(basename "${SHELL:-unknown}")"
    DET_SESSION="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_TYPE:-tty}}"
    DET_RAM="$(awk '/MemTotal/ {printf "%.0f GiB", $2/1024/1024}' /proc/meminfo 2>/dev/null)"
    DET_DISK="$(df -h --output=avail / 2>/dev/null | tail -1 | tr -d ' ')"

    DET_PACMAN=0; command -v pacman >/dev/null && DET_PACMAN=1
    DET_STOW=0;   command -v stow >/dev/null && DET_STOW=1
    DET_GIT=0;    command -v git >/dev/null && DET_GIT=1

    DET_AUR=""
    command -v yay >/dev/null && DET_AUR="yay"
    [ -z "$DET_AUR" ] && command -v paru >/dev/null && DET_AUR="paru"

    DET_HYPR=0; command -v Hyprland >/dev/null && DET_HYPR=1

    # reddoted, if it is already here
    DET_RED_PATH="$(python3 "$DOTS/deps/query.py" reddoted-path 2>/dev/null || true)"
    DET_RED_PIN="$(python3 "$DOTS/deps/query.py" reddoted-rev 2>/dev/null || true)"
    DET_RED_HAVE=""
    if [ -n "$DET_RED_PATH" ] && [ -d "$DET_RED_PATH/.git" ]; then
        DET_RED_HAVE="$(git -C "$DET_RED_PATH" rev-parse --short HEAD 2>/dev/null || echo '?')"
    fi

    # package count already satisfied, for the opening panel
    DET_SATISFIED=0
    DET_TOTAL=0
    if [ "$DET_PACMAN" -eq 1 ] && command -v python3 >/dev/null; then
        local wanted
        mapfile -t wanted < <( { python3 "$DOTS/deps/query.py" pacman; python3 "$DOTS/deps/query.py" gaps; } 2>/dev/null | awk '!seen[$0]++')
        DET_TOTAL=${#wanted[@]}
        # one call: pacman -T prints only what is missing
        local missing
        mapfile -t missing < <(pacman -T "${wanted[@]}" 2>/dev/null || true)
        DET_SATISFIED=$((DET_TOTAL - ${#missing[@]}))
    fi
}

detect_panel() {
    ui_header "machine"
    local cpu="$DET_CPU" gpu="$DET_GPU"
    [ ${#cpu} -gt 40 ] && cpu="${cpu:0:37}..."
    [ ${#gpu} -gt 40 ] && gpu="${gpu:0:37}..."
    ui_kv "system" "${DET_PRETTY}  ${DET_ARCH} ${DET_KERNEL}"
    ui_kv "host" "${DET_HOST}  ${DET_RAM} ram, ${DET_DISK} free"
    ui_kv "cpu" "${cpu}"
    ui_kv "gpu" "${gpu} (${DET_GPU_FAMILY})"
    ui_kv "session" "${DET_SESSION}, shell ${DET_SHELL}, $([ "$DET_HYPR" -eq 1 ] && echo "hyprland present" || echo "hyprland absent")"
    ui_kv "tooling" "pacman $([ "$DET_PACMAN" -eq 1 ] && echo ok || echo missing), stow $([ "$DET_STOW" -eq 1 ] && echo ok || echo missing), git $([ "$DET_GIT" -eq 1 ] && echo ok || echo missing), aur ${DET_AUR:-none}"
    ui_panel_close
}

detect_panel_packages() {
    [ "$DET_TOTAL" -eq 0 ] && return 0
    local state red="not cloned"
    if [ "$DET_SATISFIED" -eq "$DET_TOTAL" ]; then
        state="all ${DET_TOTAL} requirements satisfied"
    else
        state="$((DET_TOTAL - DET_SATISFIED)) of ${DET_TOTAL} required packages missing"
    fi
    if [ -n "$DET_RED_HAVE" ]; then
        if [ "$DET_RED_HAVE" = "$DET_RED_PIN" ]; then
            red="at pin ${DET_RED_HAVE}"
        else
            red="at ${DET_RED_HAVE}, pin is ${DET_RED_PIN}"
        fi
    fi
    ui_header "state"
    ui_kv "packages" "${state}"
    ui_kv "reddoted" "${DET_RED_PATH:-?}  ${red}"
    ui_panel_close
}
