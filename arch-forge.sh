#!/bin/bash

# ==============================================================================
# arch-forge - Post-Install Setup Forge for Arch Linux
# Forges your fresh Arch into a battle-ready workstation.
# Audio | NVIDIA | Fonts | Essential Tools
#
# NOTE FOR PRIVATE REPOSITORIES:
# If you make your repository private, export your GitHub Personal Access Token (PAT):
#   export GITHUB_TOKEN="ghp_your_token_here"
# Before running the script. The script will automatically use it for curl.
# ==============================================================================

# --- Colors & UI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'

# --- State Tracking ---
STATE_FILE="$HOME/.forge_completed"

is_completed() {
    local opt_id="$1"
    [ -f "$STATE_FILE" ] && grep -q "^$opt_id$" "$STATE_FILE"
}

mark_completed() {
    local opt_id="$1"
    touch "$STATE_FILE" 2>/dev/null
    if [ -f "$STATE_FILE" ] && ! grep -q "^$opt_id$" "$STATE_FILE"; then
        echo "$opt_id" >> "$STATE_FILE" 2>/dev/null
    fi
}

get_status() {
    local opt_id="$1"
    local is_private="${2:-false}"
    
    if [ "$is_private" = "true" ] && [ "$PRIVATE_REPO_DISABLED" = "true" ]; then
        echo -e " ${RED}[DISABLED - TOKEN REQUIRED]${NC}"
    elif is_completed "$opt_id"; then
        echo -e " ${GREEN}[✓ INSTALLED]${NC}"
    else
        echo ""
    fi
}

check_private_repo_allowed() {
    if [ "$PRIVATE_REPO_DISABLED" = "true" ]; then
        echo -e "\n${RED}${BOLD}[ERROR]${NC} This option requires a GitHub Personal Access Token (GITHUB_TOKEN)."
        echo -e "Please export GITHUB_TOKEN or place a 'token.txt' in the script directory, then restart."
        return 1
    fi
    return 0
}

# --- Script Location & Init Variables ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PRIVATE_REPO_DISABLED=false

# --- Helper Functions (same style as install.sh) ---

msg() {
    echo -e "\n${BLUE}${BOLD}[FORGE]${NC} ${CYAN}$1${NC}"
}

success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}${BOLD}[ERROR]${NC} $1"
    exit 1
}

run_cmd() {
    echo -e "${CYAN}Executing: ${BOLD}$1${NC}"
    eval "$1"
}

brief() {
    echo -e "\n${MAGENTA}${BOLD}>> WHY:${NC} ${DIM}$1${NC}"
}

wait_step() {
    echo -e "\n${YELLOW}>> Press [Enter] to continue to the next step...${NC}"
    read -r
}

check_success() {
    if [ $? -eq 0 ]; then
        success "$1 finished successfully."
    else
        warn "$1 may have failed."
        echo -e "Do you want to [r]etry, [i]gnore, or [a]bort?"
        read -p "(r/i/a): " choice
        case $choice in
            r) return 1 ;;
            i) return 0 ;;
            *) exit 1 ;;
        esac
    fi
}

section_header() {
    echo ""
    echo -e "${BLUE}${BOLD}============================================================${NC}"
    echo -e "   ${BOLD}$1${NC}"
    echo -e "${BLUE}${BOLD}============================================================${NC}"
    echo ""
}

ensure_yay() {
    if command -v yay &> /dev/null; then
        return 0
    fi

    msg "Installing base development tools and yay (AUR helper)"
    brief "base-devel and git are needed to build yay from source. yay is the AUR helper
       required to install community packages."
    echo ""

    run_cmd "sudo pacman -S --needed --noconfirm base-devel git"
    check_success "Build tools installation"

    msg "Building and installing yay from source..."
    run_cmd "git clone https://aur.archlinux.org/yay.git /tmp/yay-build"
    run_cmd "cd /tmp/yay-build && makepkg -si --noconfirm"
    run_cmd "rm -rf /tmp/yay-build"
    check_success "yay installation"
    wait_step
}

# --- Initialization & Token Check ---
clear
echo -e "${BLUE}${BOLD}============================================================${NC}"
echo -e "          ${BOLD}arch-forge :: Initial Checks & Setup${NC}"
echo -e "${BLUE}${BOLD}============================================================${NC}\n"

