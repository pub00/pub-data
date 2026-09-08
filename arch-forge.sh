#!/bin/bash

# ==============================================================================
# arch-forge - Post-Install Setup Forge for Arch Linux
# Forges your fresh Arch into a battle-ready workstation.
# Audio | GPU | Media | Virtualization | Desktop | Hardware | Tools | Gaming
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

    # ── Audio & Sound ──
    echo -e "  ${BLUE}${BOLD}🔊 AUDIO & SOUND${NC}"
    echo -e "  ${CYAN}1)${NC}  Install Audio (PipeWire + PulseAudio)$(get_status "audio")"
    echo -e "  ${CYAN}2)${NC}  Audio Production (Audacity + EasyEffects)$(get_status "audio_production")"

    echo -e "  ${MAGENTA}────────────────────────────────────────────${NC}"

    # ── GPU & Display ──
    echo -e "  ${BLUE}${BOLD}🎮 GPU & DISPLAY DRIVERS${NC}"
    echo -e "  ${CYAN}3)${NC}  Install AMD GPU Drivers (Radeon / Vulkan)$(get_status "amd_gpu")"
    echo -e "  ${CYAN}4)${NC}  Install NVIDIA GPU Driver (GTX970M / Legacy)$(get_status "nvidia")"

    echo -e "  ${MAGENTA}────────────────────────────────────────────${NC}"

    # ── Media & Production ──
    echo -e "  ${BLUE}${BOLD}🎬 MEDIA & PRODUCTION${NC}"
    echo -e "  ${CYAN}5)${NC}  Install VLC Media Player (Hardware Accelerated)$(get_status "vlc")"
    echo -e "  ${CYAN}6)${NC}  Install OBS Studio (Recording & Streaming)$(get_status "obs_studio")"
    echo -e "  ${CYAN}7)${NC}  Setup Webcam (v4l-utils + guvcview)$(get_status "webcam")"

    echo -e "  ${MAGENTA}────────────────────────────────────────────${NC}"

    # ── Virtualization ──
    echo -e "  ${BLUE}${BOLD}💻 VIRTUALIZATION${NC}"
    echo -e "  ${CYAN}8)${NC}  Setup QEMU / KVM (virt-manager)$(get_status "qemu_kvm")"

    echo -e "  ${MAGENTA}────────────────────────────────────────────${NC}"

    # ── Desktop & Customization ──
    echo -e "  ${BLUE}${BOLD}🖥  DESKTOP & CUSTOMIZATION${NC}"
    echo -e "  ${CYAN}9)${NC}  Apply XFCE Desktop Settings (from GitHub)$(get_status "xfce")"
    echo -e "  ${CYAN}10)${NC} Apply Arabic System Font (Noto Naskh Arabic)$(get_status "arabic_font")"
    echo -e "  ${CYAN}11)${NC} Download Wallpapers (from GitHub bg/ folder)$(get_status "wallpapers")"

    echo -e "  ${MAGENTA}────────────────────────────────────────────${NC}"

    # ── Hardware & Devices ──
    echo -e "  ${BLUE}${BOLD}🔌 HARDWARE & DEVICES${NC}"
    echo -e "  ${CYAN}12)${NC} Setup Bluetooth (bluez + bluetoothctl)$(get_status "bluetooth")"
    echo -e "  ${CYAN}13)${NC} Test Flash Drive (f3)$(get_status "f3_test")"

    echo -e "  ${MAGENTA}────────────────────────────────────────────${NC}"

    # ── Custom Tools ──
    echo -e "  ${BLUE}${BOLD}🛠  TOOLS & MANAGERS${NC}"
    echo -e "  ${CYAN}14)${NC} Install Useful Tools (Chrome, Firefox, Obsidian, etc.)$(get_status "tools")"
    echo -e "  ${CYAN}15)${NC} Install Secure Manager (from pub00/pub-data)$(get_status "secure_manager")"
    echo -e "  ${CYAN}16)${NC} Install G-Manager (from pub00/pub-data)$(get_status "g_manager")"
    echo -e "  ${CYAN}17)${NC} Install Git Helper (from pub00/pub-data)$(get_status "git_helper")"

    echo -e "  ${MAGENTA}────────────────────────────────────────────${NC}"

    # ── Gaming ──
    echo -e "  ${BLUE}${BOLD}🕹  GAMING${NC}"
    echo -e "  ${CYAN}18)${NC} Install Gaming Tools (Lutris, Wine, MangoHud)$(get_status "gaming")"

    echo -e "  ${MAGENTA}════════════════════════════════════════════${NC}"
    echo -e "  ${YELLOW}19)${NC} Quick Reference (Useful Commands)"
    echo -e "  ${RED}20)${NC} Exit"
    echo ""
    read -p "Select an option [1-20]: " opt
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
    smart_install "7zip" "pacman"
    smart_install "firefox" "pacman"
    smart_install "inkscape" "pacman"
    smart_install "htop" "pacman"
    smart_install "btop" "pacman"
    smart_install "fastfetch" "pacman"
    smart_install "dmidecode" "pacman"
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
        error "Font 'Noto Naskh Arabic' is not installed! Install it with: sudo pacman -S noto-fonts noto-fonts-extra"
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
# SECTION 14: BLUETOOTH SETUP (Full Stack)
# ==============================================================================

