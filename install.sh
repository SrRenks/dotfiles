#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Logging and silent execution
# ==============================
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' EXIT

print_info() { echo -e "\033[0;32m[INFO]\033[0m $1" >&3; }
print_warn() { echo -e "\033[0;33m[WARN]\033[0m $1" >&3; }
print_error() { echo -e "\033[0;31m[ERROR]\033[0m $1" >&3; }

# ==============================
# Spinner for long-running commands
# ==============================
run_with_spinner() {
    local desc="$1"
    shift
    local log_file
    log_file=$(mktemp)
    local pid

    echo -n "$desc... " >&3

    "$@" &> "$log_file" &
    pid=$!

    local spin='-\|/'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\b${spin:$i:1}" >&3
        sleep 0.1
    done
    printf "\b" >&3

    wait "$pid"
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo -e "\033[0;32mOK\033[0m" >&3
        rm -f "$log_file"
        return 0
    else
        echo -e "\033[0;31mFAILED\033[0m" >&3
        echo "Error running: $*" >&3
        echo "Exit code: $exit_code" >&3
        echo "--- Output ---" >&3
        cat "$log_file" >&3
        echo "--------------" >&3
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
    lazygit yazi rbw bw
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
            run_with_spinner "Installing kbd and console-setup" sudo apt install -y kbd console-setup
            ;;
    esac

    case "$DISTRO_FAMILY" in
        arch|debian|ubuntu|redhat|suse|alpine)
            print_info "Setting persistent keyboard layout for $DISTRO_FAMILY..."
            case "$DISTRO_FAMILY" in
                arch)
                    run_with_spinner "Setting KEYMAP in /etc/vconsole.conf" \
                        sudo bash -c "echo 'KEYMAP=us-intl' > /etc/vconsole.conf"
                    print_info "Persistent configuration set in /etc/vconsole.conf. Reboot to take full effect."
                    ;;
                debian|ubuntu)
                    echo "keyboard-configuration keyboard-configuration/layoutcode string us" | sudo debconf-set-selections
                    echo "keyboard-configuration keyboard-configuration/variantcode string intl" | sudo debconf-set-selections
                    echo "keyboard-configuration keyboard-configuration/xkb-keymap select us" | sudo debconf-set-selections
                    run_with_spinner "Reconfiguring keyboard-configuration" sudo dpkg-reconfigure -f noninteractive keyboard-configuration
                    run_with_spinner "Applying setupcon" sudo setupcon --force
                    print_info "Keyboard configuration updated. It should persist across reboots."
                    ;;
                redhat)
                    if command -v localectl &>/dev/null; then
                        run_with_spinner "Setting keymap via localectl" sudo localectl set-keymap us-intl
                    else
                        run_with_spinner "Setting KEYMAP in /etc/vconsole.conf" \
                            sudo bash -c "echo 'KEYMAP=us-intl' > /etc/vconsole.conf"
                    fi
                    ;;
                suse)
                    if command -v localectl &>/dev/null; then
                        run_with_spinner "Setting keymap via localectl" sudo localectl set-keymap us-intl
                    else
                        print_warn "Please use YaST to set keyboard to 'US International (with dead keys)' for persistence."
                    fi
                    ;;
                alpine)
                    run_with_spinner "Setting KEYMAP in /etc/conf.d/keymaps" \
                        sudo sed -i 's/^keymap=.*/keymap="us-intl"/' /etc/conf.d/keymaps
                    ;;
            esac
            ;;
        *)
            print_warn "Unsupported distribution for persistent keyboard configuration."
            print_warn "You may need to manually add 'loadkeys us-intl' to your startup scripts (e.g., ~/.zshrc, /etc/rc.local)."
            ;;
    esac

    print_info "Keyboard configuration for TTY completed."
}

# ==============================
# Package installation (common tools)
#===============================
install_packages() {
    local packages=("$@")
    print_info "Installing system packages: ${packages[*]}"

    case "$DISTRO_FAMILY" in
        debian)
            run_with_spinner "Updating package lists" sudo apt update
            run_with_spinner "Installing packages" sudo apt install -y "${packages[@]}"
            if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
                run_with_spinner "Creating bat symlink" sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
            fi
            ;;
        redhat)
            run_with_spinner "Installing packages" sudo dnf install -y "${packages[@]}"
            ;;
        arch)
            run_with_spinner "Installing packages" sudo pacman -S --noconfirm "${packages[@]}"
            ;;
        suse)
            run_with_spinner "Installing packages" sudo zypper install -y "${packages[@]}"
            ;;
        alpine)
            run_with_spinner "Installing packages" sudo apk add "${packages[@]}"
            ;;
        *) print_error "Unsupported package manager"; exit 1 ;;
    esac
}