# First, attempt to auto-load from token.txt if not in environment
if [ -z "$GITHUB_TOKEN" ] && [ -f "$SCRIPT_DIR/token.txt" ]; then
    export GITHUB_TOKEN="$(cat "$SCRIPT_DIR/token.txt" | tr -d '\r\n ')"
fi

if [ -n "$GITHUB_TOKEN" ]; then
    echo -e "${GREEN}${BOLD}[NOTE]${NC} You have defined your GITHUB_TOKEN for this repository!"
    if [ -f "$SCRIPT_DIR/token.txt" ]; then
        echo -e "       (Loaded from token.txt in script directory)"
    else
        echo -e "       (Detected from environment variable)"
    fi
    echo ""
else
    echo -e "${YELLOW}${BOLD}[WARNING]${NC} GITHUB_TOKEN is NOT defined, and token.txt was not found."
    echo -e "          Options that depend on the private 'pub' repository"
    echo -e "          (Arabic Fonts, XFCE Settings, Secure Manager) will be disabled."
    echo -e "          A GitHub Personal Access Token is required to download these assets."
    echo ""
    PRIVATE_REPO_DISABLED=true
fi

# --- Internet Check ---
if ! ping -c 1 google.com &> /dev/null; then
    error "No internet connection detected. Please connect and try again."
fi

echo -e "Press [Enter] to proceed to the main menu..."
read -r

# ==============================================================================
# MAIN MENU
# ==============================================================================

show_menu() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "============================================================"
    echo "          arch-forge :: Post-Install Setup Forge             "
    echo "============================================================"
    echo -e "${NC}"
    echo -e "  ${CYAN}1)${NC} Install Audio (PipeWire + PulseAudio)$(get_status "audio")"
    echo -e "  ${CYAN}2)${NC} Install NVIDIA Driver (580xx via yay/AUR)$(get_status "nvidia")"
    echo -e "  ${CYAN}3)${NC} Download & Install Fonts (Arabic + Microsoft Fonts)$(get_status "fonts" "true")"
    echo -e "  ${CYAN}4)${NC} Install Useful Tools$(get_status "tools")"
    echo -e "  ${CYAN}5)${NC} Apply XFCE Desktop Settings (from GitHub)$(get_status "xfce" "true")"
    echo -e "  ${CYAN}6)${NC} Install Secure Manager (from GitHub)$(get_status "secure_manager" "true")"
    echo -e "  ${CYAN}7)${NC} Install G-manager (from GitHub)$(get_status "g_manager" "true")"
    echo -e "  ${CYAN}8)${NC} Install Git Helper (from GitHub)$(get_status "git_helper" "true")"
    echo -e "  ${CYAN}9)${NC} XFCE Backup/Restore Reminder$(get_status "backup")"
    echo -e "  ${CYAN}10)${NC} Exit"
    echo ""
    read -p "Select an option [1-10]: " opt
}

# ==============================================================================
# SECTION 1: AUDIO (PipeWire)
# ==============================================================================

install_audio() {
    section_header "SECTION 1: AUDIO SETUP (PipeWire)"

    # --- Step 1: Install PipeWire stack ---
    msg "Step 1: Installing PipeWire, PulseAudio compatibility, and ALSA utilities"
    brief "PipeWire is the modern audio/video server for Linux, replacing PulseAudio.
       pipewire-pulse provides backward-compatibility so apps that expect PulseAudio still work.
       WirePlumber is the session manager that decides how audio streams are routed.
       alsa-utils gives you low-level mixer tools like 'amixer' and 'alsamixer'."
    echo ""
    run_cmd "sudo pacman -S --noconfirm pipewire pipewire-pulse wireplumber alsa-utils"
    check_success "PipeWire installation"
    wait_step

    # --- Step 2: Enable PipeWire services ---
    msg "Step 2: Enabling PipeWire user services"
    brief "These run as your user (not root). '--user' means they live in your session.
       'enable --now' both starts them immediately AND marks them to auto-start on login.
       After this, any app playing audio will route through PipeWire automatically."
    echo ""
    run_cmd "systemctl --user enable --now pipewire pipewire-pulse wireplumber"
    check_success "PipeWire services"
    wait_step

    # --- Step 3: Install pavucontrol ---
    msg "Step 3: Installing PulseAudio Volume Control (pavucontrol)"
    brief "pavucontrol is a graphical mixer. Even though we use PipeWire, it speaks the
       PulseAudio protocol, so pavucontrol works perfectly. It lets you control
       per-app volume, choose output devices, and configure input sources."
    echo ""
    run_cmd "sudo pacman -S --noconfirm pavucontrol"
    check_success "pavucontrol installation"
    wait_step

    # --- Step 4: Verify ---
    msg "Step 4: Verifying audio stack"
    brief "'pactl info' queries PulseAudio (via PipeWire). Look at the 'Server Name' line —
       it should say 'PulseAudio (on PipeWire)'. That confirms everything is wired correctly."
    echo ""
    run_cmd "pactl info"
    check_success "Audio verification"
    wait_step

    mark_completed "audio"
    success "Audio setup complete! Your system now uses PipeWire."
}