install_bluetooth() {
    section_header "SECTION 14: BLUETOOTH SETUP (Full Stack)"

    brief "This installs the complete Bluetooth stack for Arch Linux:
       bluez          = Linux Bluetooth protocol stack (core)
       bluez-utils    = CLI tools (bluetoothctl)
       bluez-obex     = OBEX protocol for file transfer (separated since 2024)
       blueman        = GTK Bluetooth manager (GUI for pairing, sending files)
       xdg-user-dirs  = ensures ~/Downloads, ~/Documents etc. exist for transfers"
    echo ""
    wait_step

    # --- Step 1: Check current state ---
    msg "Step 1: Checking currently installed Bluetooth packages"
    echo ""
    if pacman -Qs bluez &>/dev/null; then
        success "Some Bluetooth packages are already installed:"
        run_cmd "pacman -Qs bluez"
    else
        warn "No Bluetooth packages detected."
    fi
    if pacman -Qq blueman &>/dev/null 2>&1; then
        success "blueman is already installed."
    fi
    if pacman -Qq xdg-user-dirs &>/dev/null 2>&1; then
        success "xdg-user-dirs is already installed."
    fi
    wait_step

    # --- Step 2: Install core Bluetooth stack ---
    msg "Step 2: Installing core Bluetooth stack (bluez + bluez-utils)"
    brief "bluez = the official Linux Bluetooth protocol stack.
       bluez-utils = provides bluetoothctl and other CLI tools."
    echo ""
    if pacman -Qq bluez &>/dev/null 2>&1 && pacman -Qq bluez-utils &>/dev/null 2>&1; then
        success "bluez & bluez-utils are already installed. Skipping."
    else
        run_cmd "sudo pacman -S --needed --noconfirm bluez bluez-utils"
        check_success "bluez + bluez-utils installation"
    fi
    wait_step

    # --- Step 3: Install OBEX for file transfer ---
    msg "Step 3: Installing OBEX file transfer support (bluez-obex)"
    brief "Since 2024, Arch separated OBEX from the main bluez package.
       Without bluez-obex, you CANNOT send/receive files via Bluetooth.
       This is required for phone-to-PC file transfers."
    echo ""
    if pacman -Qq bluez-obex &>/dev/null 2>&1; then
        success "bluez-obex is already installed. Skipping."
    else
        run_cmd "sudo pacman -S --needed --noconfirm bluez-obex"
        check_success "bluez-obex installation"
    fi
    wait_step

    # --- Step 4: Install Blueman (GUI manager) ---
    msg "Step 4: Installing Blueman (GTK Bluetooth Manager)"
    brief "blueman provides a graphical interface for:
       - Pairing and connecting devices
       - Sending/receiving files with drag-and-drop
       - Managing trusted devices
       - System tray applet for quick access"
    echo ""
    if pacman -Qq blueman &>/dev/null 2>&1; then
        success "blueman is already installed. Skipping."
    else
        run_cmd "sudo pacman -S --needed --noconfirm blueman"
        check_success "blueman installation"
    fi
    wait_step

    # --- Step 5: Install xdg-user-dirs ---
    msg "Step 5: Ensuring standard user directories exist (xdg-user-dirs)"
    brief "xdg-user-dirs creates standard directories like ~/Downloads,
       ~/Documents, ~/Pictures etc. These are needed so Bluetooth
       file transfers have a proper destination folder."
    echo ""
    if pacman -Qq xdg-user-dirs &>/dev/null 2>&1; then
        success "xdg-user-dirs is already installed."
    else
        run_cmd "sudo pacman -S --needed --noconfirm xdg-user-dirs"
        check_success "xdg-user-dirs installation"
    fi
    run_cmd "xdg-user-dirs-update"
    success "User directories are ready."
    wait_step

    # --- Step 6: Enable bluetooth.service (system) ---
    msg "Step 6: Enabling bluetooth.service (system-wide)"
    brief "This enables the systemd bluetooth service so it starts
       automatically on every boot, and starts it immediately now."
    echo ""
    run_cmd "sudo systemctl enable --now bluetooth"
    check_success "bluetooth.service"
    wait_step

    # --- Step 7: Enable obex.service (user) ---
    msg "Step 7: Enabling obex.service (user session — for file transfers)"
    brief "obex.service runs under your user session and handles
       incoming/outgoing file transfers via Bluetooth OBEX protocol.
       Without this, sending files from phone to PC will fail silently."
    echo ""
    run_cmd "systemctl --user enable --now obex.service"
    check_success "obex.service"
    wait_step

    # --- Step 8: Verify all services ---
    msg "Step 8: Verifying all Bluetooth services"
    echo ""
    echo -e "  ${BOLD}bluetooth.service (system):${NC}"
    run_cmd "systemctl status bluetooth --no-pager -l"
    echo ""
    echo -e "  ${BOLD}obex.service (user):${NC}"
    run_cmd "systemctl --user status obex.service --no-pager -l"
    wait_step

    mark_completed "bluetooth"
    success "Bluetooth full stack installed and all services are running!"

    # --- Step 9: Command Reference ---
    msg "Step 9: Bluetooth Quick Reference"
    echo ""
    echo -e "  ${BOLD}Interactive mode:${NC}"
    echo -e "  ${CYAN}  bluetoothctl${NC}"
    echo ""
    echo -e "  ${BOLD}Power ON / OFF:${NC}"
    echo -e "  ${CYAN}  bluetoothctl power on${NC}"
    echo -e "  ${CYAN}  bluetoothctl power off${NC}"
    echo ""
    echo -e "  ${BOLD}Status:${NC}"
    echo -e "  ${CYAN}  bluetoothctl show${NC}            ${DIM}# Powered: yes/no${NC}"
    echo ""
    echo -e "  ${BOLD}Scan, Pair & Connect:${NC}"
    echo -e "  ${CYAN}  bluetoothctl scan on${NC}         ${DIM}# start scanning${NC}"
    echo -e "  ${CYAN}  bluetoothctl scan off${NC}        ${DIM}# stop scanning${NC}"
    echo -e "  ${CYAN}  bluetoothctl pair XX:XX:..${NC}"
    echo -e "  ${CYAN}  bluetoothctl trust XX:XX:..${NC}"
    echo -e "  ${CYAN}  bluetoothctl connect XX:XX:..${NC}"
    echo ""
    echo -e "  ${BOLD}Manage devices:${NC}"
    echo -e "  ${CYAN}  bluetoothctl devices${NC}         ${DIM}# list known devices${NC}"
    echo -e "  ${CYAN}  bluetoothctl info XX:XX:..${NC}   ${DIM}# Paired/Trusted/Connected${NC}"
    echo -e "  ${CYAN}  bluetoothctl disconnect XX:XX:..${NC}"
    echo -e "  ${CYAN}  bluetoothctl remove XX:XX:..${NC}  ${DIM}# unpair device${NC}"
    echo ""
    echo -e "  ${BOLD}File transfer (OBEX):${NC}"
    echo -e "  ${CYAN}  bluetooth-sendto${NC}             ${DIM}# GUI send file dialog${NC}"
    echo -e "  ${CYAN}  blueman-manager${NC}              ${DIM}# full GUI manager${NC}"
    echo -e "  ${CYAN}  blueman-sendto${NC}               ${DIM}# send file via Blueman${NC}"
    echo ""
    echo -e "  ${BOLD}Services:${NC}"
    echo -e "  ${CYAN}  systemctl status bluetooth${NC}                  ${DIM}# core service${NC}"
    echo -e "  ${CYAN}  systemctl --user status obex.service${NC}        ${DIM}# file transfer${NC}"
    echo -e "  ${CYAN}  sudo systemctl restart bluetooth${NC}"
    echo -e "  ${CYAN}  systemctl --user restart obex.service${NC}"
    echo ""
    echo -e "  ${YELLOW}TIP:${NC} ${DIM}View these commands anytime → Main Menu → Quick Reference${NC}"
    echo ""
    wait_step

    success "Bluetooth setup complete! Use 'blueman-manager' for GUI or 'bluetoothctl' for CLI."
}

