#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Configuration
# ==============================
REQUIRED_COMMANDS=(
    zsh tmux nvim bat fzf zoxide lsd git curl wget xdg-open alacritty
    lazygit yazi
)

# ==============================
# Helper functions
#===============================
print_info() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

print_warn() {
    echo -e "\033[0;33m[WARN]\033[0m $1"
}

print_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
}

# ==============================
# Distribution detection
# ==============================
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION_ID="${VERSION_ID:-}"
        OS_LIKE="${ID_LIKE:-}"
    else
        print_error "Cannot detect Linux distribution."
        exit 1
    fi

    case "$OS_ID" in
        debian|ubuntu|linuxmint|pop|elementary|zorin)
            DISTRO_FAMILY="debian"
            PKG_MANAGER="apt"
            INSTALL_CMD="sudo apt update && sudo apt install -y"
            ;;
        fedora|rhel|centos|rocky|alma)
            DISTRO_FAMILY="redhat"
            PKG_MANAGER="dnf"
            INSTALL_CMD="sudo dnf install -y"
            ;;
        arch|manjaro|endeavouros|garuda)
            DISTRO_FAMILY="arch"
            PKG_MANAGER="pacman"
            INSTALL_CMD="sudo pacman -S --noconfirm"
            ;;
        opensuse*|suse)
            DISTRO_FAMILY="suse"
            PKG_MANAGER="zypper"
            INSTALL_CMD="sudo zypper install -y"
            ;;
        alpine)
            DISTRO_FAMILY="alpine"
            PKG_MANAGER="apk"
            INSTALL_CMD="sudo apk add"
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
# ==============================
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
        redhat)
            sudo dnf install -y "${packages[@]}"
            ;;
        arch)
            sudo pacman -S --noconfirm "${packages[@]}"
            ;;
        suse)
            sudo zypper install -y "${packages[@]}"
            ;;
        alpine)
            sudo apk add "${packages[@]}"
            ;;
        *)
            print_error "Unsupported package manager for family: $DISTRO_FAMILY"
            exit 1
            ;;
    esac
}

# ==============================
# Install yay (AUR helper) for Arch-based systems
# ==============================
install_yay() {
    if command -v yay &>/dev/null; then
        print_info "yay already installed."
        return
    fi

    print_info "Installing yay from AUR..."
    if [[ ! -d "/tmp/yay" ]]; then
        git clone https://aur.archlinux.org/yay.git /tmp/yay
    fi
    (cd /tmp/yay && makepkg -si --noconfirm)
    rm -rf /tmp/yay
    print_info "yay installed successfully."
}

# ==============================
# Install lazygit (if not available)
# ==============================
install_lazygit() {
    if command -v lazygit &>/dev/null; then
        print_info "lazygit already installed."
        return
    fi

    print_info "Installing lazygit..."
    case "$DISTRO_FAMILY" in
        debian|ubuntu)
            LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": *"v\K[^"]*')
            if [[ -z "$LAZYGIT_VERSION" ]]; then
                print_warn "Could not fetch latest lazygit version. Skipping."
                return
            fi
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
                print_warn "No native lazygit package and cargo missing. Skipping."
            fi
            ;;
    esac
}

# ==============================
# Install yazi (if not available)
# ==============================
install_yazi() {
    if command -v yazi &>/dev/null; then
        print_info "yazi already installed."
        return
    fi

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
# Install snapd and Bitwarden CLI (bw)
# ==============================
install_snap_and_bw() {
    if command -v snap &>/dev/null; then
        print_info "snap already installed."
    else
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
                print_warn "snapd not available on Alpine. Skipping Bitwarden installation."
                return
                ;;
            *)
                print_warn "Unsupported distribution for snapd. Skipping Bitwarden."
                return
                ;;
        esac

        sudo systemctl enable --now snapd.socket

        print_info "Waiting for snapd to be ready..."
        local max_attempts=30
        local attempt=0
        while ! snap version &>/dev/null; do
            attempt=$((attempt+1))
            if [[ $attempt -ge $max_attempts ]]; then
                print_error "snapd did not become ready in time."
                return 1
            fi
            sleep 2
        done
        print_info "snapd is ready."
    fi

    # Install Bitwarden CLI (bw) with classic confinement
    if ! command -v bw &>/dev/null; then
        print_info "Installing Bitwarden CLI (bw) via snap..."
        sudo snap install bw --classic
    else
        print_info "Bitwarden CLI already installed."
    fi
}