# ==============================================================================
# SECTION 2: NVIDIA DRIVER (580xx via AUR/yay)
# ==============================================================================

install_nvidia() {
    section_header "SECTION 2: NVIDIA DRIVER INSTALLATION"

    # --- Step 1: Ensure yay is installed ---
    ensure_yay

    # --- Step 2: Enable multilib ---
    msg "Step 2: Enabling [multilib] repository"
    brief "multilib contains 32-bit libraries (lib32-*). NVIDIA needs lib32-nvidia-utils
       so 32-bit apps (like Steam/Wine games) can use GPU acceleration.
       We uncomment the [multilib] section and its Include line in /etc/pacman.conf."
    echo ""

    if grep -q "^\[multilib\]" /etc/pacman.conf; then
        success "[multilib] is already enabled."
    else
        warn "Uncommenting [multilib] in /etc/pacman.conf..."
        run_cmd "sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf"
        check_success "Enable multilib"
    fi
    wait_step

    # --- Step 3: System update ---
    msg "Step 3: Full system update (to sync multilib)"
    brief "After enabling a new repo, we must sync the package database and update.
       -Syu = Sync database + upgrade all packages. This ensures multilib packages
       are now visible to pacman."
    echo ""
    run_cmd "sudo pacman -Syu --noconfirm"
    check_success "System update"
    wait_step

    # --- Step 4: Install linux-headers ---
    msg "Step 4: Installing Linux kernel headers"
    brief "DKMS (Dynamic Kernel Module Support) compiles NVIDIA drivers against your
       exact kernel version. It needs the kernel headers to do this. Without them,
       the NVIDIA module can't be built and your GPU won't be recognized."
    echo ""
    run_cmd "sudo pacman -S --noconfirm linux-headers"
    check_success "linux-headers"
    wait_step

    # --- Step 5: Install NVIDIA 580xx packages ---
    msg "Step 5: Installing NVIDIA 580xx driver (DKMS) from AUR"
    brief "nvidia-580xx-dkms   = the kernel module, auto-rebuilds on kernel updates via DKMS.
       nvidia-580xx-utils  = userspace driver + OpenGL libraries.
       nvidia-580xx-settings = the NVIDIA Settings GUI for fan/performance/display config.
       lib32-nvidia-580xx-utils = 32-bit GL libs for Wine/Steam games.
       nvidia-prime = lets you switch between integrated/discrete GPU (for laptops)."
    echo ""
    warn "This is a large AUR build. It will compile from source and may take a while."
    wait_step
    run_cmd "yay -S nvidia-580xx-dkms nvidia-580xx-utils nvidia-580xx-settings lib32-nvidia-580xx-utils nvidia-prime"
    check_success "NVIDIA 580xx driver"
    wait_step

    # --- Step 6: Verify DKMS ---
    msg "Step 6: Verifying DKMS module status"
    brief "'dkms status' shows all DKMS-managed kernel modules. You should see nvidia
       listed as 'installed' for your running kernel version.
       'lspci -k' shows which kernel driver is bound to your GPU hardware."
    echo ""
    run_cmd "dkms status"
    echo ""
    run_cmd "lspci -k | grep -A 2 -E '(VGA|3D|Display)'"
    check_success "DKMS verification"
    wait_step

    # --- Step 7: nvidia-smi ---
    msg "Step 7: Running nvidia-smi"
    brief "nvidia-smi (System Management Interface) is the GPU monitoring tool.
       It shows driver version, CUDA version, GPU temperature, memory usage,
       and running GPU processes. If this works, your driver is fully operational."
    echo ""
    run_cmd "nvidia-smi"
    check_success "nvidia-smi"
    wait_step

    mark_completed "nvidia"
    success "NVIDIA driver setup complete!"
}

