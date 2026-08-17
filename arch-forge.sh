#!/bin/bash

# ==============================================================================
# arch-forge - Post-Install Setup Forge for Arch Linux
# Forges your fresh Arch into a battle-ready workstation.
# Audio | AMD / NVIDIA Graphics | Fonts | Tools | Custom Managers
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
    if is_completed "$opt_id"; then
        echo -e " ${GREEN}[✓ INSTALLED]${NC}"
    else
        echo ""
    fi
}

# --- Script Location & Init Variables ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# --- Helper Functions ---

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

# --- Ensure yay, git, and base-devel are installed ---
ensure_yay() {
    if command -v yay &> /dev/null; then
        return 0
    fi

    msg "Installing base development tools and yay (AUR helper)"
    brief "base-devel and git are required to build yay from source.
       yay is the AUR helper required to install community packages."
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

# --- Initialization ---
clear
echo -e "${BLUE}${BOLD}============================================================${NC}"
echo -e "          ${BOLD}arch-forge :: Initial Checks & Setup${NC}"
echo -e "${BLUE}${BOLD}============================================================${NC}\n"

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
    echo "          arch-forge :: Post-Install Setup Forge            "
    echo "============================================================"
    echo -e "${NC}"
    echo -e "  ${CYAN}1)${NC} Install Audio (PipeWire + PulseAudio - Universal)$(get_status "audio")"
    echo -e "  ${CYAN}2)${NC} Install AMD GPU Drivers (HP EliteBook 845 G9 / Radeon)$(get_status "amd_gpu")"
    echo -e "  ${CYAN}3)${NC} Install NVIDIA GPU Driver (MSI GTX970M / Legacy NVIDIA)$(get_status "nvidia")"
    echo -e "  ${CYAN}4)${NC} Download & Install Fonts (Arabic + Microsoft Fonts)$(get_status "fonts")"
    echo -e "  ${CYAN}5)${NC} Install Useful Tools (Chrome, Firefox, Obsidian, etc.)$(get_status "tools")"
    echo -e "  ${CYAN}6)${NC} Apply XFCE Desktop Settings (from GitHub)$(get_status "xfce")"
    echo -e "  ${CYAN}7)${NC} Install Secure Manager (from pub00/pub-data)$(get_status "secure_manager")"
    echo -e "  ${CYAN}8)${NC} Install G-Manager (from pub00/pub-data)$(get_status "g_manager")"
    echo -e "  ${CYAN}9)${NC} Install Git Helper (from pub00/pub-data)$(get_status "git_helper")"
    echo -e "  ${CYAN}10)${NC} Download Wallpapers (from GitHub bg/ folder)$(get_status "wallpapers")"
    echo -e "  ${CYAN}11)${NC} Apply Arabic System Font (Noto Naskh Arabic)$(get_status "arabic_font")"
    echo -e "  ${MAGENTA}────────────────────────────────────────────${NC}"
    echo -e "  ${CYAN}12)${NC} Setup Webcam (v4l-utils + guvcview)$(get_status "webcam")"
    echo -e "  ${CYAN}13)${NC} Install VLC Media Player (Hardware Accelerated)$(get_status "vlc")"
    echo -e "  ${MAGENTA}────────────────────────────────────────────${NC}"
    echo -e "  ${CYAN}14)${NC} Exit"
    echo ""
    read -p "Select an option [1-14]: " opt
}

# ==============================================================================
# SECTION 1: AUDIO (PipeWire - Universal)
# ==============================================================================