# ==============================================================================
# SECTION 15: TEST FLASH DRIVE (f3)
# ==============================================================================

test_flash_drive() {
    section_header "SECTION 15: TEST FLASH DRIVE (f3)"

    ensure_yay

    msg "Step 1: Installing f3 (Fight Flash Fraud)"
    if pacman -Qq f3 &>/dev/null 2>&1; then
        success "f3 is already installed."
    else
        run_cmd "yay -S --noconfirm f3"
        check_success "f3 installation"
    fi
    wait_step

    msg "Step 2: How to use f3 tools"
    echo ""
    echo -e "  ${BOLD}To test a flash drive, follow these steps:${NC}"
    echo -e "  ${RED}WARNING: f3probe completely destroys data! Make sure the drive is empty or backed up!${NC}"
    echo ""
    echo -e "  ${CYAN}1. Destructive probing (tests speed and capacity, DESTROYS DATA):${NC}"
    echo -e "     ${BOLD}sudo f3probe --destructive /dev/sdX${NC}"
    echo -e "     ${DIM}(Replace /dev/sdX with your actual block device, e.g., /dev/sdb)${NC}"
    echo ""
    echo -e "  ${CYAN}2. Write test data to the drive (requires mounted drive):${NC}"
    echo -e "     ${BOLD}f3write /path/to/mountpoint${NC}"
    echo -e "     ${DIM}(This will fill the drive with .h2w files to test actual capacity)${NC}"
    echo ""
    echo -e "  ${CYAN}3. Read and verify the test data:${NC}"
    echo -e "     ${BOLD}f3read /path/to/mountpoint${NC}"
    echo -e "     ${DIM}(This will verify the written files. If there are corrupted files, the drive is fake or failing)${NC}"
    echo ""
    wait_step

    mark_completed "f3_test"
}

