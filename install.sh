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

    case "$DISTRO_FAMILY" in
        debian|ubuntu)
            run_silent "Installing kbd and console-setup" sudo apt install -y kbd console-setup
            ;;
    esac

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
                    echo "keyboard-configuration keyboard-configuration/layoutcode string us" | sudo debconf-set-selections
                    echo "keyboard-configuration keyboard-configuration/variantcode string intl" | sudo debconf-set-selections
                    echo "keyboard-configuration keyboard-configuration/xkb-keymap select us" | sudo debconf-set-selections
                    run_silent "Reconfiguring keyboard-configuration" sudo dpkg-reconfigure -f noninteractive keyboard-configuration
                    run_silent "Applying setupcon" sudo setupcon --force
                    print_info "Keyboard configuration updated. It should persist across reboots."
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
        debian|ubuntu)
            if sudo apt install -y yazi &>/dev/null; then
                print_info "yazi installed via apt."
                return 0
            fi
            if command -v curl &>/dev/null && command -v tar &>/dev/null; then
                print_info "Attempting binary installation from GitHub..."
                local version
                version=$(curl -s https://api.github.com/repos/sxyazi/yazi/releases/latest | grep -Po '"tag_name": *"v\K[^"]*' || echo "26.1.22")
                local url="https://github.com/sxyazi/yazi/releases/download/v${version}/yazi-x86_64-unknown-linux-musl.tar.gz"
                local tmp_dir="/tmp/yazi-install-$$"
                mkdir -p "$tmp_dir"
                if curl -L -o "$tmp_dir/yazi.tar.gz" "$url" && [[ $(stat -c%s "$tmp_dir/yazi.tar.gz" 2>/dev/null || echo 0) -gt 1000000 ]]; then
                    if tar xzf "$tmp_dir/yazi.tar.gz" -C "$tmp_dir"; then
                        local binary_path
                        binary_path=$(find "$tmp_dir" -name yazi -type f | head -n1)
                        if [[ -n "$binary_path" ]]; then
                            sudo install -Dm755 "$binary_path" /usr/local/bin/yazi
                            rm -rf "$tmp_dir"
                            print_info "yazi installed successfully from binary."
                            return 0
                        fi
                    fi
                else
                    print_warn "tar.gz download failed, trying .zip..."
                    local url_zip="https://github.com/sxyazi/yazi/releases/download/v${version}/yazi-x86_64-unknown-linux-musl.zip"
                    if curl -L -o "$tmp_dir/yazi.zip" "$url_zip" && [[ $(stat -c%s "$tmp_dir/yazi.zip" 2>/dev/null || echo 0) -gt 1000000 ]]; then
                        if unzip -q "$tmp_dir/yazi.zip" -d "$tmp_dir"; then
                            binary_path=$(find "$tmp_dir" -name yazi -type f | head -n1)
                            if [[ -n "$binary_path" ]]; then
                                sudo install -Dm755 "$binary_path" /usr/local/bin/yazi
                                rm -rf "$tmp_dir"
                                print_info "yazi installed successfully from binary (zip)."
                                return 0
                            fi
                        fi
                    fi
                fi
                print_warn "Binary installation failed (invalid or too small)."
                rm -rf "$tmp_dir"
            fi
            if command -v cargo &>/dev/null; then
                local cargo_version
                cargo_version=$(cargo --version | awk '{print $2}')
                local min_version="1.70.0"
                if [[ "$(printf '%s\n' "$cargo_version" "$min_version" | sort -V | head -n1)" == "$min_version" ]]; then
                    print_info "Attempting installation via cargo (this may take a while)..."
                    if run_silent "Installing yazi via cargo" cargo install --locked yazi-fm; then
                        print_info "yazi installed successfully via cargo."
                        return 0
                    else
                        print_error "cargo installation failed."
                        return 1
                    fi
                else
                    print_error "Cargo version $cargo_version is too old to build yazi (needs >= 1.70)."
                    echo "Please install Rust via rustup:"
                    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
                    return 1
                fi
            else
                print_error "No suitable installation method found for yazi."
                return 1
            fi
            ;;
        *)
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
        if rbw --version &>/dev/null; then
            return 0
        else
            print_warn "Existing rbw binary is broken. Removing and reinstalling..."
            rm -f "$(command -v rbw)"
        fi
    fi

    print_info "Installing rbw (Bitwarden CLI with SSH agent)..."

    case "$DISTRO_FAMILY" in
        debian|ubuntu)
            run_silent "Installing pinentry-tty" sudo apt install -y pinentry-tty
            ;;
        redhat)
            run_silent "Installing pinentry" sudo dnf install -y pinentry
            ;;
        arch)
            run_silent "Installing pinentry" sudo pacman -S --noconfirm pinentry
            ;;
        suse)
            run_silent "Installing pinentry" sudo zypper install -y pinentry
            ;;
        alpine)
            run_silent "Installing pinentry" sudo apk add pinentry
            ;;
        *)
            print_warn "Please ensure pinentry-tty is installed manually."
            ;;
    esac

    if ! command -v pinentry-tty &>/dev/null; then
        print_error "pinentry-tty not found after installation. Aborting."
        return 1
    fi

    case "$DISTRO_FAMILY" in
        arch)
            run_silent "Installing rbw via pacman" sudo pacman -S --noconfirm rbw
            ;;
        debian|ubuntu)
            if command -v snap &>/dev/null; then
                if run_silent "Installing rbw via snap" sudo snap install rbw; then
                    print_info "rbw installed via snap."
                    return 0
                else
                    print_warn "Snap installation failed (rbw may not be available in snap), trying apt..."
                fi
            fi

            if sudo apt install -y rbw &>/dev/null; then
                print_info "rbw installed via apt."
                return 0
            else
                print_warn "rbw not found in apt repositories. Trying cargo..."
            fi

            if command -v cargo &>/dev/null; then
                local cargo_version
                cargo_version=$(cargo --version | awk '{print $2}')
                local min_version="1.70.0"
                if [[ "$(printf '%s\n' "$cargo_version" "$min_version" | sort -V | head -n1)" == "$min_version" ]]; then
                    print_info "Installing rbw via cargo (this may take a while)..."
                    if run_silent "Installing rbw via cargo" cargo install --force --locked rbw; then
                        print_info "rbw installed successfully via cargo."
                        return 0
                    else
                        print_error "cargo installation failed."
                        return 1
                    fi
                else
                    print_error "Cargo version $cargo_version is too old to install rbw (needs >= 1.70)."
                    echo ""
                    echo "You can install rustup to get a modern Rust toolchain:"
                    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
                    echo "After that, restart your shell and run this script again."
                    echo -n "Install rustup now? (y/N) "
                    read -r install_rustup
                    if [[ "$install_rustup" =~ ^[Yy]$ ]]; then
                        print_info "Installing rustup..."
                        if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
                            print_info "rustup installed. Please restart your shell and re-run the script."
                            exit 0
                        else
                            print_error "rustup installation failed."
                            return 1
                        fi
                    else
                        echo "Skipping rustup. You can manually install rbw later with:"
                        echo "  cargo install --locked rbw"
                        return 1
                    fi
                fi
            else
                print_error "No suitable installation method found for rbw."
                return 1
            fi
            ;;
        redhat)
            if sudo dnf install -y rbw &>/dev/null; then
                print_info "rbw installed via dnf."
                return 0
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
            if command -v cargo &>/dev/null; then
                run_silent "Installing rbw via cargo" cargo install --locked rbw
            else
                print_error "Cargo not available. Cannot install rbw."
                return 1
            fi
            ;;
        *)
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

    mkdir -p "$HOME/.config/rbw"
    touch "$HOME/.config/rbw/config.toml"

    check_rbw() {
        command -v rbw &>/dev/null && rbw --version &>/dev/null
    }

    if ! check_rbw; then
        if command -v rbw &>/dev/null; then
            print_warn "Existing rbw binary seems broken. Reinstalling..."
            rm -f "$(command -v rbw)" 2>/dev/null || true
        fi
        install_rbw || return 1
        if ! check_rbw; then
            print_error "rbw installation failed or binary still not working."
            echo "Please try installing manually:"
            echo "  cargo install --force --locked rbw"
            echo "or via snap: sudo snap install rbw"
            return 1
        fi
    fi

    local rbw_path
    rbw_path=$(command -v rbw)

    if ! command -v pinentry-tty &>/dev/null; then
        print_error "pinentry-tty not found in PATH. Please ensure it's installed."
        return 1
    fi

    run_silent "Setting pinentry to pinentry-tty" "$rbw_path" config set pinentry pinentry-tty

    echo ""
    echo "rbw requires your Bitwarden email address."
    echo -n "Enter your email: "
    read -r email
    if [[ -n "$email" ]]; then
        run_silent "Configuring email" "$rbw_path" config set email "$email"
    else
        print_error "Email is required. Aborting."
        return 1
    fi

    echo "Bitwarden server URL (press Enter to use official server):"
    echo -n "URL [https://api.bitwarden.com]: "
    read -r server_url
    if [[ -n "$server_url" ]]; then
        run_silent "Configuring base_url" "$rbw_path" config set base_url "$server_url"
        print_info "Using custom server: $server_url"
    else
        print_info "Using official Bitwarden server."
    fi

    print_info "Logging in to Bitwarden (follow the prompts)..."
    if ! run_interactive "$rbw_path" login; then
        print_warn "Login failed. This may happen if you have 2FA methods not supported by rbw (like WebAuthn/FIDO2)."
        echo ""
        echo "For official Bitwarden server (bitwarden.com), you need to register the device using your API key first."
        echo "The 'rbw register' command will now be executed – it will ask for your client_id and client_secret."
        echo "You can find these at: https://vault.bitwarden.com → Settings → Security → API Key"
        echo ""
        echo -n "Proceed with device registration? (Y/n) "
        read -r register_choice
        if [[ -z "$register_choice" || "$register_choice" =~ ^[Yy]$ ]]; then
            print_info "Running rbw register (follow the prompts)..."
            if run_interactive "$rbw_path" register; then
                print_info "Device registered successfully. Now logging in normally..."
                run_interactive "$rbw_path" login
            else
                print_error "Registration failed. Please check your API key and try again later manually with: rbw register"
                return 1
            fi
        else
            print_error "Login failed and registration skipped. You can try again later with: rbw register"
            return 1
        fi
    fi

    run_silent "Syncing vault" "$rbw_path" sync

    local use_systemd=false
    if command -v systemctl &>/dev/null && systemctl --user list-units &>/dev/null 2>&1; then
        use_systemd=true
    fi

    if $use_systemd; then
        print_info "Setting up systemd user service for rbw-agent..."

        local service_dir="$HOME/.config/systemd/user"
        local service_file="$service_dir/rbw.service"
        mkdir -p "$service_dir"

        local agent_path
        agent_path=$(command -v rbw-agent)

        cat > "$service_file" <<EOF