# ==============================
# Install s-bit-agent (SSH agent for Bitwarden)
# ==============================
install_sbit_agent() {
    if command -v s-bit-agent &>/dev/null; then
        print_info "s-bit-agent already installed."
    else
        print_info "Installing s-bit-agent..."
        
        # Ensure npm is available
        if ! command -v npm &>/dev/null; then
            print_info "npm not found. Installing Node.js and npm..."
            case "$DISTRO_FAMILY" in
                debian)
                    sudo apt install -y nodejs npm
                    ;;
                redhat)
                    sudo dnf install -y nodejs npm
                    ;;
                arch)
                    if command -v yay &>/dev/null; then
                        yay -S --noconfirm nodejs npm
                    else
                        sudo pacman -S --noconfirm nodejs npm
                    fi
                    ;;
                suse)
                    sudo zypper install -y nodejs npm
                    ;;
                alpine)
                    sudo apk add nodejs npm
                    ;;
                *)
                    print_error "Cannot install npm on this distribution."
                    return 1
                    ;;
            esac
        fi

        # Install globally
        sudo npm install -g s-bit-agent

        # Configure Bitwarden server (default is official)
        s-bit-agent -- bw config server https://bitwarden.com || true
    fi

    # Get the full path of s-bit-agent (after installation)
    local agent_path
    if ! agent_path="$(which s-bit-agent 2>/dev/null)"; then
        print_error "s-bit-agent not found in PATH after installation."
        return 1
    fi

    # Create necessary directories
    mkdir -p "$HOME/.ssh"
    mkdir -p "$HOME/.config/systemd/user"

    # Create systemd user service
    local service_file="$HOME/.config/systemd/user/s-bit-agent.service"
    cat > "$service_file" <<EOF
[Unit]
Description=s-bit-agent (Bitwarden SSH agent)
After=network.target

[Service]
Type=simple
ExecStart=$agent_path daemon
Restart=on-failure
Environment="PATH=/usr/local/bin:/usr/bin:/bin:$PATH"

[Install]
WantedBy=default.target
EOF

    # Reload systemd user daemon
    systemctl --user daemon-reload

    # Add environment variable to .zshrc if not already present
    if ! grep -q "SSH_AUTH_SOCK.*s-bit-agent" ~/.zshrc 2>/dev/null; then
        echo '' >> ~/.zshrc
        echo '# s-bit-agent socket for Bitwarden SSH' >> ~/.zshrc
        echo 'export SSH_AUTH_SOCK="$HOME/.ssh/s-bit-agent.sock"' >> ~/.zshrc
        print_info "Added SSH_AUTH_SOCK to ~/.zshrc"
    fi

    print_info "s-bit-agent installed and systemd service created."
    print_info "To start the agent now, run: systemctl --user start s-bit-agent"
    print_info "To enable autostart: systemctl --user enable s-bit-agent"
    print_info "Note: You must log in to Bitwarden CLI first: bw login"
}

# ==============================
# TPM setup
# ==============================
setup_tpm() {
    local tpm_path="$HOME/.tmux/plugins/tpm"
    if [[ ! -d "$tpm_path" ]]; then
        print_info "Cloning TPM..."
        git clone https://github.com/tmux-plugins/tpm "$tpm_path"
    else
        print_info "TPM already present."
    fi

    if [[ ! -f "$tpm_path/tpm" ]]; then
        print_error "TPM installation incomplete."
        exit 1
    fi
}

# ==============================
# Set default shell to zsh (optional)
# ==============================
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
# Check optional tools
# ==============================
check_optional() {
    if command -v bw &>/dev/null; then
        print_info "Bitwarden CLI is installed."
    else
        print_warn "Bitwarden CLI not found."
    fi

    if command -v s-bit-agent &>/dev/null; then
        print_info "s-bit-agent is installed."
        if [[ -S "$HOME/.ssh/s-bit-agent.sock" ]]; then
            print_info "s-bit-agent socket found at ~/.ssh/s-bit-agent.sock"
        else
            print_warn "s-bit-agent socket not found. Ensure the service is running: systemctl --user start s-bit-agent"
        fi
    else
        print_warn "s-bit-agent not installed. SSH agent will not be available."
    fi

    if [[ ! -f "$HOME/.config/alacritty/dracula.toml" ]]; then
        print_warn "Alacritty Dracula theme not found. Ensure your dotfiles include it."
    fi
}

# ==============================
# Main
# ==============================
main() {
    detect_distro

    local common_packages=(
        zsh tmux neovim fzf zoxide lsd git curl wget
    )

    case "$DISTRO_FAMILY" in
        debian)
            common_packages+=(openssh-client bat xdg-utils alacritty build-essential cargo unzip)
            ;;
        redhat)
            common_packages+=(openssh-clients bat xdg-utils alacritty gcc make cargo unzip)
            ;;
        arch)
            common_packages+=(openssh bat xdg-utils alacritty base-devel rust unzip)
            ;;
        suse)
            common_packages+=(openssh bat xdg-utils alacritty gcc make cargo unzip)
            ;;
        alpine)
            common_packages+=(openssh bat xdg-utils alacritty build-base cargo unzip)
            ;;
    esac

    install_packages "${common_packages[@]}"

    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
        install_yay
    fi

    install_lazygit
    install_yazi

    install_snap_and_bw
    install_sbit_agent

    setup_tpm
    set_default_shell
    check_optional

    print_info "Installation complete!"
    print_info "Important next steps:"
    echo "  1. Log out and back in (or restart) to ensure shell and group changes take effect."
    echo "  2. If you changed your default shell to zsh, start a new session."
    echo "  3. Log in to Bitwarden CLI: bw login"
    echo "  4. Start s-bit-agent: systemctl --user start s-bit-agent"
    echo "  5. Enable it to start automatically: systemctl --user enable s-bit-agent"
    echo "  6. Your SSH_AUTH_SOCK is already set in ~/.zshrc; after starting the agent, SSH will use Bitwarden."
}

main