# ==============================================================================
# SECTION 16: INSTALL GAMING TOOLS (Lutris, Wine, MangoHud)
# ==============================================================================

install_gaming_tools() {
    section_header "SECTION 16: INSTALL GAMING TOOLS"

    msg "Step 1: Installing Lutris, Wine, Winetricks, MangoHud"
    run_cmd "sudo pacman -S --noconfirm lutris wine winetricks mangohud"
    check_success "Gaming tools installation"
    wait_step

    msg "Step 2: Configuration Information"
    echo ""
    echo -e "  ${BOLD}To enable FPS counter MangoHud in your games (SYSTEM OPTIONS in configure of the game):${NC}"
    echo -e "  ${CYAN}1. Open game configuration in Lutris/Steam${NC}"
    echo -e "  ${CYAN}2. Go to System Options${NC}"
    echo -e "  ${CYAN}3. Add the following Environment Variable:${NC}"
    echo -e "     ${GREEN}MANGOHUD_CONFIG = fps_limit=60,no_display${NC}"
    echo -e "  ${CYAN}4. Make sure 'FPS counter (MangoHud)' is enabled/toggled ON.${NC}"
    echo ""
    wait_step

    mark_completed "gaming"
}

# ==============================================================================
# SECTION 17: QEMU / KVM VIRTUALIZATION SETUP
# ==============================================================================

