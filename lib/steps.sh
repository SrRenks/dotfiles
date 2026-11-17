#!/usr/bin/env bash
# lib/steps.sh, everything that changes the machine. Each step is idempotent:
# running it twice reports "already true" instead of redoing work.

BACKUP="$HOME/.dots-backup-$(date +%F_%H-%M-%S)"

# ── root access ─────────────────────────────────────────────────────────────
# A bare Arch has no sudo: `base` ships su and nothing else. The first phase
# installs sudo, but everything before that has to go through su.
asroot() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        su -c "$(printf '%q ' "$@")"
    fi
}

root_label() { # how to spell "as root" in a --dry-run line
    if [ "$(id -u)" -eq 0 ]; then printf ''
    elif command -v sudo >/dev/null 2>&1; then printf 'sudo'
    else printf 'su -c'; fi
}

# ── primitives ──────────────────────────────────────────────────────────────
backup_move() { # $1 = path under $HOME; moves it into $BACKUP, preserving depth
    local dst="$1" rel="${1#"$HOME"/}"
    mkdir -p "$BACKUP/$(dirname "$rel")"
    mv "$dst" "$BACKUP/$rel"
}

link_one() { # $1 = source, $2 = destination. Idempotent, backs up what was there.
    local src="$1" dst="$2"
    if [ -L "$dst" ]; then
        [ "$(readlink "$dst")" = "$src" ] && return 0
        rm -f "$dst"
    elif [ -e "$dst" ]; then
        backup_move "$dst"
        ui_info "backed up ${dst#"$HOME"/}"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
}

# ── stow engine ─────────────────────────────────────────────────────────────
# stow maps the *contents* of a package onto the target, and by default folds
# whole directories into one symlink. --no-folding is deliberate: a folded
# ~/.config/fish would make `fisher update` write plugins into reddoted instead
# of into $HOME, and the same trap exists for yazi's `ya pkg`.
stow_clean() { # $1 = stow dir, $2 = target, $3 = ignore regex (may be empty), $4.. = packages
    local dir="$1" target="$2" ignore="$3"; shift 3
    local pkg rel dst src
    for pkg in "$@"; do
        [ -d "$dir/$pkg" ] || continue
        while IFS= read -r rel; do
            if [ -n "$ignore" ] && printf '%s' "$rel" | grep -qE "$ignore"; then continue; fi
            dst="$target/${rel#"$pkg"/}"
            src="$dir/$rel"
            if [ -L "$dst" ]; then
                [ "$(readlink "$dst")" = "$src" ] && continue
                [ "$(readlink -f "$dst" 2>/dev/null)" = "$(readlink -f "$src" 2>/dev/null)" ] && continue
                rm -f "$dst"
            elif [ -e "$dst" ]; then
                backup_move "$dst"
                ui_info "backed up ${dst#"$HOME"/}"
            fi
        done < <(cd "$dir" && find "$pkg" -mindepth 1 \( -type f -o -type l \) -printf '%P\n' | sed "s|^|$pkg/|")
    done
}