# ==============================================================================
# SECTION 3: FONTS (Arabic fonts from GitHub & Microsoft fonts from AUR)
# ==============================================================================

install_fonts() {
    section_header "SECTION 3: FONTS INSTALLATION (ARABIC + MICROSOFT)"

    FONT_DIR="$HOME/.local/share/fonts"
    REPO_BASE="https://raw.githubusercontent.com/someoneTrying-99/pub/main/fonts"

    # Font file list
    FONTS=(
        "ArefRuqaa-Bold.ttf"
        "ArefRuqaa-Regular.ttf"
        "Cairo-Black.ttf"
        "Cairo-Bold.ttf"
        "Cairo-ExtraBold.ttf"
        "Cairo-ExtraLight.ttf"
        "Cairo-Light.ttf"
        "Cairo-Medium.ttf"
        "Cairo-Regular.ttf"
        "Cairo-SemiBold.ttf"
        "NotoNaskhArabic-Bold.ttf"
        "NotoNaskhArabic-Medium.ttf"
        "NotoNaskhArabic-Regular.ttf"
        "NotoNaskhArabic-SemiBold.ttf"
    )

    # --- Step 1: Create font directory ---
    msg "Step 1: Preparing font directory"
    brief "~/.local/share/fonts/ is the per-user font directory on Linux. Fonts placed
       here are available to your user without needing root. The system scans this
       folder when you run fc-cache."
    echo ""
    run_cmd "mkdir -p $FONT_DIR"
    check_success "Font directory"
    wait_step

    # --- Step 2: Download fonts ---
    msg "Step 2: Downloading fonts from GitHub"
    brief "We pull each .ttf directly from the raw GitHub URL into your local fonts folder.
       These are three Arabic font families:
         - Aref Ruqaa: A classic Ruq'ah calligraphy style.
         - Cairo: A modern, clean Arabic/Latin sans-serif.
         - Noto Naskh Arabic: Google's Naskh-style font for full Unicode coverage."
    echo ""

    local auth_header=""
    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="-H 'Authorization: token $GITHUB_TOKEN'"
    fi

    for font in "${FONTS[@]}"; do
        run_cmd "curl -fsSL $auth_header -o \"$FONT_DIR/$font\" \"$REPO_BASE/$font\""
    done
    check_success "Font download"
    wait_step

    # --- Step 3: Rebuild font cache ---
    msg "Step 3: Rebuilding font cache"
    brief "fc-cache scans all font directories and builds a lookup database so apps can
       find fonts by name instantly. -f forces a rebuild, -v shows verbose output
       so you can see which directories were scanned."
    echo ""
    run_cmd "fc-cache -fv"
    check_success "Font cache rebuild"
    wait_step

    # --- Step 4: Verify ---
    msg "Step 4: Verifying installed fonts"
    brief "fc-list queries the font database. We grep for 'Cairo' to confirm at least
       one of our fonts was registered correctly."
    echo ""
    run_cmd "fc-list | grep Cairo"
    echo ""
    run_cmd "fc-list | grep Ruqaa"
    echo ""
    run_cmd "fc-list | grep 'Noto Naskh'"
    check_success "Font verification"
    wait_step

    # --- Step 5: Install Microsoft TrueType Core Fonts via AUR ---
    msg "Step 5: Installing Microsoft TrueType Core Fonts (AUR)"
    brief "Microsoft's Core TrueType fonts (Arial, Times New Roman, Courier New, etc.)
       are available from the AUR as ttf-ms-fonts. We build and install it using yay.
       No --noconfirm is used so you can handle interactive prompts."
    echo ""
    ensure_yay
    run_cmd "yay -S ttf-ms-fonts"
    check_success "Microsoft core fonts installation"
    wait_step

    mark_completed "fonts"
    success "Fonts installed! Arabic fonts and Microsoft TrueType fonts are ready."
}