install_qemu_kvm() {
    section_header "SECTION 17: QEMU / KVM VIRTUALIZATION SETUP"

    # --- Step 1: System update ---
    msg "Step 1: Updating the system"
    brief "Ensuring all packages are up-to-date before installing virtualization tools."
    echo ""
    run_cmd "sudo pacman -Syu --noconfirm"
    check_success "System update"
    wait_step

    # --- Step 2: Install virtualization packages ---
    msg "Step 2: Installing QEMU, libvirt, and virt-manager"
    brief "qemu-desktop     = Main QEMU virtualization package.
       libvirt          = Virtualization management daemon.
       virt-manager     = GUI manager for virtual machines.
       dnsmasq          = Provides DHCP/NAT networking for VMs.
       iptables-nft     = Firewall backend required by libvirt networking.
       dmidecode        = Lets guests read hardware/system information."
    echo ""
    run_cmd "sudo pacman -S --noconfirm qemu-desktop libvirt virt-manager dnsmasq iptables-nft dmidecode"
    check_success "Virtualization packages installation"
    wait_step

    # --- Step 3: Add user to libvirt group ---
    msg "Step 3: Adding your user to the libvirt group"
    brief "Allows your user account to manage virtual machines
       without using root every time."
    echo ""
    run_cmd "sudo usermod -aG libvirt $USER"
    check_success "User added to libvirt group"
    wait_step

    # --- Step 4: Enable and start libvirtd ---
    msg "Step 4: Enabling and starting libvirtd service"
    brief "Starts the virtualization daemon now and automatically on boot."
    echo ""
    run_cmd "sudo systemctl enable --now libvirtd.service"
    check_success "libvirtd service"
    wait_step

    # --- Step 5: REBOOT WARNING ---
    msg "Step 5: IMPORTANT — Reboot Required!"
    echo ""
    echo -e "  ${RED}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${RED}${BOLD}║  ⚠  YOU MUST REBOOT BEFORE CONTINUING TO STEP 6!       ║${NC}"
    echo -e "  ${RED}${BOLD}║                                                          ║${NC}"
    echo -e "  ${RED}${BOLD}║  Your user is NOT yet part of the libvirt group.         ║${NC}"
    echo -e "  ${RED}${BOLD}║  Without rebooting, 'virsh net-start default' will FAIL  ║${NC}"
    echo -e "  ${RED}${BOLD}║  with: 'Unable to create bridge virbr0'                 ║${NC}"
    echo -e "  ${RED}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${YELLOW}After rebooting, run arch-forge again and select this option.${NC}"
    echo -e "  ${YELLOW}It will detect the reboot and continue from Step 6 automatically.${NC}"
    echo ""

    # Check if user is already in the libvirt group (post-reboot)
    if id -nG "$USER" | grep -qw "libvirt"; then
        success "User is already in the libvirt group. Continuing..."
    else
        warn "Reboot now, then re-run this option to finish setup."
        echo ""
        read -p "Do you want to reboot now? (y/n): " reboot_choice
        if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
            reboot
        fi
        return 0
    fi
    wait_step

    # --- Step 6: Start the default virtual network ---
    msg "Step 6: Starting the default virtual network"
    brief "Creates the default NAT network for virtual machines.
       VMs will get internet access through your host machine."
    echo ""
    run_cmd "sudo virsh net-start default"
    check_success "Default network start"
    wait_step

    # --- Step 7: Enable autostart for the network ---
    msg "Step 7: Enabling autostart for the default network"
    brief "Automatically starts the default VM network after every reboot."
    echo ""
    run_cmd "sudo virsh net-autostart default"
    check_success "Network autostart"
    wait_step

    mark_completed "qemu_kvm"
    success "QEMU/KVM virtualization is fully configured!"
    echo ""
    echo -e "  ${BOLD}Launch Virtual Machine Manager:${NC}"
    echo -e "  ${CYAN}  virt-manager${NC}"
    echo ""
    echo -e "  ${BOLD}List running VMs:${NC}"
    echo -e "  ${CYAN}  virsh list --all${NC}"
    echo ""
    echo -e "  ${BOLD}Check network status:${NC}"
    echo -e "  ${CYAN}  virsh net-list --all${NC}"
    echo ""
    wait_step
}

