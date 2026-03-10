#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Configuration
#===============================
REQUIRED_COMMANDS=(
    zsh tmux nvim bat fzf zoxide lsd git curl wget xdg-open alacritty stow wl-clipboard
    lazygit yazi
)

# ==============================
# Helper functions
#===============================
print_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
print_warn() { echo -e "\033[0;33m[WARN]\033[0m $1"; }
print_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

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
# Package installation
#===============================
install_packages() {
    local packages=("$@")
    print_info "Installing packages: ${packages[*]}"

    case "$DISTRO_FAMILY" in
        debian)
            sudo apt update
            sudo apt install -y "${packages[@]}"
            if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
                sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
                print_info "Created symlink batcat -> bat"
            fi
            ;;
        redhat) sudo dnf install -y "${packages[@]}" ;;
        arch)   sudo pacman -S --noconfirm "${packages[@]}" ;;
        suse)   sudo zypper install -y "${packages[@]}" ;;
        alpine) sudo apk add "${packages[@]}" ;;
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
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    (cd /tmp/yay && makepkg -si --noconfirm)
    rm -rf /tmp/yay
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
            curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
            tar xf lazygit.tar.gz lazygit
            sudo install lazygit /usr/local/bin
            rm -f lazygit lazygit.tar.gz
            ;;
        redhat)
            sudo dnf copr enable atim/lazygit -y
            sudo dnf install lazygit -y
            ;;
        arch)
            if command -v yay &>/dev/null; then
                yay -S --noconfirm lazygit
            else
                sudo pacman -S --noconfirm lazygit
            fi
            ;;
        *)
            if command -v cargo &>/dev/null; then
                cargo install lazygit
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
                yay -S --noconfirm yazi
            else
                sudo pacman -S --noconfirm yazi
            fi
            ;;
        *)
            if command -v cargo &>/dev/null; then
                cargo install --locked yazi-fm
            else
                print_warn "Cargo not available. Cannot install yazi."
            fi
            ;;
    esac
}

# ==============================
# Install snapd (if not available)
# ==============================
install_snapd() {
    if command -v snap &>/dev/null; then
        print_info "snapd already installed."
        return
    fi

    print_info "Installing snapd..."
    case "$DISTRO_FAMILY" in
        debian)
            sudo apt install -y snapd
            ;;
        redhat)
            sudo dnf install -y snapd
            ;;
        arch)
            install_yay
            yay -S --noconfirm snapd
            ;;
        suse)
            sudo zypper install -y snapd
            ;;
        alpine)
            print_warn "snapd not available on Alpine. Skipping."
            return 1
            ;;
        *)
            print_warn "Unsupported distribution for snapd. Skipping."
            return 1
            ;;
    esac

    sudo systemctl enable --now snapd.socket

    print_info "Waiting for snapd to be ready..."
    local max_attempts=30
    local attempt=0
    while ! snap version &>/dev/null; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            print_error "snapd failed to start after $max_attempts attempts."
            return 1
        fi
        sleep 1
    done
    print_info "snapd is ready."
}

# ==============================
# Install Bitwarden CLI (bw) via snap
# ==============================
install_bw_cli() {
    if command -v bw &>/dev/null; then
        print_info "Bitwarden CLI already installed."
        return
    fi

    if ! command -v snap &>/dev/null; then
        install_snapd || return 1
    fi

    print_info "Installing Bitwarden CLI (bw) via snap..."
    sudo snap install bw --classic

    print_info "Waiting for bw command to become available..."
    local max_attempts=30
    local attempt=0
    while ! command -v bw &>/dev/null; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            print_warn "bw installed but not found in PATH after $max_attempts seconds."
            print_warn "You may need to log out and back in, or add /snap/bin to your PATH."
            return 0
        fi
        sleep 1
    done
    print_info "Bitwarden CLI installed successfully."
}

# ==============================
# Install s-bit-agent (SSH agent for Bitwarden personal)
#===============================
install_sbit_agent() {
    if command -v s-bit-agent &>/dev/null; then
        print_info "s-bit-agent already installed."
    else
        print_info "Installing s-bit-agent..."
        # Ensure npm
        if ! command -v npm &>/dev/null; then
            print_info "npm not found. Installing Node.js and npm..."
            case "$DISTRO_FAMILY" in
                debian) sudo apt install -y nodejs npm ;;
                redhat) sudo dnf install -y nodejs npm ;;
                arch)
                    if command -v yay &>/dev/null; then
                        yay -S --noconfirm nodejs npm
                    else
                        sudo pacman -S --noconfirm nodejs npm
                    fi
                    ;;
                suse)   sudo zypper install -y nodejs npm ;;
                alpine) sudo apk add nodejs npm ;;
                *) print_error "Cannot install npm"; return 1 ;;
            esac
        fi
        sudo npm install -g s-bit-agent
    fi

    local agent_path
    agent_path="$(which s-bit-agent)"
    mkdir -p "$HOME/.ssh" "$HOME/.config/systemd/user"

    cat > "$HOME/.config/systemd/user/s-bit-agent.service" <<EOF
[Unit]
Description=s-bit-agent (Bitwarden SSH agent)
After=network.target

[Service]
Type=simple
ExecStart=$agent_path daemon
Restart=on-failure
Environment="PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin"

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable s-bit-agent
    systemctl --user start s-bit-agent

    sleep 2
    if systemctl --user is-active s-bit-agent &>/dev/null; then
        print_info "s-bit-agent service started successfully."
    else
        print_warn "s-bit-agent service failed to start. Check logs: journalctl --user -u s-bit-agent"
    fi

    print_warn "IMPORTANT: Add the following line to your ~/.zshrc (or to your dotfiles .zshrc and re-stow):"
    echo '  export SSH_AUTH_SOCK="$HOME/.ssh/s-bit-agent.sock"'
    echo ""
    print_info "s-bit-agent installed and configured."
    print_info "Next steps:"
    echo "  1. Log in to Bitwarden CLI: bw login"
    echo "  2. Unlock your vault: bw unlock (export the session key)"
    echo "  3. The agent will automatically use your SSH keys from Bitwarden."
    echo "  4. Test with: ssh-add -l"
}

# ==============================
# TPM setup
#===============================
setup_tpm() {
    local tpm_path="$HOME/.tmux/plugins/tpm"
    if [[ ! -d "$tpm_path" ]]; then
        print_info "Cloning TPM..."
        git clone https://github.com/tmux-plugins/tpm "$tpm_path"
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
            chsh -s "$zsh_path"
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
    echo -n "Install Bitwarden CLI and s-bit-agent for SSH key management? (Y/n) "
    read -r install_bitwarden
    if [[ ! "$install_bitwarden" =~ ^[Nn]$ ]]; then
        install_bw_cli
        install_sbit_agent
    else
        print_info "Skipping Bitwarden SSH agent setup."
    fi

    setup_tpm
    set_default_shell

    print_info "Installation complete!"
    if [[ ! "$install_bitwarden" =~ ^[Nn]$ ]]; then
        print_info "Reminder: Add the SSH_AUTH_SOCK line to your .zshrc (as shown above)."
        print_info "Then run 'bw login' and 'bw unlock' to start using s-bit-agent."
    else
        print_info "You can manually install Bitwarden later if needed."
    fi
}

main