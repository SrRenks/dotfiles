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
# Install lazygit
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
            sudo pacman -S --noconfirm lazygit
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
# Install yazi
# ==============================
install_yazi() {
    if command -v yazi &>/dev/null; then
        print_info "yazi already installed."
        return
    fi

    print_info "Installing yazi..."
    case "$DISTRO_FAMILY" in
        arch)
            sudo pacman -S --noconfirm yazi
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
# Install snap and Bitwarden
# ==============================
install_snap_and_bitwarden() {
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
                if [[ ! -d "/tmp/snapd" ]]; then
                    git clone https://aur.archlinux.org/snapd.git /tmp/snapd
                fi
                (cd /tmp/snapd && makepkg -si --noconfirm)
                rm -rf /tmp/snapd
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
        sudo ln -sf /var/lib/snapd/snap /snap

        print_info "Waiting for snapd to initialize..."
        sleep 5
    fi

    # Install Bitwarden if not present
    if ! snap list 2>/dev/null | grep -q bitwarden; then
        print_info "Installing Bitwarden via snap..."
        sudo snap install bitwarden
        sudo snap connect bitwarden:password-manager-service
    else
        print_info "Bitwarden already installed."
    fi
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
            print_info "Default shell changed to zsh. Log out and back in."
        fi
    else
        print_info "zsh is already the default shell."
    fi
}

# ==============================
# Check optional tools
# ==============================
check_optional() {
    if ! command -v bw &>/dev/null; then
        print_warn "Bitwarden CLI not found. SSH agent integration may be missing."
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

    install_lazygit
    install_yazi

    install_snap_and_bitwarden

    setup_tpm
    set_default_shell
    check_optional

    print_info "Installation complete! Run 'source ~/.zshrc' or restart your terminal."
}

main