# ==============================================================================
# SECTION 18: OBS STUDIO (Screen Recording & Streaming)
# ==============================================================================

install_obs_studio() {
    section_header "SECTION 18: OBS STUDIO INSTALLATION"

    # --- Step 1: System update ---
    msg "Step 1: Updating the system"
    run_cmd "sudo pacman -Syu --noconfirm"
    check_success "System update"
    wait_step

    # --- Step 2: Install OBS Studio ---
    msg "Step 2: Installing OBS Studio"
    brief "OBS Studio is a free and open-source software for video recording
       and live streaming. Supports screen capture, webcam, and audio mixing."
    echo ""
    run_cmd "sudo pacman -S --noconfirm obs-studio"
    check_success "OBS Studio installation"
    wait_step

    mark_completed "obs_studio"
    success "OBS Studio installed successfully!"
    echo ""
    echo -e "  ${BOLD}Launch OBS Studio:${NC}"
    echo -e "  ${CYAN}  obs${NC}"
    echo ""
    wait_step
}

# ==============================================================================
# SECTION 19: AUDIO PRODUCTION (Audacity + EasyEffects)
# ==============================================================================

install_audio_production() {
    section_header "SECTION 19: AUDIO PRODUCTION TOOLS"

    # --- Step 1: System update ---
    msg "Step 1: Updating the system"
    run_cmd "sudo pacman -Syu --noconfirm"
    check_success "System update"
    wait_step

    # --- Step 2: Install Audacity ---
    msg "Step 2: Installing Audacity"
    brief "Audacity is a free, open-source audio editor and recorder.
       Supports multi-track editing, effects, noise reduction, and more."
    echo ""
    run_cmd "sudo pacman -S --noconfirm audacity"
    check_success "Audacity installation"
    wait_step

    # --- Step 3: Install EasyEffects ---
    msg "Step 3: Installing EasyEffects"
    brief "EasyEffects is a PipeWire-based audio effects tool.
       Provides equalizer, compressor, noise gate, echo canceller,
       and many other real-time audio effects for your microphone and speakers."
    echo ""
    run_cmd "sudo pacman -S --noconfirm easyeffects"
    check_success "EasyEffects installation"
    wait_step

    mark_completed "audio_production"
    success "Audio production tools installed!"
    echo ""
    echo -e "  ${BOLD}Launch Audacity:${NC}"
    echo -e "  ${CYAN}  audacity${NC}"
    echo ""
    echo -e "  ${BOLD}Launch EasyEffects:${NC}"
    echo -e "  ${CYAN}  easyeffects${NC}"
    echo ""
    wait_step
}

# ==============================================================================
# SECTION 20: QUICK REFERENCE (Useful Commands)
# ==============================================================================