install_audio() {
    section_header "SECTION 1: AUDIO SETUP (PipeWire)"

    # --- Step 1: Install PipeWire stack ---
    msg "Step 1: Installing PipeWire, PulseAudio compatibility, and ALSA utilities"
    brief "PipeWire is the modern audio server for Linux.
       pipewire-pulse provides PulseAudio compatibility.
       WirePlumber is the session manager for routing audio streams.
       alsa-utils provides mixer utilities (alsamixer)."
    echo ""
    run_cmd "sudo pacman -S --noconfirm pipewire pipewire-pulse wireplumber alsa-utils"
    check_success "PipeWire installation"
    wait_step

    # --- Step 2: Enable PipeWire services ---
    msg "Step 2: Enabling PipeWire user services"
    brief "Enabling pipewire, pipewire-pulse, and wireplumber for your user session."
    echo ""
    run_cmd "systemctl --user enable --now pipewire pipewire-pulse wireplumber"
    check_success "PipeWire services"
    wait_step

    # --- Step 3: Install pavucontrol ---
    msg "Step 3: Installing Volume Control (pavucontrol)"
    brief "pavucontrol is the graphical volume control mixer."
    echo ""
    run_cmd "sudo pacman -S --noconfirm pavucontrol"
    check_success "pavucontrol installation"
    wait_step

    # --- Step 4: Verify ---
    msg "Step 4: Verifying audio stack"
    echo ""
    run_cmd "pactl info"
    check_success "Audio verification"
    wait_step

    mark_completed "audio"
    success "Audio setup complete! Your system now uses PipeWire."
}

# ==============================================================================
# SECTION 2: AMD GPU DRIVERS (HP EliteBook 845 G9 / Radeon)
# ==============================================================================

install_amd_gpu() {
    section_header "SECTION 2: AMD GPU DRIVERS (Radeon / Vulkan)"

    msg "Step 1: Enabling [multilib] repository"
    brief "multilib provides 32-bit graphics libraries (lib32-mesa, lib32-vulkan-radeon)
       required for games and 32-bit apps."
    echo ""

    if grep -q "^\[multilib\]" /etc/pacman.conf; then
        success "[multilib] is already enabled."
    else
        warn "Uncommenting [multilib] in /etc/pacman.conf..."
        run_cmd "sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf"
        check_success "Enable multilib"
    fi
    wait_step

    msg "Step 2: Syncing package databases"
    run_cmd "sudo pacman -Syu --noconfirm"
    check_success "System update"
    wait_step

    msg "Step 3: Installing AMD open-source drivers and Vulkan"
    brief "xf86-video-amdgpu = X.org AMDGPU driver.
       mesa & lib32-mesa = OpenGL drivers (64 & 32 bit).
       vulkan-radeon & lib32-vulkan-radeon = Vulkan drivers for AMD RADV."
    echo ""
    run_cmd "sudo pacman -S --noconfirm xf86-video-amdgpu mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon"
    check_success "AMD GPU driver installation"
    wait_step

    mark_completed "amd_gpu"
    success "AMD GPU driver setup complete!"
}

# ==============================================================================
# SECTION 3: NVIDIA DRIVER (MSI GTX970M / Legacy NVIDIA)
# ==============================================================================

install_nvidia() {
    section_header "SECTION 3: NVIDIA DRIVER INSTALLATION (MSI / GTX970M)"

    ensure_yay

    msg "Step 1: Enabling [multilib] repository"
    if grep -q "^\[multilib\]" /etc/pacman.conf; then
        success "[multilib] is already enabled."
    else
        warn "Uncommenting [multilib] in /etc/pacman.conf..."
        run_cmd "sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf"
        check_success "Enable multilib"
    fi
    wait_step

    msg "Step 2: Full system update"
    run_cmd "sudo pacman -Syu --noconfirm"
    check_success "System update"
    wait_step

    msg "Step 3: Installing Linux kernel headers"
    run_cmd "sudo pacman -S --noconfirm linux-headers"
    check_success "linux-headers"
    wait_step

    msg "Step 4: Installing NVIDIA 580xx driver (DKMS) from AUR"
    warn "This will compile NVIDIA DKMS modules from source."
    wait_step
    run_cmd "yay -S nvidia-580xx-dkms nvidia-580xx-utils nvidia-580xx-settings lib32-nvidia-580xx-utils nvidia-prime"
    check_success "NVIDIA 580xx driver"
    wait_step

    msg "Step 5: Verifying DKMS module status"
    run_cmd "dkms status"
    echo ""
    run_cmd "lspci -k | grep -A 2 -E '(VGA|3D|Display)'"
    check_success "DKMS verification"
    wait_step

    mark_completed "nvidia"
    success "NVIDIA driver setup complete!"
}