# ==============================
# Install Rust via rustup (if needed)
#===============================
ensure_rust() {
    if command -v rustc &>/dev/null && command -v cargo &>/dev/null; then
        print_info "Rust already installed."
        return 0
    fi
    print_info "Rust not found. Installing rustup (will be asked for confirmation)..."
    if run_interactive bash -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"; then
        source "$HOME/.cargo/env"
        print_info "Rust installed successfully."
    else
        print_error "Rust installation failed."
        return 1
    fi
}

# ==============================
# Generic GitHub binary installer
#===============================
_install_github_binary() {
    local repo="$1"          # e.g. "jesseduffield/lazygit"
    local binary_name="$2"    # e.g. "lazygit"
    local version_pattern="$3" # pattern to extract version (usually "v$version")
    local asset_pattern="$4"   # pattern to match asset name, e.g. "lazygit_${version}_Linux_x86_64.tar.gz"
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        armv7l)  arch="armv7" ;;
        *)       print_error "Unsupported architecture: $arch"; return 1 ;;
    esac

    print_info "Installing $binary_name from GitHub releases..."

    local version
    version=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | grep -Po '"tag_name": *"v\K[^"]*')
    if [[ -z "$version" ]]; then
        print_error "Could not fetch latest version for $repo"
        return 1
    fi

    local asset
    asset=$(echo "$asset_pattern" | sed -e "s/{version}/$version/g" -e "s/{arch}/$arch/g")
    local url="https://github.com/$repo/releases/download/v${version}/$asset"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    pushd "$tmp_dir" >/dev/null

    if ! run_with_spinner "Downloading $binary_name" curl -L -o "$binary_name" "$url"; then
        print_error "Download failed for $url"
        popd >/dev/null; rm -rf "$tmp_dir"
        return 1
    fi

    if [[ "$asset" == *.tar.gz ]]; then
        run_with_spinner "Extracting $binary_name" tar xzf "$binary_name" || { print_error "Extraction failed"; popd >/dev/null; rm -rf "$tmp_dir"; return 1; }
        if [[ ! -f "$binary_name" ]]; then
            local found
            found=$(find . -type f -name "$binary_name" | head -n1)
            if [[ -n "$found" ]]; then
                mv "$found" "$binary_name"
            else
                print_error "Binary not found in extracted files"
                popd >/dev/null; rm -rf "$tmp_dir"
                return 1
            fi
        fi
    fi

    run_with_spinner "Installing $binary_name to /usr/local/bin" sudo install -Dm755 "$binary_name" "/usr/local/bin/$binary_name"
    popd >/dev/null
    rm -rf "$tmp_dir"
    print_info "$binary_name installed successfully."
}

# ==============================
# Install lazygit
#===============================
install_lazygit() {
    if command -v lazygit &>/dev/null; then
        print_info "lazygit already installed."
        return 0
    fi
    if ! _install_github_binary \
        "jesseduffield/lazygit" \
        "lazygit" \
        "v{version}" \
        "lazygit_{version}_Linux_{arch}.tar.gz"; then
        print_warn "lazygit installation failed, but continuing."
        return 1
    fi
}

# ==============================
# Install yazi
#===============================
install_yazi() {
    if command -v yazi &>/dev/null; then
        print_info "yazi already installed."
        return 0
    fi
    if ! _install_github_binary \
        "sxyazi/yazi" \
        "yazi" \
        "v{version}" \
        "yazi-{arch}-unknown-linux-musl.zip"; then
        print_warn "yazi installation failed, but continuing."
        return 1
    fi
}

# ==============================
# Install rbw (requires Rust)
#===============================
install_rbw() {
    if command -v rbw &>/dev/null && rbw --version &>/dev/null; then
        print_info "rbw already installed."
        return 0
    fi
    print_info "Installing rbw via cargo..."
    ensure_rust || return 1
    if ! run_with_spinner "Installing rbw" cargo install --locked rbw; then
        print_warn "rbw installation failed, but continuing."
        return 1
    fi
    print_info "rbw installed."
}