show_quick_reference() {
    section_header "QUICK REFERENCE :: Useful Commands"

    # ── Bluetooth ──
    echo -e "  ${BLUE}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BLUE}${BOLD}│${NC}  ${BOLD}🔵 BLUETOOTH${NC}                                          ${BLUE}${BOLD}│${NC}"
    echo -e "  ${BLUE}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e "  ${CYAN}bluetoothctl power on${NC}              ${DIM}# turn on${NC}"
    echo -e "  ${CYAN}bluetoothctl power off${NC}             ${DIM}# turn off${NC}"
    echo -e "  ${CYAN}bluetoothctl show${NC}                  ${DIM}# controller status${NC}"
    echo -e "  ${CYAN}bluetoothctl scan on${NC}               ${DIM}# discover devices${NC}"
    echo -e "  ${CYAN}bluetoothctl scan off${NC}              ${DIM}# stop scanning${NC}"
    echo -e "  ${CYAN}bluetoothctl devices${NC}               ${DIM}# list known devices${NC}"
    echo -e "  ${CYAN}bluetoothctl pair XX:XX:..${NC}         ${DIM}# pair${NC}"
    echo -e "  ${CYAN}bluetoothctl trust XX:XX:..${NC}        ${DIM}# trust${NC}"
    echo -e "  ${CYAN}bluetoothctl connect XX:XX:..${NC}      ${DIM}# connect${NC}"
    echo -e "  ${CYAN}bluetoothctl disconnect XX:XX:..${NC}   ${DIM}# disconnect${NC}"
    echo -e "  ${CYAN}bluetoothctl info XX:XX:..${NC}         ${DIM}# device details${NC}"
    echo -e "  ${CYAN}bluetoothctl remove XX:XX:..${NC}       ${DIM}# unpair/forget${NC}"
    echo -e "  ${MAGENTA}  ── File Transfer (OBEX) ──${NC}"
    echo -e "  ${CYAN}blueman-manager${NC}                    ${DIM}# full GUI manager${NC}"
    echo -e "  ${CYAN}blueman-sendto${NC}                     ${DIM}# send file via GUI${NC}"
    echo -e "  ${CYAN}bluetooth-sendto${NC}                   ${DIM}# GNOME send dialog${NC}"
    echo -e "  ${MAGENTA}  ── Services ──${NC}"
    echo -e "  ${CYAN}systemctl status bluetooth${NC}         ${DIM}# core BT service${NC}"
    echo -e "  ${CYAN}systemctl --user status obex${NC}       ${DIM}# file transfer service${NC}"
    echo -e "  ${CYAN}systemctl --user restart obex${NC}      ${DIM}# restart OBEX${NC}"
    echo ""

    # ── Audio ──
    echo -e "  ${BLUE}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BLUE}${BOLD}│${NC}  ${BOLD}🔊 AUDIO (PipeWire)${NC}                                   ${BLUE}${BOLD}│${NC}"
    echo -e "  ${BLUE}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e "  ${CYAN}pactl info${NC}                         ${DIM}# audio server info${NC}"
    echo -e "  ${CYAN}pactl list sinks short${NC}             ${DIM}# list output devices${NC}"
    echo -e "  ${CYAN}pactl list sources short${NC}           ${DIM}# list input devices (mic)${NC}"
    echo -e "  ${CYAN}pactl set-sink-volume @DEFAULT_SINK@ 80%${NC}  ${DIM}# set volume${NC}"
    echo -e "  ${CYAN}pactl set-sink-mute @DEFAULT_SINK@ toggle${NC} ${DIM}# mute/unmute${NC}"
    echo -e "  ${CYAN}pavucontrol${NC}                        ${DIM}# GUI volume mixer${NC}"
    echo -e "  ${CYAN}alsamixer${NC}                          ${DIM}# TUI mixer${NC}"
    echo ""

    # ── GPU ──
    echo -e "  ${BLUE}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BLUE}${BOLD}│${NC}  ${BOLD}🎮 GPU & DISPLAY${NC}                                      ${BLUE}${BOLD}│${NC}"
    echo -e "  ${BLUE}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e "  ${CYAN}lspci -k | grep -A2 VGA${NC}            ${DIM}# GPU info & driver${NC}"
    echo -e "  ${CYAN}glxinfo | grep 'OpenGL renderer'${NC}   ${DIM}# active renderer${NC}"
    echo -e "  ${CYAN}vainfo${NC}                             ${DIM}# VA-API (hw video decode)${NC}"
    echo -e "  ${CYAN}radeontop${NC}                          ${DIM}# AMD GPU monitor${NC}"
    echo -e "  ${CYAN}nvidia-smi${NC}                         ${DIM}# NVIDIA GPU monitor${NC}"
    echo -e "  ${CYAN}xrandr${NC}                             ${DIM}# display/resolution info${NC}"
    echo ""

    # ── Webcam ──
    echo -e "  ${BLUE}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BLUE}${BOLD}│${NC}  ${BOLD}📷 WEBCAM${NC}                                             ${BLUE}${BOLD}│${NC}"
    echo -e "  ${BLUE}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e "  ${CYAN}v4l2-ctl --list-devices${NC}            ${DIM}# list camera devices${NC}"
    echo -e "  ${CYAN}guvcview${NC}                           ${DIM}# open camera preview${NC}"
    echo -e "  ${CYAN}sudo fuser -v /dev/video0${NC}          ${DIM}# who is using camera?${NC}"
    echo -e "  ${CYAN}sudo modprobe -r uvcvideo${NC}          ${DIM}# disable camera${NC}"
    echo -e "  ${CYAN}sudo modprobe uvcvideo${NC}             ${DIM}# re-enable camera${NC}"
    echo ""

    # ── System ──
    echo -e "  ${BLUE}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BLUE}${BOLD}│${NC}  ${BOLD}🖥  SYSTEM${NC}                                             ${BLUE}${BOLD}│${NC}"
    echo -e "  ${BLUE}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo -e "  ${CYAN}sudo pacman -Syu${NC}                   ${DIM}# full system update${NC}"
    echo -e "  ${CYAN}pacman -Qs <package>${NC}              ${DIM}# search installed pkgs${NC}"
    echo -e "  ${CYAN}pacman -Qi <package>${NC}              ${DIM}# package info${NC}"
    echo -e "  ${CYAN}systemctl status <service>${NC}        ${DIM}# check service status${NC}"
    echo -e "  ${CYAN}systemctl restart <service>${NC}       ${DIM}# restart a service${NC}"
    echo -e "  ${CYAN}journalctl -xe${NC}                    ${DIM}# recent system logs${NC}"
    echo -e "  ${CYAN}htop${NC}                               ${DIM}# process monitor${NC}"
    echo -e "  ${CYAN}fc-list | grep <font>${NC}             ${DIM}# check installed fonts${NC}"
    echo -e "  ${CYAN}xfce4-panel -r${NC}                    ${DIM}# restart XFCE panel${NC}"
    echo ""
    wait_step
}