# ==============================================================================
# SECTION 4: USEFUL TOOLS
# ==============================================================================

install_tools() {
    section_header "SECTION 4: USEFUL TOOLS"

    # --- Ensure yay is installed first (since some tools are AUR packages) ---
    ensure_yay

    # --- unzip ---
    msg "Installing unzip"
    brief "unzip extracts .zip archives from the command line. Many downloads and AUR
       packages come as .zip files, so this is a must-have utility."
    echo ""
    run_cmd "sudo pacman -S --noconfirm unzip"
    check_success "unzip"
    wait_step

    # --- firefox ---
    msg "Installing Firefox"
    brief "Firefox is a free, open-source browser by Mozilla. Unlike Chrome, it's in the
       official Arch repos. It's privacy-focused, supports extensions, and is a solid
       default browser right out of the box."
    echo ""
    run_cmd "sudo pacman -S --noconfirm firefox"
    check_success "Firefox"
    wait_step

    # --- inkscape ---
    msg "Installing Inkscape"
    brief "Inkscape is a professional vector graphics editor (like Adobe Illustrator).
       It works with SVG files and is great for logos, icons, and scalable artwork."
    echo ""
    run_cmd "sudo pacman -S --noconfirm inkscape"
    check_success "Inkscape"
    wait_step

    # --- htop ---
    msg "Installing htop"
    brief "htop is an interactive process viewer — a colorful, scrollable upgrade over 'top'.
       It shows CPU/RAM usage per core, lets you search/filter/kill processes, and
       displays a tree view of parent-child process relationships."
    echo ""
    run_cmd "sudo pacman -S --noconfirm htop"
    check_success "htop"
    wait_step

    # --- google-chrome ---
    msg "Installing Google Chrome (from AUR)"
    brief "Chrome isn't in the official Arch repos because it's proprietary. yay fetches
       it from the AUR, downloads the official .deb/.rpm from Google, repackages it
       for Arch, and installs it. Expect a large download."
    echo ""
    run_cmd "yay -S google-chrome"
    check_success "Google Chrome"
    wait_step

    # --- obsidian ---
    msg "Installing Obsidian"
    brief "Obsidian is a Markdown-based knowledge base / note-taking app. Notes are stored
       as plain .md files on disk, so you always own your data. It supports linking,
       graphs, plugins, and is perfect for building a personal wiki."
    echo ""
    run_cmd "sudo pacman -S --noconfirm obsidian"
    check_success "Obsidian"
    wait_step

    # --- orchis-theme ---
    msg "Installing Orchis Theme (from AUR)"
    brief "Orchis is a material design theme for GNOME/XFCE. It's clean and modern."
    echo ""
    run_cmd "yay -S orchis-theme"
    check_success "Orchis Theme"
    wait_step

    # --- bibata-cursor-theme ---
    msg "Installing Bibata Cursor Theme (from AUR)"
    brief "Bibata is a modern cursor set. We will use the Ice variant."
    echo ""
    run_cmd "yay -S bibata-cursor-theme"
    check_success "Bibata Cursor Theme"
    wait_step

    # --- whisker-menu ---
    msg "Installing Whisker Menu Plugin"
    brief "Whisker Menu is an alternate application menu for XFCE. It's more modern and searchable."
    echo ""
    run_cmd "sudo pacman -S --noconfirm xfce4-whiskermenu-plugin"
    check_success "Whisker Menu Plugin"
    wait_step

    # --- antigravity ---
    msg "Installing Antigravity (AI Coding Assistant)"
    brief "Antigravity is an AI-powered coding assistant that runs locally on your machine.
       Fun fact: it's the very tool that wrote this script you're running right now.
       Yes, the forge forges itself. You're welcome."
    echo ""
    run_cmd "yay -S antigravity"
    check_success "Antigravity"
    wait_step

    mark_completed "tools"
    success "All useful tools installed!"
}

# ==============================================================================
# SECTION 5: APPLY XFCE DESKTOP CONFIGURATIONS
# ==============================================================================

