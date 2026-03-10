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

# Run a command silently, showing a status message
# Usage: run_silent "description" command [args...]
run_silent() {
    local desc="$1"
    shift
    echo -n "➜ $desc... " >&3
    if "$@" &>> "$LOG_FILE"; then
        echo -e "\033[0;32mOK\033[0m" >&3
        return 0
    else
        local exit_code=$?
        echo -e "\033[0;31mFAILED\033[0m" >&3
        echo "Error running: $*" >> "$LOG_FILE"
        echo "Exit code: $exit_code" >> "$LOG_FILE"
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
            if command -v cargo &>/dev/null; then
                run_silent "Installing yazi via cargo" cargo install --locked yazi-fm
            else
                print_warn "Cargo not available. Cannot install yazi."
            fi
            ;;
    esac
}

# ==============================
# Install Node.js and npm
# ==============================
install_nodejs_npm() {
    if command -v node &>/dev/null && command -v npm &>/dev/null; then
        print_info "Node.js and npm already installed."
        return
    fi

    print_info "Installing Node.js and npm..."
    case "$DISTRO_FAMILY" in
        debian)
            run_silent "Adding NodeSource repository" curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            run_silent "Installing Node.js" sudo apt install -y nodejs
            ;;
        redhat)
            run_silent "Adding NodeSource repository" curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo -E bash -
            run_silent "Installing Node.js" sudo dnf install -y nodejs
            ;;
        arch)
            run_silent "Installing Node.js and npm" sudo pacman -S --noconfirm nodejs npm
            ;;
        suse)
            run_silent "Installing Node.js and npm" sudo zypper install -y nodejs npm
            ;;
        alpine)
            run_silent "Installing Node.js and npm" sudo apk add nodejs npm
            ;;
        *)
            print_error "Cannot install Node.js automatically on this distro."
            exit 1
            ;;
    esac
}

# ==============================
# Install and configure s-bit-agent (Bitwarden CLI SSH agent)
# ==============================
setup_bitwarden_agent() {
    print_info "Setting up Bitwarden with s-bit-agent..."

    install_nodejs_npm

    if ! command -v bw &>/dev/null; then
        run_silent "Installing Bitwarden CLI" sudo npm install -g @bitwarden/cli
    else
        print_info "Bitwarden CLI already installed."
    fi

    if ! command -v s-bit-agent &>/dev/null; then
        run_silent "Installing s-bit-agent" sudo npm install -g s-bit-agent
    else
        print_info "s-bit-agent already installed."
    fi

    local sock_line='export SSH_AUTH_SOCK="$HOME/.ssh/s-bit-agent.sock"'
    if ! grep -q "s-bit-agent.sock" "$HOME/.zshrc" 2>/dev/null; then
        echo "" >> "$HOME/.zshrc"
        echo "# s-bit-agent SSH agent socket" >> "$HOME/.zshrc"
        echo "$sock_line" >> "$HOME/.zshrc"
        print_info "Added SSH_AUTH_SOCK export to ~/.zshrc"
    else
        print_info "SSH_AUTH_SOCK already configured in ~/.zshrc"
    fi

    if command -v systemctl &>/dev/null && systemctl --user list-units &>/dev/null 2>&1; then
        local service_dir="$HOME/.config/systemd/user"
        local service_file="$service_dir/s-bit-agent.service"
        mkdir -p "$service_dir"

        local agent_path
        agent_path=$(command -v s-bit-agent)

        cat > "$service_file" <<EOF
[Unit]
Description=s-bit-agent daemon for Bitwarden SSH agent
After=network.target

[Service]
Type=simple
ExecStart=$agent_path daemon
Restart=on-failure
Environment="PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.npm-global/bin"

[Install]
WantedBy=default.target
EOF

        run_silent "Reloading systemd" systemctl --user daemon-reload
        run_silent "Enabling s-bit-agent service" systemctl --user enable --now s-bit-agent.service
    else
        print_warn "systemd user services not available. You'll need to start s-bit-agent manually:"
        echo "  s-bit-agent daemon &"
        echo "Add this to your .zshrc or startup script to run automatically."
    fi

    echo "Do you want to configure your Bitwarden account now?"
    echo "This will allow you to log in and unlock your vault so the SSH agent (s-bit-agent) can access your keys."
    echo ""
    echo -n "Proceed with login? (Y/n) "
    read -r login_choice
    if [[ -z "$login_choice" || "$login_choice" =~ ^[Yy]$ ]]; then
        echo ""
        echo -n "Do you use a self-hosted Bitwarden server? (y/N) "
        read -r self_hosted

        if [[ "$self_hosted" =~ ^[Yy]$ ]]; then
            echo -n "Enter your server URL (e.g., https://bitwarden.example.com): "
            read -r server_url
            if [[ -n "$server_url" ]]; then
                print_info "Configuring server..."
                run_interactive s-bit-agent -- bw config server "$server_url"
            else
                print_warn "No URL provided. Skipping server configuration."
            fi
        fi

        print_info "Logging in to Bitwarden (follow the prompts)..."
        run_interactive s-bit-agent -- bw login

        print_info "Login completed. You may want to unlock your vault now to test:"
        echo -n "Unlock vault now? (Y/n) "
        read -r unlock_choice
        if [[ -z "$unlock_choice" || "$unlock_choice" =~ ^[Yy]$ ]]; then
            run_interactive s-bit-agent -- bw unlock
        fi

        echo ""
        print_info "Checking s-bit-agent daemon status:"
        run_interactive s-bit-agent status || true

        echo ""
        print_info "Bitwarden setup finished. Your SSH agent is ready to use."
        echo "You can now test it with: ssh-add -l"
    else
        print_info "Skipping login. You can do it later manually:"
        echo "  s-bit-agent -- bw login"
        echo "  s-bit-agent -- bw unlock"
    fi

    print_info "Bitwarden agent setup completed."
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
    echo "Do you want to use Bitwarden as your SSH agent (via s-bit-agent)?"
    echo -n "This will install Node.js, Bitwarden CLI, and s-bit-agent. (Y/n) "
    read -r use_bitwarden
    if [[ -z "$use_bitwarden" || "$use_bitwarden" =~ ^[Yy]$ ]]; then
        setup_bitwarden_agent
    else
        print_info "Skipping Bitwarden SSH agent setup."
    fi

    setup_tpm
    set_default_shell

    print_info "Installation complete!"
    echo "Detailed log saved to: $LOG_FILE"
}

main