# ==============================================================================
# SECTION 4: FONTS (Arabic + Microsoft Fonts)
# ==============================================================================

install_fonts() {
    section_header "SECTION 4: FONTS INSTALLATION (ARABIC + MICROSOFT)"

    FONT_DIR="$HOME/.local/share/fonts"
    REPO_BASE="https://raw.githubusercontent.com/pub00/pub-data/main/fonts"

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

    msg "Step 1: Preparing font directory (~/.local/share/fonts/)"
    run_cmd "mkdir -p $FONT_DIR"
    check_success "Font directory"
    wait_step

    msg "Step 2: Downloading fonts from GitHub"
    for font in "${FONTS[@]}"; do
        run_cmd "curl -fsSL -o \"$FONT_DIR/$font\" \"$REPO_BASE/$font\""
    done
    check_success "Font download"
    wait_step

    msg "Step 3: Rebuilding font cache"
    run_cmd "fc-cache -fv"
    check_success "Font cache rebuild"
    wait_step

    msg "Step 4: Installing Microsoft TrueType Core Fonts (AUR)"
    ensure_yay
    run_cmd "yay -S ttf-ms-fonts"
    check_success "Microsoft core fonts installation"
    wait_step

    mark_completed "fonts"
    success "Fonts installed! Arabic fonts and Microsoft TrueType fonts are ready."
}

# ==============================================================================
# SECTION 5: USEFUL TOOLS
# ==============================================================================

install_tools() {
    section_header "SECTION 5: USEFUL TOOLS"

    ensure_yay

    # Helper function to smartly install a package if it's not already installed
    smart_install() {
        local pkg="$1"
        local manager="$2" # "pacman" or "yay"
        local custom_cmd="$3" # Optional: Custom command to install

        # Check if the package is already installed
        if pacman -Qq "$pkg" &> /dev/null; then
            echo -e " ${GREEN}[✓]${NC} $pkg is already installed. Skipping."
        else
            echo -e " ${CYAN}[+]${NC} Installing $pkg..."
            if [ -n "$custom_cmd" ]; then
                run_cmd "$custom_cmd"
            elif [ "$manager" = "pacman" ]; then
                run_cmd "sudo pacman -S --noconfirm $pkg"
            elif [ "$manager" = "yay" ]; then
                # Some yay packages might prompt, so --noconfirm is used to automate
                run_cmd "yay -S --noconfirm $pkg"
            else
                warn "Unknown package manager: $manager for $pkg"
                return 1
            fi
            check_success "$pkg"
        fi
    }

    msg "Checking and installing Useful Tools..."

    # --- Official Repositories (pacman) ---
    smart_install "unzip" "pacman"
    smart_install "xarchiver" "pacman"
    smart_install "firefox" "pacman"
    smart_install "inkscape" "pacman"
    smart_install "htop" "pacman"
    smart_install "obsidian" "pacman"

    # --- AUR Packages (yay) ---
    smart_install "google-chrome" "yay"
    smart_install "bibata-cursor-theme" "yay"
    smart_install "antigravity" "yay"

    # Example of adding a custom tool in the future:
    # smart_install "my-custom-tool" "custom" "curl -sS https://example.com/install.sh | bash"

    wait_step

    mark_completed "tools"
    success "All useful tools are installed!"
}

# ==============================================================================
# SECTION 6: APPLY XFCE DESKTOP CONFIGURATIONS
# ==============================================================================

