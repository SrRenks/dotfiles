#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Logging and silent execution
# ==============================
LOG_FILE="/tmp/install-$(date +%Y%m%d-%H%M%S).log"
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' EXIT

print_info() { echo -e "\033[0;32m[INFO]\033[0m $1" >&3; }
print_warn() { echo -e "\033[0;33m[WARN]\033[0m $1" >&3; }
print_error() { echo -e "\033[0;31m[ERROR]\033[0m $1" >&3; }

run_silent() {
    local desc="$1"
    shift
    echo -n "$desc... "
    local log_file
    log_file=$(mktemp)
    if "$@" &> "$log_file"; then
        echo -e "\033[0;32mOK\033[0m"
        rm -f "$log_file"
        return 0
    else
        local exit_code=$?
        echo -e "\033[0;31mFAILED\033[0m"
        echo "Error running: $*"
        echo "Exit code: $exit_code"
        echo "--- Output ---"
        cat "$log_file"
        echo "--------------"
        rm -f "$log_file"
        return $exit_code
    fi
}

run_interactive() {
    "$@"
}

# ==============================
# Configuration
#===============================
REQUIRED_COMMANDS=(
    zsh tmux nvim bat fzf zoxide lsd git curl wget xdg-open alacritty stow wl-clipboard
    lazygit yazi
)

# ==============================
# Distribution detection
#===============================
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="$ID"
    else
        print_error "Cannot detect Linux distribution."
        exit 1
    fi

    case "$OS_ID" in
        debian|ubuntu|linuxmint|pop|elementary|zorin)
            DISTRO_FAMILY="debian"
            ;;
        fedora|rhel|centos|rocky|alma)
            DISTRO_FAMILY="redhat"
            ;;
        arch|manjaro|endeavouros|garuda)
            DISTRO_FAMILY="arch"
            ;;
        opensuse*|suse)
            DISTRO_FAMILY="suse"
            ;;
        alpine)
            DISTRO_FAMILY="alpine"
            ;;
        *)
            print_error "Unsupported distribution: $OS_ID"
            exit 1
            ;;
    esac
    print_info "Detected distribution family: $DISTRO_FAMILY"
}

# ==============================
# Configure US International keyboard with accents (TTY)
# ==============================
configure_us_intl_tty() {
    print_info "Configuring TTY keyboard layout for US International (with accents/dead keys)..."

    if run_silent "Applying us-acentos map to current TTY" sudo loadkeys us-acentos; then
        print_info "us-acentos map loaded successfully for current session."
    else
        print_warn "Failed to load us-acentos map for current session. It may not be available."
    fi

    case "$DISTRO_FAMILY" in
        arch|debian|ubuntu|redhat|suse|alpine)
            print_info "Setting persistent keyboard layout for $DISTRO_FAMILY..."
            case "$DISTRO_FAMILY" in
                arch)
                    run_silent "Setting KEYMAP in /etc/vconsole.conf" \
                        sudo bash -c "echo 'KEYMAP=us-acentos' > /etc/vconsole.conf"
                    print_info "Persistent configuration set in /etc/vconsole.conf. Reboot to take full effect."
                    ;;
                debian|ubuntu)
                    if command -v dpkg-reconfigure &>/dev/null; then
                        echo 'console-data console-data/keymap/policy select Select keymap from list' | sudo debconf-set-selections
                        echo 'console-data console-data/keymap/full select us-acentos' | sudo debconf-set-selections
                        run_silent "Reconfiguring console-data" sudo dpkg-reconfigure -f noninteractive console-data
                    else
                        run_silent "Setting XKBLAYOUT in /etc/default/keyboard" \
                            sudo bash -c "echo 'XKBLAYOUT=\"us\"' > /etc/default/keyboard && echo 'XKBVARIANT=\"intl\"' >> /etc/default/keyboard"
                        print_info "Set XKBLAYOUT to 'us' with variant 'intl' in /etc/default/keyboard."
                    fi
                    ;;
                redhat)
                    if command -v localectl &>/dev/null; then
                        run_silent "Setting keymap via localectl" sudo localectl set-keymap us-acentos
                    else
                        run_silent "Setting KEYMAP in /etc/vconsole.conf" \
                            sudo bash -c "echo 'KEYMAP=us-acentos' > /etc/vconsole.conf"
                    fi
                    ;;
                suse)
                    if command -v localectl &>/dev/null; then
                        run_silent "Setting keymap via localectl" sudo localectl set-keymap us-acentos
                    else
                        print_warn "Please use YaST to set keyboard to 'US International (with dead keys)' for persistence."
                    fi
                    ;;
                alpine)
                    run_silent "Setting KEYMAP in /etc/conf.d/keymaps" \
                        sudo sed -i 's/^keymap=.*/keymap="us-acentos"/' /etc/conf.d/keymaps
                    ;;
            esac
            ;;
        *)
            print_warn "Unsupported distribution for persistent keyboard configuration."
            print_warn "You may need to manually add 'loadkeys us-acentos' to your startup scripts (e.g., ~/.zshrc, /etc/rc.local)."
            ;;
    esac

    print_info "Keyboard configuration for TTY completed."
}