# ==============================
# Install Bitwarden CLI (bw)
#===============================
install_bw() {
    if command -v bw &>/dev/null; then
        print_info "bw already installed."
        return 0
    fi
    print_info "Installing Bitwarden CLI from official binary..."

    local arch
    arch=$(uname -m)
    local arch_suffix=""
    case "$arch" in
        x86_64)
            arch_suffix=""
            ;;
        aarch64)
            arch_suffix="-arm64"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    local version
    version=$(curl -s https://api.github.com/repos/bitwarden/clients/releases | grep -Po '"tag_name": *"cli-v\K[^"]*' | head -n1)
    if [[ -z "$version" ]]; then
        print_error "Could not fetch latest version for bw"
        return 1
    fi

    local url="https://github.com/bitwarden/clients/releases/download/cli-v${version}/bw-linux${arch_suffix}-${version}.zip"
    local tmp_dir
    tmp_dir=$(mktemp -d)
    pushd "$tmp_dir" >/dev/null

    if ! run_with_spinner "Downloading bw" curl -L -o bw.zip "$url"; then
        print_error "Download failed for $url"
        popd >/dev/null; rm -rf "$tmp_dir"
        return 1
    fi

    run_with_spinner "Extracting bw" unzip -q bw.zip
    run_with_spinner "Installing bw to /usr/local/bin" sudo install -Dm755 bw "/usr/local/bin/bw"
    popd >/dev/null
    rm -rf "$tmp_dir"
    print_info "bw installed successfully."
}

# ==============================
# Install yay (Arch only)
#===============================
install_yay() {
    if [[ "$DISTRO_FAMILY" != "arch" ]]; then
        return 0
    fi
    if command -v yay &>/dev/null; then
        print_info "yay already installed."
        return
    fi
    print_info "Installing yay from AUR..."
    run_with_spinner "Cloning yay repository" git clone --depth=1 https://aur.archlinux.org/yay.git /tmp/yay
    (cd /tmp/yay && run_with_spinner "Building yay" makepkg -si --noconfirm)
    run_with_spinner "Cleaning up" rm -rf /tmp/yay
    print_info "yay installed successfully."
}

# ==============================
# Setup rbw (Bitwarden SSH agent)
# ==============================
setup_rbw() {
    print_info "Setting up rbw..."

    if ! command -v pinentry-tty &>/dev/null; then
        case "$DISTRO_FAMILY" in
            debian) run_with_spinner "Installing pinentry-tty" sudo apt install -y pinentry-tty ;;
            redhat) run_with_spinner "Installing pinentry" sudo dnf install -y pinentry ;;
            arch)   run_with_spinner "Installing pinentry" sudo pacman -S --noconfirm pinentry ;;
            suse)   run_with_spinner "Installing pinentry" sudo zypper install -y pinentry ;;
            alpine) run_with_spinner "Installing pinentry" sudo apk add pinentry ;;
            *) print_warn "Please install pinentry-tty manually." ;;
        esac
    fi

    mkdir -p "$HOME/.config/rbw"
    touch "$HOME/.config/rbw/config.toml"

    rbw config set pinentry pinentry-tty

    echo ""
    echo "rbw requires your Bitwarden email address."
    echo -n "Enter your email: "
    read -r email
    if [[ -n "$email" ]]; then
        rbw config set email "$email"
    else
        print_error "Email is required. Aborting."
        return 1
    fi

    echo "Bitwarden server URL (press Enter to use official server):"
    echo -n "URL [https://api.bitwarden.com]: "
    read -r server_url
    if [[ -n "$server_url" ]]; then
        rbw config set base_url "$server_url"
    fi

    print_info "Attempting to log in (if fails, will guide through registration)..."
    if ! rbw login; then
        print_warn "Login failed. This may require device registration with API key."
        echo "You can find your API key at: https://vault.bitwarden.com → Settings → Security → API Key"
        echo -n "Proceed with automated registration? (Y/n) "
        read -r register_choice
        if [[ -z "$register_choice" || "$register_choice" =~ ^[Yy]$ ]]; then
            if ! command -v bw &>/dev/null; then
                print_error "bw not installed; cannot retrieve API key automatically."
                echo "Please run manually: rbw register"
                return 1
            fi

            local client_id client_secret
            client_id=$(bw get username bw-api 2>/dev/null || true)
            client_secret=$(bw get password bw-api 2>/dev/null || true)
            if [[ -z "$client_id" || -z "$client_secret" ]]; then
                print_error "Could not retrieve API key from bw. Please run 'rbw register' manually."
                return 1
            fi

            if ! command -v expect &>/dev/null; then
                print_warn "expect not installed. Please run 'rbw register' manually."
                return 1
            fi

            print_info "Running rbw register with provided API key..."
            expect << EOF