apply_xfce_configs() {
    section_header "SECTION 5: XFCE CUSTOMIZATION (FROM GITHUB)"

    # --- Step 0: Check dependencies needed for custom XFCE settings ---
    local missing_deps=()
    for pkg in "orchis-theme" "bibata-cursor-theme" "xfce4-whiskermenu-plugin"; do
        if ! pacman -Qq "$pkg" &>/dev/null; then
            missing_deps+=("$pkg")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        warn "The following packages required by your configurations are missing: ${missing_deps[*]}"
        brief "These are heavily referenced in your custom XFCE XML settings (themes, cursor styles, and panel menu)."
        echo ""
        read -p "Would you like to install them now before applying settings? (y/n): " install_choice
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            ensure_yay
            # Whisker menu is in official repo, others are in AUR, yay can install all of them
            run_cmd "yay -S --needed --noconfirm ${missing_deps[*]}"
            check_success "Dependencies installation"
        else
            warn "Continuing without installing dependencies. Some panel icons or styles might look broken."
            wait_step
        fi
    else
        success "All required XFCE packages (Orchis theme, Bibata cursor, Whisker menu) are already installed!"
        wait_step
    fi

    local XFCONF_DIR="$HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
    local REPO_BASE="https://raw.githubusercontent.com/someoneTrying-99/pub/main/xfconf/xfce-perchannel-xml"

    # List of all files with their relative paths
    local FILES=(
        "displays.xml"
        "keyboard-layout.xml"
        "keyboards.xml"
        "thunar.xml"
        "xfce4-desktop.xml"
        "xfce4-keyboard-shortcuts.xml"
        "xfce4-notifyd.xml"
        "xfce4-panel.xml"
        "xfce4-power-manager.xml"
        "xfce4-session.xml"
        "xfce4-terminal.xml"
        "xfwm4.xml"
        "xsettings.xml"
    )

    # --- Step 1: Create configuration directory ---
    msg "Step 1: Preparing XFCE configuration directory"
    brief "We ensure the XFCE4 configurations folder (~/.config/xfce4/xfconf/xfce-perchannel-xml/) exists."
    echo ""
    run_cmd "mkdir -p $XFCONF_DIR"
    check_success "XFCE config directory preparation"
    wait_step

    # --- Step 2: Download configurations ---
    msg "Step 2: Downloading 13 configuration XML files from GitHub"
    brief "We download all the XFCE configurations from your repository,
       preserving their structure automatically using curl's --create-dirs."
    echo ""

    local auth_header=""
    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="-H 'Authorization: token $GITHUB_TOKEN'"
        msg "GitHub Personal Access Token detected! Using authenticated requests."
    fi

    for f in "${FILES[@]}"; do
        run_cmd "curl -fsSL --create-dirs $auth_header -o \"$XFCONF_DIR/$f\" \"$REPO_BASE/$f\""
    done
    check_success "XFCE configurations download"
    wait_step

    # --- Step 3: Crucial restart reminder ---
    msg "Step 3: Reminder to restart/reload XFCE Desktop"
    brief "XFCE caches its configurations in memory. To load the new XML settings, you must restart."
    echo ""
    warn "CRITICAL REMINDER: You MUST restart your XFCE session (log out & log back in, or reboot)"
    warn "for all these configurations to take effect!"
    echo -e "${YELLOW}>> Pro-Tip: You can restart the panel immediately without logging out by running:${NC}"
    echo -e "   ${BOLD}xfce4-panel -r${NC}"
    wait_step

    mark_completed "xfce"
    success "XFCE desktop configurations successfully applied!"
}

# ==============================================================================
# SECTION 6: XFCE BACKUP INSTRUCTIONS & REMINDER
# ==============================================================================

# ==============================================================================
# SECTION 6: SECURE MANAGER (FROM GITHUB)
# ==============================================================================