# ==============================
# Package installation
#===============================
install_packages() {
    local packages=("$@")
    print_info "Installing system packages: ${packages[*]}"

    case "$DISTRO_FAMILY" in
        debian)
            run_silent "Updating package lists" sudo apt update
            run_silent "Installing packages" sudo apt install -y "${packages[@]}"
            if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
                run_silent "Creating bat symlink" sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
            fi
            ;;
        redhat)
            run_silent "Installing packages" sudo dnf install -y "${packages[@]}"
            ;;
        arch)
            run_silent "Installing packages" sudo pacman -S --noconfirm "${packages[@]}"
            ;;
        suse)
            run_silent "Installing packages" sudo zypper install -y "${packages[@]}"
            ;;
        alpine)
            run_silent "Installing packages" sudo apk add "${packages[@]}"
            ;;
        *) print_error "Unsupported package manager"; exit 1 ;;
    esac
}

# ==============================
# Install yay (AUR helper) for Arch
#===============================
install_yay() {
    if command -v yay &>/dev/null; then
        print_info "yay already installed."
        return
    fi
    print_info "Installing yay from AUR..."
    run_silent "Cloning yay repository" git clone --depth=1 https://aur.archlinux.org/yay.git /tmp/yay
    (cd /tmp/yay && run_silent "Building yay" makepkg -si --noconfirm)
    run_silent "Cleaning up" rm -rf /tmp/yay
    print_info "yay installed successfully."
}

# ==============================
# Install lazygit
#===============================
install_lazygit() {
    command -v lazygit && return
    print_info "Installing lazygit..."
    case "$DISTRO_FAMILY" in
        debian|ubuntu)
            LAZYGIT_VERSION=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep -Po '"tag_name": *"v\K[^"]*')
            run_silent "Downloading lazygit v$LAZYGIT_VERSION" curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
            run_silent "Extracting lazygit" tar xf /tmp/lazygit.tar.gz -C /tmp lazygit
            run_silent "Installing lazygit" sudo install /tmp/lazygit /usr/local/bin
            run_silent "Cleaning up" rm -f /tmp/lazygit /tmp/lazygit.tar.gz
            ;;
        redhat)
            run_silent "Enabling COPR for lazygit" sudo dnf copr enable atim/lazygit -y
            run_silent "Installing lazygit" sudo dnf install lazygit -y
            ;;
        arch)
            if command -v yay &>/dev/null; then
                run_silent "Installing lazygit via yay" yay -S --noconfirm lazygit
            else
                run_silent "Installing lazygit via pacman" sudo pacman -S --noconfirm lazygit
            fi
            ;;
        *)
            if command -v cargo &>/dev/null; then
                run_silent "Installing lazygit via cargo" cargo install lazygit
            else
                print_warn "Cargo not available. Skipping lazygit."
            fi
            ;;
    esac
}