[Unit]
Description=rbw agent daemon
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=$agent_path
Restart=on-failure

[Install]
WantedBy=graphical-session.target
EOF

        run_silent "Reloading systemd user daemon" systemctl --user daemon-reload
        run_silent "Enabling rbw service" systemctl --user enable rbw.service
        run_silent "Starting rbw service" systemctl --user start rbw.service

        print_info "rbw-agent is now managed by systemd and will start automatically on login."
    else
        print_warn "systemd user services not available. Starting rbw-agent manually for this session."
        if ! pgrep -x "rbw-agent" > /dev/null; then
            run_silent "Starting rbw-agent" rbw-agent --daemon
        fi
    fi

    echo ""
    echo -n "Unlock your vault now? (Y/n) "
    read -r unlock_choice
    if [[ -z "$unlock_choice" || "$unlock_choice" =~ ^[Yy]$ ]]; then
        run_interactive "$rbw_path" unlock
    fi

    echo ""
    print_info "rbw setup finished. Your SSH agent is running in this session."
    echo ""
    echo "To make the SSH agent socket available in future sessions, add the following line to your ~/.zshrc:"
    echo "  export SSH_AUTH_SOCK=\"\$XDG_RUNTIME_DIR/rbw/ssh-agent-socket\""
    echo ""

    if $use_systemd; then
        echo "The agent itself is managed by systemd (service 'rbw.service')."
        echo "You can check its status with: systemctl --user status rbw.service"
    else
        echo "To start the agent automatically in future sessions, also add these lines to your ~/.zshrc:"
        echo "  if ! pgrep -x \"rbw-agent\" > /dev/null; then"
        echo "      rbw-agent --daemon"
        echo "  fi"
    fi

    echo ""
    echo "You can test the agent with: ssh-add -l"
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
        debian) common_packages+=(openssh-client bat xdg-utils alacritty build-essential cargo unzip jq snapd) ;;
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