install_secure_manager() {
    section_header "SECTION 6: SECURE MANAGER INSTALLATION"

    # --- Step 1: Create mother directory ---
    msg "Step 1: Preparing secure_manager directory in /usr/local/lib"
    brief "We create the mother directory /usr/local/lib/secure_manager to house the files."
    echo ""
    run_cmd "sudo mkdir -p /usr/local/lib/secure_manager"
    check_success "Directory creation"
    wait_step

    # --- Step 2: Download files ---
    msg "Step 2: Downloading Secure Manager files from GitHub"
    brief "We download all the files belonging to Secure Manager from your repository,
       preserving their relative paths (like lib/ and icons/) automatically using curl's --create-dirs."
    echo ""

    local auth_header=""
    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="-H 'Authorization: token $GITHUB_TOKEN'"
    fi

    local REPO_BASE="https://raw.githubusercontent.com/someoneTrying-99/pub/main/secure_manager"

    # List of all files with their relative paths
    local FILES=(
        "README.md"
        "secure_manager.sh"
        "icons/decrypted.png"
        "icons/encrypted.png"
        "lib/backup.sh"
        "lib/config.sh"
        "lib/guard.sh"
        "lib/ui.sh"
        "lib/utils.sh"
        "lib/vault.sh"
    )

    for f in "${FILES[@]}"; do
        run_cmd "sudo curl -fsSL --create-dirs $auth_header -o \"/usr/local/lib/secure_manager/$f\" \"$REPO_BASE/$f\""
    done
    check_success "Download files"
    wait_step

    # --- Step 3: Make secure_manager.sh executable and symlink ---
    msg "Step 3: Making script executable and creating symlink"
    brief "We make the main secure_manager.sh script executable, then create a symbolic link in /usr/local/bin
       named 'secmgr' so you can run it from anywhere in your terminal by typing 'secmgr'."
    echo ""
    run_cmd "sudo chmod -R u+rwX,go+rX /usr/local/lib/secure_manager"
    run_cmd "sudo chmod +x /usr/local/lib/secure_manager/secure_manager.sh"
    run_cmd "sudo ln -sf /usr/local/lib/secure_manager/secure_manager.sh /usr/local/bin/secmgr"
    check_success "Permissions and symlink"
    wait_step

    mark_completed "secure_manager"
    success "Secure Manager installed successfully! You can run it with the command: secmgr"
}

# ==============================================================================
# SECTION 7: G-MANAGER INSTALLATION
# ==============================================================================

install_g_manager() {
    section_header "SECTION 7: G-MANAGER INSTALLATION"

    # --- Step 1: Create mother directory ---
    msg "Step 1: Preparing G-manager directory in /usr/local/lib"
    brief "We create the mother directory /usr/local/lib/G-manager to house the files."
    echo ""
    run_cmd "sudo mkdir -p /usr/local/lib/G-manager"
    check_success "Directory creation"
    wait_step

    # --- Step 2: Download files ---
    msg "Step 2: Downloading G-manager files from GitHub"
    brief "We download all the files belonging to G-manager from your repository,
       preserving their relative paths (like lib/) automatically using curl's --create-dirs."
    echo ""

    local auth_header=""
    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="-H 'Authorization: token $GITHUB_TOKEN'"
    fi

    local REPO_BASE="https://raw.githubusercontent.com/someoneTrying-99/pub/main/G-manager"

    # List of all files with their relative paths
    local FILES=(
        "README.md"
        "TROUBLESHOOTING.md"
        "g_manager.sh"
        "lib/config.sh"
        "lib/core.sh"
        "lib/ui.sh"
    )

    for f in "${FILES[@]}"; do
        run_cmd "sudo curl -fsSL --create-dirs $auth_header -o \"/usr/local/lib/G-manager/$f\" \"$REPO_BASE/$f\""
    done
    check_success "Download files"
    wait_step

    # --- Step 3: Make g_manager.sh executable and symlink ---
    msg "Step 3: Making script executable and creating symlink"
    brief "We make the main g_manager.sh script executable, then create a symbolic link in /usr/local/bin
       named 'a3ctl' so you can run it from anywhere in your terminal by typing 'a3ctl'."
    echo ""
    run_cmd "sudo chmod -R u+rwX,go+rX /usr/local/lib/G-manager"
    run_cmd "sudo chmod +x /usr/local/lib/G-manager/g_manager.sh"
    run_cmd "sudo ln -sf /usr/local/lib/G-manager/g_manager.sh /usr/local/bin/a3ctl"
    check_success "Permissions and symlink"
    wait_step

    mark_completed "g_manager"
    success "G-manager installed successfully! You can run it with the command: a3ctl"
}

# ==============================================================================
# SECTION 8: GIT HELPER INSTALLATION
# ==============================================================================