# ==============================
# Install yazi
#===============================
install_yazi() {
    command -v yazi && return
    print_info "Installing yazi..."
    case "$DISTRO_FAMILY" in
        arch)
            if command -v yay &>/dev/null; then
                run_silent "Installing yazi via yay" yay -S --noconfirm yazi
            else
                run_silent "Installing yazi via pacman" sudo pacman -S --noconfirm yazi
            fi
            ;;
        *)
            # Tenta instalar via binário estático primeiro (recomendado)
            if command -v curl &>/dev/null && command -v unzip &>/dev/null; then
                if run_silent "Installing yazi via binary" bash -c '
                    set -e
                    version=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | grep -Po '\''"tag_name": *"v\K[^"]*'\'' || echo "26.1.22")
                    url="https://github.com/sxyazi/yazi/releases/download/v${version}/yazi-${version}-x86_64-unknown-linux-musl.zip"
                    tmp_dir="/tmp/yazi-install-$$"
                    mkdir -p "$tmp_dir"
                    curl -L -o "$tmp_dir/yazi.zip" "$url"
                    unzip -q "$tmp_dir/yazi.zip" -d "$tmp_dir"
                    binary_path=$(find "$tmp_dir" -name yazi -type f | head -n1)
                    sudo install -Dm755 "$binary_path" /usr/local/bin/yazi
                    rm -rf "$tmp_dir"
                '; then
                    print_info "yazi installed successfully from binary."
                    return 0
                else
                    print_warn "Binary installation failed, falling back to cargo..."
                fi
            else
                print_warn "curl or unzip not available, skipping binary download."
            fi

            if command -v cargo &>/dev/null; then
                if run_silent "Installing yazi via cargo" cargo install --locked yazi-fm; then
                    print_info "yazi installed successfully via cargo."
                else
                    print_error "cargo installation failed. You may need to update Rust."
                    return 1
                fi
            else
                print_error "Cargo not available. Cannot install yazi."
                return 1
            fi
            ;;
    esac
}

# ==============================
# Install rbw (Bitwarden CLI with agent) for any distro
# ==============================
install_rbw() {
    if command -v rbw &>/dev/null; then
        return 0
    fi

    print_info "Installing rbw (Bitwarden CLI with SSH agent)..."

    case "$DISTRO_FAMILY" in
        arch)
            run_silent "Installing rbw via pacman" sudo pacman -S --noconfirm rbw
            ;;
        debian)
            # Tenta via apt (pode não estar disponível em versões estáveis)
            if sudo apt install -y rbw &>/dev/null; then
                print_info "rbw installed via apt."
            else
                print_warn "rbw not found in apt repositories. Falling back to cargo..."
                if command -v cargo &>/dev/null; then
                    run_silent "Installing rbw via cargo" cargo install --locked rbw
                else
                    print_error "Cargo not available. Cannot install rbw."
                    return 1
                fi
            fi
            ;;
        redhat)
            # Fedora/EPEL tem rbw
            if sudo dnf install -y rbw &>/dev/null; then
                print_info "rbw installed via dnf."
            else
                print_warn "rbw not found in dnf repositories. Falling back to cargo..."
                if command -v cargo &>/dev/null; then
                    run_silent "Installing rbw via cargo" cargo install --locked rbw
                else
                    print_error "Cargo not available. Cannot install rbw."
                    return 1
                fi
            fi
            ;;
        alpine)
            run_silent "Installing rbw via apk" sudo apk add rbw
            ;;
        suse)
            # Não há pacote oficial, usar cargo
            if command -v cargo &>/dev/null; then
                run_silent "Installing rbw via cargo" cargo install --locked rbw
            else
                print_error "Cargo not available. Cannot install rbw."
                return 1
            fi
            ;;
        *)
            # Fallback universal: cargo
            if command -v cargo &>/dev/null; then
                run_silent "Installing rbw via cargo" cargo install --locked rbw
            else
                print_error "Cargo not available. Cannot install rbw."
                return 1
            fi
            ;;
    esac
}