# stow maps the *contents* of a package onto the target. So the stow dir must be
# the repository root and the package is the top directory that mirrors $HOME, # `-d reddoted/config fish` would put config.fish into ~/.config/config.fish.
# --no-folding keeps ~/.config/fish a real directory: a folded symlink would make
# `fisher update` write plugins into reddoted instead of into $HOME, and yazi's
# `ya pkg` has the same trap.
stow_apply() { # $1 = stow dir, $2 = target, $3 = ignore regex, $4.. = packages
    local dir="$1" target="$2" ignore="$3"; shift 3
    mkdir -p "$target"
    stow_clean "$dir" "$target" "$ignore" "$@"
    # stow matches --ignore as a regex against the entry name as it walks, and a
    # path that "ends in" it. One plain alternative per entry is what works.
    local -a opts=()
    if [ -n "$ignore" ]; then
        local pat
        for pat in ${ignore//|/ }; do opts+=(--ignore="$pat"); done
    fi
    local out
    out="$(stow --restow --no-folding --dir="$dir" --target="$target" "${opts[@]}" "$@" 2>&1 || true)"
    out="$(printf '%s\n' "$out" | grep -viE '^$|BUG in find_stowed' || true)"
    [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/      /' >&2
    return 0
}

# ── step 0 ──────────────────────────────────────────────────────────────────
step_tools() { # $@ = packages needed to read the manifest and to link
    ui_step "tools"
    local -a want=("$@") missing=()
    local p
    for p in "${want[@]}"; do
        pacman -T "$p" >/dev/null 2>&1 || missing+=("$p")
    done
    if [ ${#missing[@]} -eq 0 ]; then
        ui_ok "already here: ${want[*]}"
        return 0
    fi
    ui_info "installing ${missing[*]}"
    if [ "$DRY" -eq 1 ]; then
        ui_indent; printf '%s$ %s pacman -S --needed %s%s\n' "$UI_DIM" "$(root_label)" "${missing[*]}" "$UI_OFF"
        return 0
    fi
    if ! asroot pacman -S --needed --noconfirm "${missing[@]}"; then
        printf '\n'
        ui_warn "could not install ${missing[*]}"
        printf '  this needs root. On a fresh archinstall, either add yourself to wheel and re-login:\n'
        printf '    su -c "usermod -aG wheel %s"   then log out and back in\n' "$(id -un)"
        printf '  or run the installer from a root shell.\n\n'
        ui_die "no way to install packages"
    fi
}

# A bare Arch with no network manager has no route out; pacman would fail with a
# wall of "could not resolve" instead of saying what is actually wrong.
require_network() {
    command -v curl >/dev/null || return 0
    if curl -sSf --max-time 8 -o /dev/null https://archlinux.org/ 2>/dev/null; then
        return 0
    fi
    printf '\n'
    ui_warn "no network: https://archlinux.org is unreachable"
    printf '  pacman cannot install anything without it. On a fresh Arch:\n'
    printf '    systemctl start systemd-networkd   # or: dhcpcd, nmcli device connect\n'
    printf '    then run this again\n\n'
    ui_die "stopping before it wastes your time"
}

# ── packages ────────────────────────────────────────────────────────────────
step_packages() { # $1 = group ids, $2 = unit ids, $3 = 1 to include the gaps
    ui_step "packages"
    local -a wanted=() missing=()
    local groups="$1" units="$2" include_gaps="$3"

    # `if`, not `cond && cmd`: a false condition returns 1, and under `set -eE`
    # that status escapes the pipeline and trips the error trap on a run where
    # nothing was wrong. The final grep drops blank lines, so an empty result can
    # never become an empty package name handed to pacman.
    mapfile -t wanted < <(
        {
            if [ -n "$groups" ]; then python3 "$DOTS/deps/query.py" pacman --groups "$groups"; fi
            if [ -n "$units" ]; then python3 "$DOTS/deps/query.py" unit-packages --units "$units"; fi
            if [ "$include_gaps" = 1 ]; then python3 "$DOTS/deps/query.py" gaps; fi
        } | awk '!seen[$0]++' | grep -v '^$'
    )

    if [ ${#wanted[@]} -eq 0 ]; then
        ui_ok "nothing selected"
        return 0
    fi

    mapfile -t missing < <(pacman -T "${wanted[@]}" 2>/dev/null || true)
    if [ ${#missing[@]} -eq 0 ]; then
        ui_ok "all ${#wanted[@]} required packages present"
        return 0
    fi

    ui_info "${#missing[@]} of ${#wanted[@]} missing"
    printf '%s    %s%s\n' "$UI_DIM" "${missing[*]}" "$UI_OFF"
    if [ "$DRY" -eq 1 ]; then
        ui_indent; printf '%s$ %s pacman -S --needed %s%s\n' "$UI_DIM" "$(root_label)" "${missing[*]}" "$UI_OFF"
        return 0
    fi
    asroot pacman -S --needed --noconfirm "${missing[@]}" ||
        ui_warn "pacman reported a problem above; the rest of the setup still runs"
}

step_aur() {
    ui_step "aur"
    local -a wanted=() missing=()
    mapfile -t wanted < <(python3 "$DOTS/deps/query.py" aur --groups "$1")
    if [ ${#wanted[@]} -eq 0 ]; then ui_ok "nothing selected"; return 0; fi

    local p
    for p in "${wanted[@]}"; do pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p"); done
    if [ ${#missing[@]} -eq 0 ]; then ui_ok "already here: ${wanted[*]}"; return 0; fi

    local helper="${DET_AUR}"
    if [ -z "$helper" ]; then
        ui_info "no AUR helper · building yay-bin"
        if [ "$DRY" -eq 1 ]; then
            ui_indent; printf '%s$ git clone aur/yay-bin && makepkg -si%s\n' "$UI_DIM" "$UI_OFF"
            return 0
        fi
        local tmp; tmp="$(mktemp -d)"
        if git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay" >/dev/null 2>&1 &&
           ( cd "$tmp/yay" && makepkg -si --noconfirm ); then
            helper="$(command -v yay)"
            ui_ok "yay ready"
        else
            ui_warn "yay did not build; install by hand: ${missing[*]}"
        fi
        rm -rf "$tmp"
    fi
    [ -n "$helper" ] || return 0

    if [ "$DRY" -eq 1 ]; then
        ui_indent; printf '%s$ %s -S --needed %s%s\n' "$UI_DIM" "$helper" "${missing[*]}" "$UI_OFF"
        return 0
    fi
    "$helper" -S --needed --noconfirm "${missing[@]}" || ui_warn "AUR: not everything installed"
}

# ── system ──────────────────────────────────────────────────────────────────
# Units can be .service, .socket, .path… check the disk, not the bus: a fresh
# chroot or a container has no bus and would report everything as missing.
unit_file_exists() {
    local scope="$1" unit="$2" d suffix
    local -a dirs
    if [ "$scope" = system ]; then
        dirs=(/etc/systemd/system /run/systemd/system /usr/lib/systemd/system)
    else
        dirs=("$HOME/.config/systemd/user" /etc/systemd/user /usr/lib/systemd/user)
    fi
    for d in "${dirs[@]}"; do
        for suffix in "" .service .socket .path .timer; do
            [ -e "$d/$unit$suffix" ] && return 0
        done
    done
    return 1
}

step_services() {
    ui_step "services"
    local groups="$1" unit user_bus=0
    command -v systemctl >/dev/null || { ui_ok "no systemd"; return 0; }
    # no pipes here: under `set -o pipefail` a failing `systemctl | grep` reports
    # systemctl's status, not grep's, and the negation silently inverts.
    local probe
    if probe="$(systemctl --user is-system-running 2>&1)"; then
        user_bus=1
    else
        case "$probe" in
            *"Failed to connect"*|*"No data available"*) user_bus=0 ;;
            *) user_bus=1 ;;
        esac
    fi

    while read -r unit; do
        [ -n "$unit" ] || continue
        unit_file_exists system "$unit" || { ui_info "skip $unit (not installed)"; continue; }
        if systemctl is-enabled "$unit" >/dev/null 2>&1; then
            ui_ok "$unit already enabled"
        elif [ "$DRY" -eq 1 ]; then
            ui_indent; printf '%s$ asroot systemctl enable --now %s%s\n' "$UI_DIM" "$unit" "$UI_OFF"
        else
            local st=0
            asroot systemctl enable --now "$unit" >/dev/null 2>&1 || st=$?
            ui_report "$st" "$unit enabled" "could not enable $unit"
        fi
    done < <(python3 "$DOTS/deps/query.py" services-system --groups "$groups")

    while read -r unit; do
        [ -n "$unit" ] || continue
        unit_file_exists user "$unit" || { ui_info "skip $unit (not installed)"; continue; }
        if [ "$user_bus" -eq 0 ]; then
            ui_info "$unit, no user bus here"
            continue
        fi
        if systemctl --user is-enabled "$unit" >/dev/null 2>&1; then
            ui_ok "$unit already enabled"
        elif [ "$DRY" -eq 1 ]; then
            ui_indent; printf '%s$ systemctl --user enable --now %s%s\n' "$UI_DIM" "$unit" "$UI_OFF"
        else
            local st=0
            systemctl --user enable --now "$unit" >/dev/null 2>&1 || st=$?
            ui_report "$st" "$unit enabled" "could not enable $unit"
        fi
    done < <(python3 "$DOTS/deps/query.py" services-user --groups "$groups")
}

step_groups() {
    ui_step "groups"
    local groups="$1" g members
    while read -r g; do
        [ -n "$g" ] || continue
        members="$(getent group "$g" 2>/dev/null | cut -d: -f4 || true)"
        if printf '%s' "$members" | tr ',' '\n' | grep -qx "$(id -un)"; then
            ui_ok "$(id -un) already in $g"
        else
            ui_info "adding to $g (log out to take effect)"
            [ "$DRY" -eq 1 ] && { ui_indent; printf '%s$ asroot usermod -aG %s %s%s\n' "$UI_DIM" "$g" "$(id -un)" "$UI_OFF"; continue; }
            asroot usermod -aG "$g" "$(id -un)"
        fi
    done < <(python3 "$DOTS/deps/query.py" groups --groups "$groups")
}

# ── payload ─────────────────────────────────────────────────────────────────
step_reddoted() {
    ui_step "reddoted"
    local url path rev have
    url="$(python3 "$DOTS/deps/query.py" reddoted-url)"
    path="$(python3 "$DOTS/deps/query.py" reddoted-path)"
    rev="$(python3 "$DOTS/deps/query.py" reddoted-rev)"

    if [ ! -d "$path/.git" ]; then
        ui_info "cloning into $path"
        if [ "$DRY" -eq 1 ]; then
            ui_indent; printf '%s$ git clone %s %s%s\n' "$UI_DIM" "$url" "$path" "$UI_OFF"
            return 0
        fi
        mkdir -p "$(dirname "$path")"
        git clone --quiet "$url" "$path" || ui_die "clone failed: $url"
        git -C "$path" checkout --quiet "$rev" 2>/dev/null ||
            ui_warn "could not check out $rev; staying on the default branch"
    else
        have="$(git -C "$path" rev-parse --short HEAD)"
        if [ "$have" = "$rev" ]; then
            ui_ok "at pin $rev"
        else
            ui_warn "at $have, this repo pins $rev · run --update"
        fi
    fi

    reddoted_helper "$path"
    reddoted_greeter "$path"
}

# The shell pkexecs /usr/local/bin/reddot-thinkpad, a root-owned copy of
# hypr/scripts/glyph-thinkpad. reddoted's own installer never puts it there, so
# on a clean machine the fan page opens and every action fails. It is installed
# root-owned on purpose: a user-writable script must never run as root.
# --sddm in reddoted copies the greeter theme into /usr/share and writes the
# conf.d drop-in. Running it here is what makes `--stow reddoted --all` a
# one-shot install instead of "look at the README for the last step".
reddoted_greeter() {
    local path="$1"
    case ",$SELECTED_GROUPS," in
        *,greeter,*) ;;
        *) return 0 ;;
    esac
    ui_info "sddm: glyph greeter theme (root copy)"
    if [ "$DRY" -eq 1 ]; then
        ui_indent; printf '%s$ %s %s/install.sh --sddm%s\n' "$UI_DIM" "$(root_label)" "$path" "$UI_OFF"
        return 0
    fi
    local st=0
    asroot "$path/install.sh" --sddm || st=$?
    ui_report "$st" "greeter theme installed" "greeter: reddoted --sddm failed, run it by hand"
}

reddoted_helper() {
    local path="$1"
    local src="$path/config/hypr/scripts/glyph-thinkpad"
    local dst="/usr/local/bin/reddot-thinkpad"

    [ -f "$src" ] || return 0
    if [ -x "$dst" ]; then
        ui_ok "thinkpad helper present · $dst"
        return 0
    fi
    ui_info "installing the ThinkPad helper (root-owned, needs sudo)"
    if [ "$DRY" -eq 1 ]; then
        ui_indent; printf '%s$ %s install -o root -g root -m 755 %s %s%s\n' "$UI_DIM" "$(root_label)" "$src" "$dst" "$UI_OFF"
        return 0
    fi
    local st=0
    asroot install -D -o root -g root -m 755 "$src" "$dst" || st=$?
    ui_report "$st" "$dst" "could not install the helper; the fan/LED page will not work"
}

# The hub's own packages. When reddoted is also installed it owns the same
# targets (fish, ghostty, tmux, yazi, starship), so only the hub packages that
# reddoted does not ship are stowed, otherwise the two trees fight over $HOME.
stow_hub() {
    local -a pkgs=("$@")
    if [ ${#pkgs[@]} -eq 0 ]; then
        local entry
        for entry in "$DOTS"/stow/*/; do pkgs+=("$(basename "$entry")"); done
    fi
    [ ${#pkgs[@]} -eq 0 ] && return 0
    stow_apply "$DOTS/stow" "$HOME" "" "${pkgs[@]}"
    ui_ok "${#pkgs[@]} hub packages: ${pkgs[*]}"
}

step_stow() {
    ui_step "stow"
    command -v stow >/dev/null || ui_die "stow is not installed"
    local red; red="$(python3 "${DOTS}/deps/query.py" reddoted-path)"

    # `personal` is a reddoted override; without reddoted there is nothing to
    # override, so it stays out of the standalone list.
    local -a hub=()
    local u
    for u in "${SELECTED_UNITS[@]}"; do
        [ "$u" = personal ] && [ "$WANT_REDDOTED" -eq 0 ] && continue
        hub+=("$u")
    done

    if [ "$WANT_REDDOTED" -eq 0 ]; then
        if [ "$DRY" -eq 1 ]; then
            ui_indent; printf '%s$ stow --no-folding -d %s/stow -t ~ %s%s\n' "${UI_DIM}" "${DOTS}" "${hub[*]}" "${UI_OFF}"
            return 0
        fi
        stow_hub "${hub[@]}"
        return 0
    fi

    if [ ! -x "${red}/install.sh" ]; then
        ui_warn "reddoted is not there; stowing the hub units only"
        [ "$DRY" -eq 0 ] && stow_hub "${hub[@]}"
        return 0
    fi

    # The desktop owns fish, ghostty, tmux, yazi and starship. Asking for both is
    # not an error: reddoted's copies win and these are skipped.
    local -a safe=()
    for u in "${hub[@]}"; do
        case "$u" in
            fish|ghostty|tmux|yazi|starship) continue ;;
        esac
        safe+=("$u")
    done
    if [ ${#safe[@]} -ne ${#hub[@]} ]; then
        ui_warn "reddoted owns fish/ghostty/tmux/yazi/starship; the hub copies are not stowed"
    fi

    if [ "$DRY" -eq 1 ]; then
        ui_indent; printf '%s$ stow --no-folding -d %s -t ~/.config --ignore=fonts --ignore=sddm --ignore=xdg config%s\n' "${UI_DIM}" "${red}" "${UI_OFF}"
        if [ ${#safe[@]} -gt 0 ]; then
            ui_indent; printf '%s$ stow --no-folding -d %s/stow -t ~ %s%s\n' "${UI_DIM}" "${DOTS}" "${safe[*]}" "${UI_OFF}"
        fi
        return 0
    fi

    stow_apply "${red}" "${HOME}/.config" 'fonts|sddm|xdg' config
    ui_ok "config/ stowed into ~/.config"
    [ ${#safe[@]} -gt 0 ] && stow_hub "${safe[@]}"

    link_one "${red}/config/fonts" "${HOME}/.local/share/fonts/glyph"
    link_one "${red}/config/quickshell/rice/rice" "${HOME}/.local/bin/rice"
    link_one "${red}/config/xdg/yazi.desktop" "${HOME}/.local/share/applications/yazi.desktop"
    ui_ok "fonts/glyph, ~/.local/bin/rice, yazi.desktop"

    local links="${red}/config/quickshell/glyph/term/links" f d
    if [ -f "${links}" ]; then
        while IFS='|' read -r f d; do
            case "$f" in ''|'#'*) continue ;; esac
            # The hub owns these. reddoted's copy is a fallback for when the hub
            # unit is not selected, not something that should overwrite the link
            # stow just made.
            case "$f" in
                fastfetch|starship) continue ;;
            esac
            link_one "${red}/config/quickshell/glyph/term/${f}" "${HOME}/.config/${d}"
        done < "${links}"
        ui_ok "term/links: starship, btop, cava, gtk"
    fi

    mkdir -p "${HOME}/.config/demonshot" "${XDG_STATE_HOME:-${HOME}/.local/state}/rice" "${HOME}/Pictures/Wallpapers"
    printf 'glyph\n' > "${XDG_STATE_HOME:-${HOME}/.local/state}/rice/shell"
    command -v fc-cache >/dev/null && fc-cache -f >/dev/null 2>&1
    if command -v gsettings >/dev/null && gsettings get org.gnome.desktop.interface color-scheme >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark &&
        gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark &&
        ui_ok "gtk dark scheme"
    fi
}

step_wiring() {
    ui_step "wiring"
    local dry="$DRY"

    if command -v fish >/dev/null; then
        ui_info "fisher plugins"
        if [ "$dry" -eq 1 ]; then
            ui_indent; printf '%s$ fish -c "fisher update"%s\n' "$UI_DIM" "$UI_OFF"
        else
            local st=0
            fish -c '
                if not functions -q fisher
                    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
                end
                fisher update
            ' >/dev/null 2>&1 || st=$?
            ui_report "$st" "fish plugins current" "fisher: some plugins did not install"
        fi

        if [ "${SHELL##*/}" != "fish" ]; then
            ui_info "login shell is ${SHELL##*/}"
            if [ "$dry" -eq 1 ] || confirm "make fish the login shell?"; then
                [ "$dry" -eq 1 ] && ui_indent
                [ "$dry" -eq 1 ] && printf '%s$ chsh -s %s%s\n' "$UI_DIM" "$(command -v fish)" "$UI_OFF"
                [ "$dry" -eq 0 ] && { chsh -s "$(command -v fish)" && ui_ok "login shell → fish"; }
            fi
        fi
    fi

    if command -v ya >/dev/null && [ -d "$HOME/.config/yazi" ]; then
        if [ "$dry" -eq 1 ]; then
            ui_indent; printf '%s$ ya pkg install%s\n' "$UI_DIM" "$UI_OFF"
        else
            local st=0
            ( cd "$HOME/.config/yazi" && ya pkg install >/dev/null 2>&1 ) || st=$?
            ui_report "$st" "yazi plugins pinned" "yazi: run 'ya pkg install' in ~/.config/yazi"
        fi
    fi

    if command -v xdg-mime >/dev/null; then
        if [ "$dry" -eq 1 ]; then
            ui_indent; printf '%s$ xdg-mime default yazi.desktop inode/directory%s\n' "$UI_DIM" "$UI_OFF"
        else
            xdg-mime default yazi.desktop inode/directory && ui_ok "inode/directory → yazi"
            command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
        fi
    fi

    # tmux 3.x reads BOTH ~/.tmux.conf and ~/.config/tmux/tmux.conf. Pointing one
    # at the other loads the config twice: every bind applied twice and every
    # error printed twice, which is exactly what the duplicate message lines were.
    # With an XDG file in place, the old path has to go.
    if printf '%s\n' "${SELECTED_UNITS[@]}" | grep -qx tmux || [ "${WANT_REDDOTED:-0}" -eq 1 ]; then
        local tmuxrc="${HOME}/.tmux.conf"
        if [ -e "${tmuxrc}" ] || [ -L "${tmuxrc}" ]; then
            if [ "$DRY" -eq 1 ]; then
                ui_indent; printf '%s$ mv %s %s/tmux.conf%s\n' "${UI_DIM}" "${tmuxrc}" "${BACKUP}" "${UI_OFF}"
            else
                mkdir -p "${BACKUP}" && mv "${tmuxrc}" "${BACKUP}/tmux.conf"
                ui_ok "~/.tmux.conf moved aside (tmux would load it twice)"
            fi
        fi
    fi

    # tmux persistence: two plugins, cloned once into $HOME (never into the repo),
    # because tmux sources them from ~/.config/tmux/plugins and that directory is
    # a real directory next to the stowed symlinks.
    if printf '%s\n' "${SELECTED_UNITS[@]}" | grep -qx tmux || [ "${WANT_REDDOTED:-0}" -eq 1 ]; then
        ui_info "tmux plugins (resurrect, continuum)"
        local plugin_dir="${HOME}/.config/tmux/plugins" plugin
        for plugin in tmux-resurrect tmux-continuum; do
            if [ -d "${plugin_dir}/${plugin}" ]; then
                ui_ok "${plugin} present"
                continue
            fi
            if [ "$DRY" -eq 1 ]; then
                ui_indent; printf '%s$ git clone --depth 1 https://github.com/tmux-plugins/%s %s/%s%s\n' \
                    "${UI_DIM}" "${plugin}" "${plugin_dir}" "${plugin}" "${UI_OFF}"
                continue
            fi
            mkdir -p "${plugin_dir}"
            if git clone --quiet --depth 1 "https://github.com/tmux-plugins/${plugin}" "${plugin_dir}/${plugin}" 2>/dev/null; then
                ui_ok "${plugin} cloned"
            else
                ui_warn "${plugin}: clone failed; sessions will not survive a reboot"
            fi
        done
    fi

    # this repo replaces SrRenks/dotfiles, which owned ~/.zshrc through ~/dotfiles
    local zshrc="$HOME/.zshrc"
    if [ -L "$zshrc" ] && [[ "$(readlink "$zshrc")" == *dotfiles/zsh/* ]]; then
        ui_info "retiring ~/.zshrc (pointed at the old repo)"
        if [ "$dry" -eq 0 ]; then mkdir -p "$BACKUP" && mv "$zshrc" "$BACKUP/zshrc.link"; fi
    fi
}

step_verify() {
    ui_step "verify"
    if [ "$DRY" -eq 1 ]; then
        ui_indent; printf '%s$ python3 deps/check.py%s\n' "$UI_DIM" "$UI_OFF"
        return 0
    fi
    python3 "$DOTS/deps/check.py" || true
}