install_git_helper() {
    section_header "SECTION 8: GIT HELPER INSTALLATION"

    # --- Step 1: Create mother directory ---
    msg "Step 1: Preparing git_helper directory in /usr/local/lib"
    brief "We create the mother directory /usr/local/lib/git_helper to house the files."
    echo ""
    run_cmd "sudo mkdir -p /usr/local/lib/git_helper"
    check_success "Directory creation"
    wait_step

    # --- Step 2: Download files ---
    msg "Step 2: Downloading Git Helper files from GitHub"
    brief "We download all the files belonging to Git Helper from your repository,
       preserving their relative paths (like lib/) automatically using curl's --create-dirs."
    echo ""

    local auth_header=""
    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="-H 'Authorization: token $GITHUB_TOKEN'"
    fi

    local REPO_BASE="https://raw.githubusercontent.com/someoneTrying-99/pub/main/git_helper"

    # List of all files with their relative paths
    local FILES=(
        "git_helper.sh"
        "lib/config.sh"
        "lib/core.sh"
        "lib/ui.sh"
    )

    for f in "${FILES[@]}"; do
        run_cmd "sudo curl -fsSL --create-dirs $auth_header -o \"/usr/local/lib/git_helper/$f\" \"$REPO_BASE/$f\""
    done
    check_success "Download files"
    wait_step

    # --- Step 3: Make git_helper.sh executable and symlink ---
    msg "Step 3: Making script executable and creating symlink"
    brief "We make the main git_helper.sh script executable, then create a symbolic link in /usr/local/bin
       named 'gith' so you can run it from anywhere in your terminal by typing 'gith'."
    echo ""
    run_cmd "sudo chmod -R u+rwX,go+rX /usr/local/lib/git_helper"
    run_cmd "sudo chmod +x /usr/local/lib/git_helper/git_helper.sh"
    run_cmd "sudo ln -sf /usr/local/lib/git_helper/git_helper.sh /usr/local/bin/gith"
    check_success "Permissions and symlink"
    wait_step

    mark_completed "git_helper"
    success "Git Helper installed successfully! You can run it with the command: gith"
}

# ==============================================================================
# SECTION 9: XFCE BACKUP INSTRUCTIONS & REMINDER
# ==============================================================================

backup_reminder() {
    section_header "SECTION 9: XFCE BACKUP INSTRUCTIONS & REMINDER"

    msg "Manual Backup & Restore Instructions"
    brief "To prevent scripts from accidentally overwriting your precious local configurations,
       it is highly recommended to manage backups manually."
    echo ""
    echo -e "${BOLD}Your current XFCE4 configurations are saved in:${NC}"
    echo -e "  ${CYAN}~/.config/xfce4/xfconf/${NC}"
    echo ""
    echo -e "${YELLOW}To manually backup your current settings, run:${NC}"
    echo -e "  ${GREEN}cp -r ~/.config/xfce4/xfconf ~/Desktop/xfconf-backup-\$(date +%F)${NC}"
    echo ""
    echo -e "${YELLOW}To restore those settings later, run:${NC}"
    echo -e "  ${GREEN}rm -rf ~/.config/xfce4/xfconf && cp -r ~/Desktop/xfconf-backup-... ~/.config/xfce4/xfconf${NC}"
    echo ""
    warn "Always make sure to backup before applying new downloaded settings!"
    mark_completed "backup"
    wait_step
}

# ==============================================================================
# MAIN LOOP
# ==============================================================================

while true; do
    show_menu
    case $opt in
        1) install_audio ;;
        2) install_nvidia ;;
        3) if check_private_repo_allowed; then install_fonts; fi ;;
        4) install_tools ;;
        5) if check_private_repo_allowed; then apply_xfce_configs; fi ;;
        6) if check_private_repo_allowed; then install_secure_manager; fi ;;
        7) if check_private_repo_allowed; then install_g_manager; fi ;;
        8) if check_private_repo_allowed; then install_git_helper; fi ;;
        9) backup_reminder ;;
        10) echo -e "\n${CYAN}Thanks for using arch-forge. Happy hacking!${NC}"; exit 0 ;;
        *) warn "Invalid option." ;;
    esac
    echo ""
    read -p "Press Enter to return to the menu..."
done