apply_xfce_configs() {
    section_header "SECTION 6: XFCE CUSTOMIZATION (FROM GITHUB)"

    local XFCE_CONFIG_DIR="$HOME/.config/xfce4"
    local REPO_URL="https://github.com/pub00/pub-data.git"
    local TMP_DIR="/tmp/pub-data-xfce-setup"

    msg "Step 1: Downloading configurations from GitHub"
    brief "Cloning repository to fetch the complete xfce4 folder"
    run_cmd "rm -rf $TMP_DIR"
    run_cmd "git clone --depth 1 $REPO_URL $TMP_DIR"
    check_success "Repository download"
    wait_step

    msg "Step 2: Applying XFCE configurations"
    brief "Copying the entire xfce4 folder to ~/.config/xfce4/ (User Permissions)"
    
    # Ensure destination exists
    run_cmd "mkdir -p $XFCE_CONFIG_DIR"
    
    if [ -d "$TMP_DIR/xfce4" ]; then
        # cp -a preserves structure, -T ensures contents merge properly
        # NO sudo used here, keeping permissions for the current user
        run_cmd "cp -a $TMP_DIR/xfce4/* $XFCE_CONFIG_DIR/"
        check_success "Configuration overwrite"
    else
        error "Could not find 'xfce4' directory in the repository!"
    fi
    wait_step

    msg "Step 3: Cleaning up temporary files"
    run_cmd "rm -rf $TMP_DIR"

    msg "Step 4: Reminder to restart/reload XFCE Desktop"
    warn "CRITICAL REMINDER: You MUST restart your XFCE session (log out & log back in, or reboot)"
    warn "for all these configurations to take effect!"
    echo -e "${YELLOW}>> Pro-Tip: You can restart the panel immediately without logging out by running:${NC}"
    echo -e "   ${BOLD}xfce4-panel -r${NC}"
    wait_step

    mark_completed "xfce"
    success "XFCE desktop configurations successfully applied!"
}

# ==============================================================================
# SECTION 7: SECURE MANAGER (FROM PUB00/PUB-DATA)
# ==============================================================================

install_secure_manager() {
    section_header "SECTION 7: SECURE MANAGER INSTALLATION"

    msg "Step 1: Preparing secure_manager directory in /usr/local/lib"
    run_cmd "sudo mkdir -p /usr/local/lib/secure_manager"
    check_success "Directory creation"
    wait_step

    msg "Step 2: Downloading Secure Manager files from GitHub (pub00/pub-data)"
    local REPO_BASE="https://raw.githubusercontent.com/pub00/pub-data/main/secure_manager"

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
        run_cmd "sudo curl -fsSL --create-dirs -o \"/usr/local/lib/secure_manager/$f\" \"$REPO_BASE/$f\""
    done
    check_success "Download files"
    wait_step

    msg "Step 3: Making script executable and creating symlink"
    run_cmd "sudo chmod -R u+rwX,go+rX /usr/local/lib/secure_manager"
    run_cmd "sudo chmod +x /usr/local/lib/secure_manager/secure_manager.sh"
    run_cmd "sudo ln -sf /usr/local/lib/secure_manager/secure_manager.sh /usr/local/bin/secmgr"
    check_success "Permissions and symlink"
    wait_step

    mark_completed "secure_manager"
    success "Secure Manager installed successfully! You can run it with: secmgr"
}

# ==============================================================================
# SECTION 8: G-MANAGER INSTALLATION (FROM PUB00/PUB-DATA)
# ==============================================================================