# ==============================================================================
# MAIN LOOP
# ==============================================================================

while true; do
    show_menu
    case $opt in
        # 🔊 Audio & Sound
        1) install_audio ;;
        2) install_audio_production ;;
        # 🎮 GPU & Display
        3) install_amd_gpu ;;
        4) install_nvidia ;;
        # 🎬 Media & Production
        5) install_vlc ;;
        6) install_obs_studio ;;
        7) setup_webcam ;;
        # 💻 Virtualization
        8) install_qemu_kvm ;;
        # 🖥 Desktop & Customization
        9) apply_xfce_configs ;;
        10) apply_arabic_font ;;
        11) download_wallpapers ;;
        # 🔌 Hardware & Devices
        12) install_bluetooth ;;
        13) test_flash_drive ;;
        # 🛠 Tools & Managers
        14) install_tools ;;
        15) install_secure_manager ;;
        16) install_g_manager ;;
        17) install_git_helper ;;
        # 🕹 Gaming
        18) install_gaming_tools ;;
        # ───
        19) show_quick_reference ;;
        20) echo -e "\n${CYAN}Thanks for using arch-forge. Happy hacking!${NC}"; exit 0 ;;
        *) warn "Invalid option." ;;
    esac
    echo ""
    read -p "Press Enter to return to the menu..."
done