# ==============================
# Setup rbw (Bitwarden CLI with SSH agent)
# ==============================
setup_rbw() {
    print_info "Setting up rbw (Bitwarden CLI with SSH agent)..."

    # Garantir que rbw está instalado
    if ! command -v rbw &>/dev/null; then
        install_rbw || return 1
    fi

    # Configuração do email (obrigatório)
    echo ""
    echo "rbw requires your Bitwarden email address."
    echo -n "Enter your email: "
    read -r email
    if [[ -n "$email" ]]; then
        run_silent "Configuring email" rbw config email "$email"
    else
        print_error "Email is required. Aborting."
        return 1
    fi

    # Opção para servidor self-hosted
    echo -n "Do you use a self-hosted Bitwarden server? (y/N) "
    read -r self_hosted
    if [[ "$self_hosted" =~ ^[Yy]$ ]]; then
        echo -n "Enter your server URL (e.g., https://bitwarden.example.com): "
        read -r server_url
        if [[ -n "$server_url" ]]; then
            run_silent "Configuring base_url" rbw config base_url "$server_url"
            # identity_url, ui_url, notifications_url são opcionais; podem ser derivados
        else
            print_warn "No URL provided. Skipping server configuration."
        fi
    fi

    # Login interativo (pode pedir 2FA)
    print_info "Logging in to Bitwarden (follow the prompts)..."
    run_interactive rbw login

    # Sincronizar
    run_silent "Syncing vault" rbw sync

    # Configurar SSH agent no .zshrc
    local sock_line='export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/rbw/ssh-agent-socket"'
    local agent_start_line='if ! pgrep -x "rbw-agent" > /dev/null; then rbw-agent --daemon; fi'
    if ! grep -q "rbw-agent" "$HOME/.zshrc" 2>/dev/null; then
        echo "" >> "$HOME/.zshrc"
        echo "# rbw SSH agent" >> "$HOME/.zshrc"
        echo "$agent_start_line" >> "$HOME/.zshrc"
        echo "$sock_line" >> "$HOME/.zshrc"
        print_info "Added rbw SSH agent configuration to ~/.zshrc"
    else
        print_info "rbw SSH agent already configured in ~/.zshrc"
    fi

    # Iniciar o agente agora
    if ! pgrep -x "rbw-agent" > /dev/null; then
        run_silent "Starting rbw-agent" rbw-agent --daemon
    fi

    # Desbloquear o cofre (opcional)
    echo ""
    echo -n "Unlock your vault now? (Y/n) "
    read -r unlock_choice
    if [[ -z "$unlock_choice" || "$unlock_choice" =~ ^[Yy]$ ]]; then
        run_interactive rbw unlock
    fi

    # Mostrar status
    echo ""
    print_info "rbw setup finished. Your SSH agent is ready."
    echo "You can test it with: ssh-add -l"
    echo "Socket: $SSH_AUTH_SOCK"
}

# ==============================
# TPM setup
#===============================
setup_tpm() {
    local tpm_path="$HOME/.tmux/plugins/tpm"
    if [[ ! -d "$tpm_path" ]]; then
        print_info "Cloning TPM..."
        run_silent "Cloning tpm" git clone --depth=1 https://github.com/tmux-plugins/tpm "$tpm_path"
    fi
    if [[ ! -f "$tpm_path/tpm" ]]; then
        print_error "TPM installation incomplete."
        exit 1
    fi
    print_info "TPM ready."
}

# ==============================
# Set default shell to zsh (optional)
#===============================
set_default_shell() {
    local zsh_path
    zsh_path="$(command -v zsh)"
    if [[ "$SHELL" != "$zsh_path" ]]; then
        echo -n "Change default shell to zsh? (y/N) "
        read -r resp
        if [[ "$resp" =~ ^[Yy]$ ]]; then
            run_silent "Changing default shell" chsh -s "$zsh_path"
            print_info "Default shell changed to zsh. Please log out and back in."
        fi
    else
        print_info "zsh is already the default shell."
    fi
}

# ==============================
# Main
#===============================
main() {
    detect_distro

    local common_packages=(
        zsh tmux neovim fzf zoxide lsd git curl wget stow wl-clipboard
    )

    case "$DISTRO_FAMILY" in
        debian) common_packages+=(openssh-client bat xdg-utils alacritty build-essential cargo unzip jq) ;;
        redhat) common_packages+=(openssh-clients bat xdg-utils alacritty gcc make cargo unzip jq) ;;
        arch)   common_packages+=(openssh bat xdg-utils alacritty base-devel rust unzip jq) ;;
        suse)   common_packages+=(openssh bat xdg-utils alacritty gcc make cargo unzip jq) ;;
        alpine) common_packages+=(openssh bat xdg-utils alacritty build-base cargo unzip jq) ;;
    esac

    install_packages "${common_packages[@]}"

    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        install_yay
    fi

    install_lazygit
    install_yazi
    echo ""
    echo "Do you want to configure the TTY keyboard for US International (accents, cedilla)?"
    echo -n "This enables ' + c = ç, etc. (Y/n) "
    read -r config_keyboard
    if [[ -z "$config_keyboard" || "$config_keyboard" =~ ^[Yy]$ ]]; then
        configure_us_intl_tty
    else
        print_info "Skipping TTY keyboard configuration."
    fi

    echo ""
    echo "Do you want to use Bitwarden as your SSH agent (via rbw)?"
    echo -n "This will install rbw and configure the SSH agent. (Y/n) "
    read -r use_bitwarden
    if [[ -z "$use_bitwarden" || "$use_bitwarden" =~ ^[Yy]$ ]]; then
        setup_rbw
    else
        print_info "Skipping Bitwarden SSH agent setup."
    fi

    setup_tpm
    set_default_shell

    print_info "Installation complete!"
    echo "Detailed log saved to: $LOG_FILE"
}

main