install_g_manager() {
    section_header "SECTION 8: G-MANAGER INSTALLATION"

    msg "Step 1: Preparing G-manager directory in /usr/local/lib"
    run_cmd "sudo mkdir -p /usr/local/lib/G-manager"
    check_success "Directory creation"
    wait_step

    msg "Step 2: Downloading G-manager files from GitHub (pub00/pub-data)"
    local REPO_BASE="https://raw.githubusercontent.com/pub00/pub-data/main/G-manager"

    local FILES=(
        "README.md"
        "TROUBLESHOOTING.md"
        "g_manager.sh"
        "lib/config.sh"
        "lib/core.sh"
        "lib/ui.sh"
    )

    for f in "${FILES[@]}"; do
        run_cmd "sudo curl -fsSL --create-dirs -o \"/usr/local/lib/G-manager/$f\" \"$REPO_BASE/$f\""
    done
    check_success "Download files"
    wait_step

    msg "Step 3: Making script executable and creating symlink"
    run_cmd "sudo chmod -R u+rwX,go+rX /usr/local/lib/G-manager"
    run_cmd "sudo chmod +x /usr/local/lib/G-manager/g_manager.sh"
    run_cmd "sudo ln -sf /usr/local/lib/G-manager/g_manager.sh /usr/local/bin/a3ctl"
    check_success "Permissions and symlink"
    wait_step

    mark_completed "g_manager"
    success "G-manager installed successfully! You can run it with: a3ctl"
}

# ==============================================================================
# SECTION 9: GIT HELPER INSTALLATION (FROM PUB00/PUB-DATA)
# ==============================================================================

install_git_helper() {
    section_header "SECTION 9: GIT HELPER INSTALLATION"

    msg "Step 1: Preparing git_helper directory in /usr/local/lib"
    run_cmd "sudo mkdir -p /usr/local/lib/git_helper"
    check_success "Directory creation"
    wait_step

    msg "Step 2: Downloading Git Helper files from GitHub (pub00/pub-data)"
    local REPO_BASE="https://raw.githubusercontent.com/pub00/pub-data/main/git_helper"

    local FILES=(
        "git_helper.sh"
        "lib/config.sh"
        "lib/core.sh"
        "lib/ui.sh"
    )

    for f in "${FILES[@]}"; do
        run_cmd "sudo curl -fsSL --create-dirs -o \"/usr/local/lib/git_helper/$f\" \"$REPO_BASE/$f\""
    done
    check_success "Download files"
    wait_step

    msg "Step 3: Making script executable and creating symlink"
    run_cmd "sudo chmod -R u+rwX,go+rX /usr/local/lib/git_helper"
    run_cmd "sudo chmod +x /usr/local/lib/git_helper/git_helper.sh"
    run_cmd "sudo ln -sf /usr/local/lib/git_helper/git_helper.sh /usr/local/bin/gith"
    check_success "Permissions and symlink"
    wait_step

    mark_completed "git_helper"
    success "Git Helper installed successfully! You can run it with: gith"
}

# ==============================================================================
# ==============================================================================
# SECTION 10: DOWNLOAD WALLPAPERS (FROM GITHUB)
# ==============================================================================