set timeout 30
spawn rbw register
expect "API key client__id:"
send -- "$client_id\r"
expect "API key client__secret:"
send -- "$client_secret\r"
expect eof
catch wait result
exit [lindex \$result 3]
EOF
            if [[ $? -eq 0 ]]; then
                print_info "Registration successful. Now logging in..."
                rbw login
            else
                print_error "Registration failed. Please run manually: rbw register"
                return 1
            fi
        else
            print_error "Login failed and registration skipped. Exiting."
            return 1
        fi
    fi

    run_with_spinner "Syncing vault" rbw sync

    if command -v systemctl &>/dev/null && systemctl --user list-units &>/dev/null 2>&1; then
        print_info "Setting up systemd user service for rbw-agent..."
        local service_dir="$HOME/.config/systemd/user"
        local service_file="$service_dir/rbw.service"
        mkdir -p "$service_dir"

        cat > "$service_file" <<EOF
[Unit]
Description=rbw agent daemon
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=$(command -v rbw-agent)
Restart=on-failure

[Install]
WantedBy=graphical-session.target
EOF

        run_with_spinner "Reloading systemd" systemctl --user daemon-reload
        run_with_spinner "Enabling rbw service" systemctl --user enable rbw.service
        run_with_spinner "Starting rbw service" systemctl --user start rbw.service
        print_info "rbw-agent started via systemd."
    else
        print_warn "systemd user services not available. Starting rbw-agent manually."
        rbw-agent --daemon
    fi

    echo ""
    echo "To use the SSH agent, add to your ~/.zshrc:"
    echo "  export SSH_AUTH_SOCK=\"\$XDG_RUNTIME_DIR/rbw/ssh-agent-socket\""
    echo ""
    echo "Test with: ssh-add -l"
}

# ==============================
# TPM setup
#===============================
setup_tpm() {
    local tpm_path="$HOME/.tmux/plugins/tpm"
    if [[ ! -d "$tpm_path" ]]; then
        print_info "Cloning TPM..."
        run_with_spinner "Cloning tpm" git clone --depth=1 https://github.com/tmux-plugins/tpm "$tpm_path"
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
        echo ""
        echo "Do you want to change your default shell to zsh? (requires password)"
        echo -n "Change shell? (y/N) "
        read -r resp
        if [[ "$resp" =~ ^[Yy]$ ]]; then
            print_info "Changing default shell to zsh (you may be prompted for your password)..."
            if run_interactive chsh -s "$zsh_path"; then
                print_info "Default shell changed to zsh. Please log out and back in."
            else
                print_error "Failed to change shell. You may need to run 'chsh -s $zsh_path' manually."
            fi
        fi
    else
        print_info "zsh is already the default shell."
    fi
}

# ==============================
# Verify required commands
#===============================
verify_commands() {
    print_info "Verifying installed commands..."
    local missing=()
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_warn "Missing commands: ${missing[*]}"
    else
        print_info "All required commands are available."
    fi
}

# ==============================
# Main
#===============================
main() {
    echo "Checking sudo access (you may be asked for your password)..."
    if ! sudo -v; then
        print_error "This script requires sudo privileges."
        exit 1
    fi

    detect_distro

    local common_packages=(
        zsh tmux neovim fzf zoxide lsd git curl wget stow wl-clipboard
        openssh-client bat xdg-utils alacritty build-essential unzip jq
        expect
    )

    case "$DISTRO_FAMILY" in
        debian) common_packages+=(cargo) ;;
        redhat) common_packages+=(cargo) ;;
        arch)   common_packages+=(cargo) ;;
        suse)   common_packages+=(cargo) ;;
        alpine) common_packages+=(cargo) ;;
    esac

    install_packages "${common_packages[@]}"

    install_yay

    install_lazygit || true
    install_yazi || true
    install_bw || true

    install_rbw || true

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
    echo
    echo "This will:"
    echo "  - Install the Bitwarden CLI (bw) to allow authentication from this machine."
    echo "  - Use Bitwarden API keys exported from your Bitwarden account."
    echo "  - Expect a Bitwarden item named 'bw-api' containing:"
    echo "      username: client_id"
    echo "      password: client_secret"
    echo "  - These values correspond to the API keys generated in your Bitwarden account."
    echo "  - The script will retrieve them, register rbw, and start the SSH agent."
    echo
    echo -n "This will configure rbw and start the agent. (Y/n) "
    read -r use_bitwarden
    if [[ -z "$use_bitwarden" || "$use_bitwarden" =~ ^[Yy]$ ]]; then
        setup_rbw
    else
        print_info "Skipping Bitwarden SSH agent setup."
    fi

    setup_tpm
    set_default_shell
    verify_commands

    print_info "Installation complete!"
}

main