download_wallpapers() {
    section_header "SECTION 10: DOWNLOAD WALLPAPERS"

    local BG_DIR="$HOME/bg"
    local REPO_URL="https://github.com/pub00/pub-data.git"
    local TMP_DIR="/tmp/pub-data-bg-setup"

    msg "Step 1: Downloading repository to temporary directory"
    brief "Cloning repository to fetch the complete bg/ folder"
    run_cmd "rm -rf $TMP_DIR"
    run_cmd "git clone --depth 1 $REPO_URL $TMP_DIR"
    check_success "Repository download"
    wait_step

    msg "Step 2: Preparing destination directory ($BG_DIR)"
    run_cmd "mkdir -p $BG_DIR"
    check_success "Directory creation"
    wait_step

    msg "Step 3: Copying files and filtering out non-images"
    brief "Moving files to $BG_DIR and dynamically removing anything that isn't a valid image."
    
    if [ -d "$TMP_DIR/bg" ]; then
        # Copy everything from the bg folder to the destination
        run_cmd "cp -a $TMP_DIR/bg/* $BG_DIR/ 2>/dev/null || true"
        
        echo -e "${CYAN}Verifying files...${NC}"
        # Iterate over all files in the destination directory
        local found_images=false
        for f in "$BG_DIR"/*; do
            # Skip if it's not a regular file or if glob matches nothing
            [ ! -f "$f" ] && continue
            
            # Check mime-type using the 'file' command
            if ! file --mime-type "$f" | grep -q "image/"; then
                warn "Removed non-image file: $(basename "$f")"
                rm -f "$f"
            else
                found_images=true
            fi
        done
        
        if [ "$found_images" = false ]; then
            warn "No valid images found in the downloaded files."
        fi
        check_success "File verification and filtering"
    else
        error "Could not find 'bg' directory in the repository!"
    fi
    wait_step

    msg "Step 4: Cleaning up temporary files"
    run_cmd "rm -rf $TMP_DIR"
    
    mark_completed "wallpapers"
    success "Wallpapers downloaded and verified successfully in ~/bg/!"
}

# ==============================================================================
# SECTION 11: APPLY ARABIC SYSTEM FONT
# ==============================================================================

apply_arabic_font() {
    section_header "SECTION 11: APPLY ARABIC SYSTEM FONT"

    msg "Step 1: Checking if 'Noto Naskh Arabic' is installed"
    if ! fc-list | grep -iq "Noto Naskh Arabic"; then
        error "Font 'Noto Naskh Arabic' is not installed! Please run Option 4 (Fonts) first."
        return 1
    fi
    success "Font found."
    wait_step

    msg "Step 2: Creating fontconfig configuration"
    local FONTCONF_DIR="$HOME/.config/fontconfig"
    local FONTCONF_FILE="$FONTCONF_DIR/fonts.conf"

    run_cmd "mkdir -p $FONTCONF_DIR"
    
    echo -e "${CYAN}Creating $FONTCONF_FILE...${NC}"
    cat << 'EOF' > "$FONTCONF_FILE"
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>

  <!-- 
    المنطق هنا يعتمد على توجيه النظام عندما يطلب المتصفح أو الواجهة 
    خطاً عاماً (مثل sans-serif). نحن نجبر النظام على وضع خطنا 
    في أعلى قائمة الأولويات (prefer).
  -->

  <!-- الخط الافتراضي للواجهات والتصفح (Sans-serif) -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <!--  <family>Noto Kufi Arabic</family>  -->
      <!-- إذا أردت التجربة لاحقاً، استبدل السطر أعلاه بـ: -->
     <family>Noto Naskh Arabic</family>
    </prefer>
  </alias>

  <!-- الخط الافتراضي للنصوص الكلاسيكية (Serif) -->
  <alias>
    <family>serif</family>
    <prefer>
     <!--  <family>Noto Kufi Arabic</family>  -->
      <!-- ونفس الشيء هنا إذا أردت التبديل -->
      <family>Noto Naskh Arabic</family>
    </prefer>
  </alias>

</fontconfig>
EOF
    check_success "fonts.conf creation"
    wait_step

    msg "Step 3: Rebuilding font cache"
    run_cmd "fc-cache -f -v"
    check_success "Font cache rebuild"
    wait_step

    msg "Step 4: Verifying default Arabic font"
    run_cmd "fc-match :lang=ar"
    echo ""
    
    mark_completed "arabic_font"
    success "Arabic system font successfully set to Noto Naskh Arabic!"
}

# ==============================================================================
# SECTION 12: WEBCAM SETUP (v4l-utils + guvcview)
# ==============================================================================

setup_webcam() {
    section_header "SECTION 12: WEBCAM SETUP"

    # --- Step 1: Install camera utilities ---
    msg "Step 1: Installing Video4Linux utilities (v4l-utils)"
    brief "v4l-utils provides v4l2-ctl for diagnosing and controlling
       webcam devices under Linux (Video4Linux2 framework)."
    echo ""
    run_cmd "sudo pacman -S --noconfirm v4l-utils"
    check_success "v4l-utils installation"
    wait_step

    # --- Step 2: Detect camera devices ---
    msg "Step 2: Detecting webcam devices"
    brief "Listing all Video4Linux devices to identify your camera.
       A single camera may register multiple /dev/video* nodes
       (main stream, metadata, IR sensor, etc.)."
    echo ""
    if ls /dev/video* &>/dev/null; then
        success "Video devices found:"
        run_cmd "ls /dev/video*"
        echo ""
        run_cmd "v4l2-ctl --list-devices"
    else
        warn "No video devices found (/dev/video*). Camera may not be connected or recognized."
    fi
    wait_step

    # --- Step 3: Show primary camera formats ---
    msg "Step 3: Identifying primary camera stream"
    brief "Checking /dev/video0 for supported formats and resolutions.
       The device that lists MJPEG/YUYV formats with real resolutions
       is the actual video stream."
    echo ""
    if [ -e /dev/video0 ]; then
        run_cmd "v4l2-ctl --list-formats-ext -d /dev/video0"
    else
        warn "/dev/video0 not found. Skipping format check."
    fi
    wait_step

    # --- Step 4: Install guvcview ---
    msg "Step 4: Installing guvcview (GTK+ UVC Viewer)"
    brief "guvcview is a lightweight webcam viewer and capture tool.
       Lets you preview the camera feed, adjust settings, and take photos/videos."
    echo ""
    run_cmd "sudo pacman -S --noconfirm guvcview"
    check_success "guvcview installation"
    wait_step

    # --- Step 5: Privacy tips ---
    msg "Step 5: Camera Privacy & Monitoring Tips"
    echo ""
    echo -e "  ${BOLD}Check who is using the camera right now:${NC}"
    echo -e "  ${CYAN}  sudo fuser -v /dev/video0${NC}"
    echo ""
    echo -e "  ${BOLD}Quick test - open camera preview:${NC}"
    echo -e "  ${CYAN}  guvcview${NC}"
    echo ""
    echo -e "  ${BOLD}Disable camera temporarily (until reboot):${NC}"
    echo -e "  ${CYAN}  sudo modprobe -r uvcvideo${NC}"
    echo ""
    echo -e "  ${BOLD}Re-enable camera:${NC}"
    echo -e "  ${CYAN}  sudo modprobe uvcvideo${NC}"
    echo ""
    wait_step

    mark_completed "webcam"
    success "Webcam setup complete! Run 'guvcview' to preview your camera."
}

# ==============================================================================
# SECTION 13: VLC MEDIA PLAYER (HARDWARE ACCELERATED)
# ==============================================================================

install_vlc() {
    section_header "SECTION 13: VLC MEDIA PLAYER (HARDWARE ACCELERATED)"

    # --- Step 1: Detect GPU vendor ---
    msg "Step 1: Detecting GPU type for hardware acceleration"
    brief "Identifying whether your GPU is AMD or Intel to install
       the correct VA-API driver for hardware video decoding."
    echo ""

    local GPU_VENDOR="unknown"
    if lspci | grep -iE 'VGA|Display' | grep -iq 'AMD\|Radeon'; then
        GPU_VENDOR="amd"
        success "Detected AMD GPU"
    elif lspci | grep -iE 'VGA|Display' | grep -iq 'Intel'; then
        GPU_VENDOR="intel"
        success "Detected Intel GPU"
    else
        warn "Could not auto-detect GPU vendor. Will install base packages only."
    fi
    wait_step

    # --- Step 2: Install VA-API driver based on GPU ---
    msg "Step 2: Installing VA-API driver for hardware video decoding"
    echo ""

    case $GPU_VENDOR in
        amd)
            brief "AMD GPUs use Mesa's built-in VA-API support.
       libva-utils provides 'vainfo' to verify VA-API functionality.
       radeontop lets you monitor GPU activity (including VCN/video engine)."
            echo ""
            run_cmd "sudo pacman -S --noconfirm libva-utils radeontop"
            check_success "AMD VA-API utilities"
            ;;
        intel)
            brief "Intel GPUs need dedicated VA-API drivers:
       libva-intel-driver = older Intel GPUs (up to Coffee Lake).
       intel-media-driver = newer Intel GPUs (Broadwell+).
       libvdpau = VDPAU compatibility layer."
            echo ""
            run_cmd "sudo pacman -S --noconfirm libva-utils libva-intel-driver intel-media-driver libvdpau"
            check_success "Intel VA-API drivers"
            ;;
        *)
            brief "Installing libva-utils only. You may need to manually install
       the correct VA-API driver for your GPU."
            echo ""
            run_cmd "sudo pacman -S --noconfirm libva-utils"
            check_success "VA-API base utilities"
            ;;
    esac
    wait_step

    # --- Step 3: Verify VA-API ---
    msg "Step 3: Verifying VA-API support"
    brief "Running 'vainfo' to confirm hardware video decoding is active.
       You should see supported profiles like H.264, HEVC, VP9, AV1."
    echo ""
    run_cmd "vainfo"
    check_success "VA-API verification"
    wait_step

    # --- Step 4: Install VLC ---
    msg "Step 4: Installing VLC media player"
    brief "VLC is a free, open-source multimedia player that supports
       virtually every audio and video format."
    echo ""
    run_cmd "sudo pacman -S --noconfirm vlc"
    check_success "VLC installation"
    wait_step

    # --- Step 5: Install FFmpeg plugin for VA-API in VLC ---
    msg "Step 5: Installing VLC FFmpeg plugin (VA-API hardware decoding)"
    brief "vlc-plugin-ffmpeg contains the VA-API output plugins:
       libvaapi_drm_plugin.so and libvaapi_plugin.so
       Without this, VLC cannot use GPU hardware decoding."
    echo ""
    run_cmd "sudo pacman -S --noconfirm vlc-plugin-ffmpeg"
    check_success "VLC FFmpeg plugin"
    wait_step

    # --- Step 6: Configuration guide ---
    msg "Step 6: VLC Hardware Decoding Configuration"
    echo ""
    echo -e "  ${BOLD}To enable hardware decoding in VLC:${NC}"
    echo -e "  ${CYAN}  1. Open VLC${NC}"
    echo -e "  ${CYAN}  2. Tools → Preferences → Input / Codecs${NC}"
    echo -e "  ${CYAN}  3. Set 'Hardware-accelerated decoding' to:${NC}"
    echo -e "     ${GREEN}${BOLD}VA-API video decoder${NC}"
    echo -e "  ${CYAN}  4. Save → Close VLC completely → Reopen${NC}"
    echo ""
    echo -e "  ${BOLD}Verify it's working:${NC}"
    echo -e "  ${CYAN}  vlc -vvv video.mkv 2>&1 | grep -iE 'vaapi|hardware|decoder'${NC}"
    echo ""
    if [ "$GPU_VENDOR" = "amd" ]; then
        echo -e "  ${BOLD}Monitor AMD GPU activity during playback:${NC}"
        echo -e "  ${CYAN}  radeontop${NC}"
        echo -e "  ${DIM}  (Look for activity in Video/VCN while playing)${NC}"
        echo ""
    fi
    wait_step

    mark_completed "vlc"
    success "VLC installed with hardware acceleration! Enjoy your media."
}

# ==============================================================================
# MAIN LOOP
# ==============================================================================

while true; do
    show_menu
    case $opt in
        1) install_audio ;;
        2) install_amd_gpu ;;
        3) install_nvidia ;;
        4) install_fonts ;;
        5) install_tools ;;
        6) apply_xfce_configs ;;
        7) install_secure_manager ;;
        8) install_g_manager ;;
        9) install_git_helper ;;
        10) download_wallpapers ;;
        11) apply_arabic_font ;;
        12) setup_webcam ;;
        13) install_vlc ;;
        14) echo -e "\n${CYAN}Thanks for using arch-forge. Happy hacking!${NC}"; exit 0 ;;
        *) warn "Invalid option." ;;
    esac
    echo ""
    read -p "Press Enter to return to the menu..."
done
