#!/bin/bash
# --- Colors & UI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# --- Helper Functions ---
msg() {
    echo -e "\n${BLUE}${BOLD}[INFO]${NC} ${CYAN}$1${NC}"
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

wait_step() {
    if [[ "$INSTALL_MODE" == "2" ]]; then
        return 0
    fi
    echo -e "\n${YELLOW}>> Press [Enter] to continue to the next step...${NC}"
    read -r
}

ask_password() {
    local prompt=$1
    local var_name=$2
    local pass1 pass2
    while true; do
        read -s -p "$(echo -e "${BOLD}${prompt}${NC}: ")" pass1
        echo ""
        read -s -p "$(echo -e "${BOLD}Confirm ${prompt}${NC}: ")" pass2
        echo ""
        if [[ "$pass1" == "$pass2" ]]; then
            eval "$var_name=\"$pass1\""
            break
        else
            echo -e "${RED}Passwords do not match. Please try again.${NC}"
        fi
    done
}

ask_input() {
    local prompt=$1
    local default=$2
    local var_name=$3
    read -p "$(echo -e "${BOLD}${prompt}${NC} ${YELLOW}[Default: ${default}]${NC}: ")" input
    if [[ -z "$input" ]]; then
        eval "$var_name=\"$default\""
    else
        eval "$var_name=\"$input\""
    fi
}

check_success() {
    if [ $? -eq 0 ]; then
        success "$1 finished successfully."
    else
        warn "$1 failed."
        echo -e "Do you want to [r]etry, [i]gnore, or [a]bort?"
        read -p "(r/i/a): " choice
        case $choice in
            r) return 1 ;;
            i) return 0 ;;
            *) exit 1 ;;
        esac
    fi
}

preview_file() {
    if [[ "$INSTALL_MODE" == "2" ]]; then
        return 0
    fi
    local file=$1
    local title=$2
    local brief=$3
    echo -e "\n${BOLD}--- EDUCATIONAL BRIEF: ${title} ---${NC}"
    echo -e "${CYAN}${brief}${NC}"

    # Only show content for fstab as requested
    if [[ "$file" == *"fstab"* ]] && [[ -f "$file" ]]; then
        echo -e "\n${YELLOW}Current content of ${file}:${NC}"
        cat "$file"
    fi
}

preview_after() {
    if [[ "$INSTALL_MODE" == "2" ]]; then
        return 0
    fi
    local file=$1
    echo -e "${GREEN}Task applied to: ${file}${NC}"
    if [[ "$file" == *"fstab"* ]] && [[ -f "$file" ]]; then
        echo -e "\n${YELLOW}New content of ${file}:${NC}"
        cat "$file"
    fi
}

# --- Initialization ---
clear
echo -e "${BLUE}${BOLD}"
echo "----------------------------------------------------"
echo "        WELCOME TO THE ARCH LINUX INSTALLER         "
echo "----------------------------------------------------"
echo -e "${NC}"

# Check for internet
if ! ping -c 1 google.com &> /dev/null; then
    error "No internet connection detected. Please connect and try again."
fi

echo -e "${BOLD}Select Installation Mode:${NC}"
echo -e "  ${CYAN}1)${NC} Interactive Learning Mode (goes step-by-step, explains command briefs, pauses)"
echo -e "  ${CYAN}2)${NC} Fast Automated Mode (collects all info upfront, previews passwords, runs without pause)"
echo ""
ask_input "Choose Mode" "1" "INSTALL_MODE"

# --- CPU Microcode Selection ---
echo ""
echo -e "${BOLD}Select your CPU type:${NC}"
echo -e "  ${CYAN}1)${NC} Intel (intel-ucode)"
echo -e "  ${CYAN}2)${NC} AMD (amd-ucode)"
ask_input "Choose CPU type" "1" "CPU_TYPE"

if [[ "$CPU_TYPE" == "2" ]]; then
    UCODE_PKG="amd-ucode"
else
    UCODE_PKG="intel-ucode"
fi
echo -e "${GREEN}Selected CPU Microcode: ${BOLD}${UCODE_PKG}${NC}"

# --- Swap & Hibernate Selection ---
echo ""
echo -e "${BOLD}Configure Swapfile for Hibernate (Suspend-to-Disk) & Memory Extension:${NC}"
echo -e "  ${CYAN}1)${NC} 8 GB Swapfile (Recommended for 8GB-16GB RAM)"
echo -e "  ${CYAN}2)${NC} 16 GB Swapfile (Recommended for 16GB-32GB RAM & Full Hibernate)"
echo -e "  ${CYAN}3)${NC} Custom Size (GB)"
echo -e "  ${CYAN}4)${NC} No Swap (0 GB)"
ask_input "Choose Swap Option" "1" "SWAP_CHOICE"

case "$SWAP_CHOICE" in
    1) SWAP_SIZE=8 ;;
    2) SWAP_SIZE=16 ;;
    3) ask_input "Enter Swapfile size in GB" "8" "SWAP_SIZE" ;;
    4|*) SWAP_SIZE=0 ;;
esac
echo -e "${GREEN}Selected Swap Size: ${BOLD}${SWAP_SIZE} GB${NC}"

if [[ "$INSTALL_MODE" == "2" ]]; then
    clear
    echo -e "${BLUE}${BOLD}====================================================================${NC}"
    echo -e "         ${BOLD}FAST AUTOMATED MODE - DISK & SYSTEM CONFIGURATION${NC}"
    echo -e "${BLUE}${BOLD}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}📌 Partition Requirements & Guidelines:${NC}"
    echo -e "  • ${BOLD}EFI Partition:${NC}  Must be ${CYAN}FAT32 (EFI System)${NC} — ${GREEN}Recommended: 1 GB (1024M)${NC}"
    echo -e "                    ${YELLOW}Warning:${NC} If reusing a 100MB EFI, Arch kernels may fill it!"
    echo -e "  • ${BOLD}Root Partition:${NC} Must be ${CYAN}Linux filesystem${NC} — Will be formatted with ext4"
    echo -e "  • ${BOLD}Swapfile:${NC}       ${GREEN}${SWAP_SIZE} GB Swapfile${NC} will be created automatically"
    echo -e "${BLUE}${BOLD}--------------------------------------------------------------------${NC}"
    echo ""
    echo "Available block devices:"
    run_cmd "lsblk -d -n -o NAME,SIZE,MODEL | grep -v 'loop'"
    echo ""

    # Auto-detect default device
    DEFAULT_DEV=$(lsblk -d -n -b -o NAME,SIZE | grep -v 'loop' | sort -k2 -n -r | head -1 | awk '{print $1}')
    [[ -z "$DEFAULT_DEV" ]] && DEFAULT_DEV="sda"

    ask_input "Enter target device name (e.g., sda, nvme0n1)" "$DEFAULT_DEV" "TARGET_DEV"
    TARGET_PATH="/dev/${TARGET_DEV}"
    if [[ ! -b "$TARGET_PATH" ]]; then
        error "Device $TARGET_PATH not found."
    fi

    if [[ "$TARGET_DEV" == nvme* ]] || [[ "$TARGET_DEV" == mmcblk* ]]; then
        DEF_EFI="/dev/${TARGET_DEV}p1"
        DEF_ROOT="/dev/${TARGET_DEV}p2"
    else
        DEF_EFI="/dev/${TARGET_DEV}1"
        DEF_ROOT="/dev/${TARGET_DEV}2"
    fi

    echo -e "\n${BOLD}Do you need to open cfdisk to partition the disk now?${NC}"
    echo "  1) No  - Partitions are already created"
    echo "  2) Yes - Open cfdisk now to partition"
    ask_input "Choose option" "1" "RUN_CFDISK_FAST"

    if [[ "$RUN_CFDISK_FAST" == "2" ]]; then
        run_cmd "cfdisk $TARGET_PATH"
    fi

    echo -e "\n${BOLD}Is this a dual-boot installation (using an existing EFI partition)?${NC}"
    echo "  1) Yes (Dual-boot - preserve existing partitions)"
    echo "  2) No (Fresh Installation - WILL WIPE TARGET PARTITIONS)"
    ask_input "Choose type" "2" "INSTALL_TYPE"

    ask_input "EFI Partition path" "$DEF_EFI" "EFI_PART"
    ask_input "Root Partition path" "$DEF_ROOT" "ROOT_PART"
    BOOT_MOUNT="/mnt/boot/efi"

    ask_input "PC Hostname" "citadel" "PC_NAME"
    ask_input "Bootloader ID" "GRUB_Arch" "BOOTLOADER_ID"

    echo ""
    ask_password "Root User Password" "ROOT_PASS"

    ask_input "New Username" "user" "USER_NAME"

    echo ""
    ask_password "User Password" "USER_PASS"

    # Confirmation window
    clear
    echo -e "${BLUE}${BOLD}============================================================${NC}"
    echo -e "              ${BOLD}CONFIRM YOUR INSTALLATION DETAILS${NC}"
    echo -e "${BLUE}${BOLD}============================================================${NC}"
    echo -e "  ${BOLD}Target Device:${NC}      /dev/${TARGET_DEV}"
    echo -e "  ${BOLD}Install Type:${NC}       $( [[ "$INSTALL_TYPE" == "1" ]] && echo "Dual-Boot" || echo "Fresh (WILL WIPE TARGETS)" )"
    echo -e "  ${BOLD}EFI Partition:${NC}      ${EFI_PART}"
    echo -e "  ${BOLD}Root Partition:${NC}     ${ROOT_PART}"
    echo -e "  ${BOLD}CPU Microcode:${NC}      ${UCODE_PKG}"
    echo -e "  ${BOLD}Swapfile Size:${NC}      ${SWAP_SIZE} GB $( [[ "$SWAP_SIZE" -gt 0 ]] && echo "(Hibernate Enabled)" || echo "(No Swap)" )"
    echo -e "  ${BOLD}PC Hostname:${NC}        ${PC_NAME}"
    echo -e "  ${BOLD}Bootloader ID:${NC}      ${BOOTLOADER_ID}"
    echo -e "  ${BOLD}Root Password:${NC}      ${ROOT_PASS}"
    echo -e "  ${BOLD}Username:${NC}           ${USER_NAME}"
    echo -e "  ${BOLD}User Password:${NC}      ${USER_PASS}"
    echo -e "${BLUE}${BOLD}============================================================${NC}"
    echo -e "${RED}${BOLD}WARNING: All operations will be performed quickly without pause!${NC}"
    echo ""
    read -p "Are these details correct? Type 'yes' to proceed: " confirm_all
    if [[ "$confirm_all" != "yes" ]]; then
        error "Installation aborted by user."
    fi
fi

# ==============================================================================
msg "Step 1: Partitioning"

if [[ "$INSTALL_MODE" == "2" ]]; then
    msg "Using pre-configured partition layout:"
    echo "EFI Partition:  $EFI_PART"
    echo "Root Partition: $ROOT_PART"

    if [[ "$INSTALL_TYPE" == "2" ]]; then
        msg "Formatting EFI partition to FAT32..."
        run_cmd "mkfs.fat -F32 $EFI_PART" || error "Formatting EFI failed."
    fi
else
    # Interactive Mode
    echo "Available block devices:"
    run_cmd "lsblk -d -n -o NAME,SIZE,MODEL | grep -v 'loop'"

    DEFAULT_DEV=$(lsblk -d -n -b -o NAME,SIZE | grep -v 'loop' | sort -k2 -n -r | head -1 | awk '{print $1}')
    [[ -z "$DEFAULT_DEV" ]] && DEFAULT_DEV="sda"

    ask_input "Enter device name only (e.g., sda, nvme0n1) — do NOT include /dev/" "$DEFAULT_DEV" "TARGET_DEV"
    TARGET_PATH="/dev/${TARGET_DEV}"

    if [[ ! -b "$TARGET_PATH" ]]; then
        error "Device $TARGET_PATH not found."
    fi

    if [[ "$TARGET_DEV" == nvme* ]] || [[ "$TARGET_DEV" == mmcblk* ]]; then
        DEF_EFI="/dev/${TARGET_DEV}p1"
        DEF_ROOT="/dev/${TARGET_DEV}p2"
    else
        DEF_EFI="/dev/${TARGET_DEV}p1"
        DEF_ROOT="/dev/${TARGET_DEV}p2"
    fi

    echo -e "\n${BOLD}Is this a dual-boot installation (using an existing EFI partition)?${NC}"
    echo "  1) Yes (Dual-boot)"
    echo "  2) No (Fresh Installation - WILL WIPE DISK)"
    ask_input "Choose an option" "2" "INSTALL_TYPE"

    clear
    echo -e "${BLUE}${BOLD}====================================================================${NC}"
    echo -e "             ${BOLD}DISK PARTITIONING GUIDE & INSTRUCTIONS (cfdisk)${NC}"
    echo -e "${BLUE}${BOLD}====================================================================${NC}"
    echo -e "${YELLOW}${BOLD}📌 Important Guidelines Before Opening cfdisk:${NC}\n"
    echo -e "  ${BOLD}1. EFI Partition:${NC}"
    echo -e "     • Type: ${CYAN}EFI System${NC}"
    echo -e "     • Recommended Size: ${GREEN}At least 1 GB (1024M)${NC}"
    echo -e "     • ${YELLOW}NOTE FOR DUAL-BOOT / RE-USED DISKS:${NC}"
    echo -e "       If your existing EFI partition is only 100MB-260MB, consider deleting it"
    echo -e "       and creating a 1GB EFI partition (if possible), because Arch Linux kernels"
    echo -e "       and initramfs images can easily fill up small 100MB EFI partitions over time!"
    echo ""
    echo -e "  ${BOLD}2. Root Partition:${NC}"
    echo -e "     • Type: ${CYAN}Linux filesystem${NC}"
    echo -e "     • Size: ${GREEN}All remaining space${NC} (or desired size)"
    echo -e "     • Will be formatted with ext4."
    echo ""
    echo -e "  ${BOLD}3. Swap Partition:${NC}"
    echo -e "     • ${GREEN}No separate Swap partition is required in cfdisk!${NC}"
    echo -e "       The installer will automatically create a Swapfile inside"
    echo -e "       the system for Hibernate & RAM extension (${SWAP_SIZE} GB)."
    echo -e "${BLUE}${BOLD}====================================================================${NC}"
    echo ""
    read -p "$(echo -e "${YELLOW}Are you ready to launch cfdisk? Press [Enter] to open cfdisk...${NC}")"

    run_cmd "cfdisk $TARGET_PATH"

    echo -e "\n${GREEN}${BOLD}Partitioning tool closed. Please confirm partition paths:${NC}"
    ask_input "Enter EFI partition path" "$DEF_EFI" "EFI_PART"
    ask_input "Enter Root partition path" "$DEF_ROOT" "ROOT_PART"
    BOOT_MOUNT="/mnt/boot/efi"

    if [[ "$INSTALL_TYPE" == "1" ]]; then
        echo -e "\n${BOLD}Do you want to format the EFI partition ($EFI_PART) to FAT32?${NC}"
        echo "  1) Yes - Format EFI partition (Wipes existing EFI contents)"
        echo "  2) No  - Preserve existing EFI contents"
        ask_input "Choose option" "2" "FORMAT_EFI_OPT"
        [[ "$FORMAT_EFI_OPT" == "1" ]] && DO_FORMAT_EFI=true || DO_FORMAT_EFI=false
    else
        DO_FORMAT_EFI=true
    fi

    if [[ "$DO_FORMAT_EFI" == "true" ]]; then
        msg "Formatting EFI partition ($EFI_PART) to FAT32..."
        until run_cmd "mkfs.fat -F32 $EFI_PART"; do
            warn "Formatting EFI failed."
            read -p "Retry formatting? (y/n): " ync
            [[ "$ync" != "y" ]] && exit 1
        done
        success "EFI partition formatted successfully."
    else
        msg "Preserving existing EFI partition ($EFI_PART)."
    fi
fi

wait_step

# ==============================================================================
msg "Step 2: File System"

msg "Creating ext4 filesystem on root partition..."
run_cmd "mkfs.ext4 -F $ROOT_PART"
check_success "ext4 creation"

msg "Mounting filesystem..."
run_cmd "mount $ROOT_PART /mnt"

# Create directories
run_cmd "mkdir -p /mnt/{boot,home}"

if [[ "$SWAP_SIZE" -gt 0 ]]; then
    msg "Creating ${SWAP_SIZE}GB Swapfile..."
    run_cmd "dd if=/dev/zero of=/mnt/swapfile bs=1G count=${SWAP_SIZE} status=progress"
    run_cmd "chmod 600 /mnt/swapfile"
    run_cmd "mkswap /mnt/swapfile"
    run_cmd "swapon /mnt/swapfile"
    check_success "Swapfile Creation"
fi

# Mount Boot/EFI
run_cmd "mkdir -p /mnt/boot/efi"
run_cmd "mount $EFI_PART /mnt/boot/efi"

check_success "Filesystem mounting"
run_cmd "lsblk $ROOT_PART"
wait_step

# ==============================================================================
msg "Step 3: Installing Base System"
warn "I am about to install the base system packages (base, linux, firmware, etc.)."
echo -e "${YELLOW}This will generate a lot of output and may fill your screen.${NC}"
wait_step

run_cmd "pacstrap -K /mnt base linux linux-firmware grub efibootmgr nano networkmanager dkms"
check_success "Pacstrap"

# --- FSTAB Preview ---
preview_file "/mnt/etc/fstab" "FSTAB (File System Table)" "This file tells the system where to mount your partitions during boot. We use UUIDs to ensure accuracy even if drive letters change."
genfstab -U /mnt >> /mnt/etc/fstab
preview_after "/mnt/etc/fstab"
wait_step

# ==============================================================================
msg "Step 4: Preparing for Chroot"

# Get Swapfile Resume Offset if Swap exists
RESUME_OFFSET=""
if [[ "$SWAP_SIZE" -gt 0 ]] && [[ -f "/mnt/swapfile" ]]; then
    RESUME_OFFSET=$(filefrag -v /mnt/swapfile | awk '{ if($1=="0:"){print substr($4, 1, length($4)-2)} }')
    msg "Swapfile resume offset for Hibernate: ${RESUME_OFFSET}"
fi



# Write host variables for chroot setup
cat <<VAR_EOF > /mnt/chroot_setup.sh
#!/bin/bash
BOOT_MOUNT="$BOOT_MOUNT"
INSTALL_TYPE="$INSTALL_TYPE"
ROOT_PART="$ROOT_PART"
INSTALL_MODE="$INSTALL_MODE"
ROOT_PASS="$ROOT_PASS"
USER_NAME="$USER_NAME"
USER_PASS="$USER_PASS"
PC_NAME="$PC_NAME"
BOOTLOADER_ID="$BOOTLOADER_ID"
UCODE_PKG="$UCODE_PKG"
RESUME_OFFSET="$RESUME_OFFSET"
VAR_EOF

# Write literal chroot setup script
cat <<'EOF' >> /mnt/chroot_setup.sh

# --- Colors & UI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

msg() { echo -e "\n${BLUE}${BOLD}[CHROOT]${NC} ${CYAN}$1${NC}"; }
success() { echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"; }
wait_step() {
    if [[ "$INSTALL_MODE" == "2" ]]; then
        return 0
    fi
    echo -e "\n${YELLOW}>> Press [Enter] to continue...${NC}"
    read -r
}
run_cmd() { echo -e "${CYAN}Executing: ${BOLD}$1${NC}"; eval "$1"; }

preview_file() {
    if [[ "$INSTALL_MODE" == "2" ]]; then
        return 0
    fi
    echo -e "\n${BOLD}--- EDUCATIONAL BRIEF: ${2} ---${NC}"
    echo -e "${CYAN}${3}${NC}"
    if [[ "$1" == *"fstab"* ]] && [[ -f "$1" ]]; then
        cat "$1"
    fi
}

preview_after() {
    if [[ "$INSTALL_MODE" == "2" ]]; then
        return 0
    fi
    echo -e "${GREEN}Task applied to: ${1}${NC}"
    if [[ "$1" == *"fstab"* ]] && [[ -f "$1" ]]; then
        cat "$1"
    fi
}

check_success() { 
    if [ $? -eq 0 ]; then 
        success "$1 finished successfully."
    else 
        if [[ "$INSTALL_MODE" == "2" ]]; then
            error "$1 failed."
        else
            echo -e "${RED}Failed. Press Enter to try to continue...${NC}"; read
        fi
    fi 
}

# --- 1. Timezone ---
msg "Setting Timezone (Asia/Baghdad)..."
run_cmd "ln -sf /usr/share/zoneinfo/Asia/Baghdad /etc/localtime"
run_cmd "hwclock --systohc"
wait_step

# --- 2. Localization ---
msg "Configuring Locales..."
preview_file "/etc/locale.gen" "LOCALE GENERATION" "Enabling en_US and ar_IQ support."
run_cmd "sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen"
run_cmd "sed -i 's/#ar_IQ.UTF-8 UTF-8/ar_IQ.UTF-8 UTF-8/' /etc/locale.gen"
preview_after "/etc/locale.gen"
wait_step

run_cmd "locale-gen"
run_cmd "echo 'LANG=en_US.UTF-8' > /etc/locale.conf"
preview_after "/etc/locale.conf"
wait_step

# --- 3. Network ---
if [[ "$INSTALL_MODE" == "2" ]]; then
    pcname="$PC_NAME"
else
    read -p "Type your PC name [Default: citadel]: " pcname
    [[ -z "$pcname" ]] && pcname="citadel"
fi
run_cmd "echo $pcname > /etc/hostname"
wait_step

# --- 4. Passwords ---
if [[ "$INSTALL_MODE" == "2" ]]; then
    echo -e "${CYAN}Executing: ${BOLD}chpasswd for root (non-interactive)${NC}"
    echo "root:$ROOT_PASS" | chpasswd
else
    msg "Set ROOT password:"
    run_cmd "passwd"
fi
wait_step

# --- 5. Mkinitcpio ---
msg "Configuring Mkinitcpio..."
preview_file "/etc/mkinitcpio.conf" "HOOKS" "Adding resume hook (if swap exists)."

# Update Hooks (including resume hook if offset is present)
run_cmd "sed -i 's/udev/systemd/g' /etc/mkinitcpio.conf"
run_cmd "sed -i 's/keyboard/keyboard keymap/g' /etc/mkinitcpio.conf"

if [[ -n "$RESUME_OFFSET" ]]; then
    run_cmd "sed -i 's/block/block resume/g' /etc/mkinitcpio.conf"
fi
run_cmd "sed -i 's/  */ /g' /etc/mkinitcpio.conf"

preview_after "/etc/mkinitcpio.conf"
wait_step

msg "Running mkinitcpio -P..."
run_cmd "mkinitcpio -P"
check_success "Mkinitcpio"
wait_step




# --- 6. Bootloader ---
msg "Configuring Grub..."
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
preview_file "/etc/default/grub" "GRUB CONFIGURATION" "Setting Kernel cmdline with Resume options (if applicable)."

# Set Kernel CMDLINE (With Hibernate resume parameter if Swapfile exists)
if [[ -n "$RESUME_OFFSET" ]]; then
    run_cmd "sed -i 's|GRUB_CMDLINE_LINUX=\"|GRUB_CMDLINE_LINUX=\"resume=UUID=$ROOT_UUID resume_offset=$RESUME_OFFSET rw |' /etc/default/grub"
fi

preview_after "/etc/default/grub"
wait_step

msg "Installing Grub to $BOOT_MOUNT..."
if [[ "$INSTALL_MODE" == "2" ]]; then
    bootloader_id="$BOOTLOADER_ID"
    echo -e "${CYAN}Executing: ${BOLD}grub-install (non-interactive)${NC}"
    run_cmd "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=\"${bootloader_id}\""
    run_cmd "mkdir -p /boot/efi/EFI/BOOT"
    run_cmd "cp /boot/efi/EFI/\"${bootloader_id}\"/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI"
    echo -e "${CYAN}Executing: ${BOLD}grub-mkconfig (non-interactive)${NC}"
    run_cmd "grub-mkconfig -o /boot/grub/grub.cfg"
else
    read -p "Type your Bootloader ID [Default: GRUB_Arch]: " bootloader_id
    [[ -z "$bootloader_id" ]] && bootloader_id="GRUB_Arch"
    run_cmd "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=\"${bootloader_id}\""
    run_cmd "mkdir -p /boot/efi/EFI/BOOT"
    run_cmd "cp /boot/efi/EFI/\"${bootloader_id}\"/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI"
    run_cmd "grub-mkconfig -o /boot/grub/grub.cfg"
fi
wait_step

# --- 7. Final Steps ---
msg "Installing System Utilities..."
warn "I am about to install: ${UCODE_PKG}, sudo"
wait_step
run_cmd "pacman -S --noconfirm ${UCODE_PKG} sudo"
run_cmd "systemctl enable NetworkManager"
wait_step

if [[ "$INSTALL_MODE" == "2" ]]; then
    username="$USER_NAME"
    run_cmd "useradd -m -G wheel -s /bin/bash $username"
    echo -e "${CYAN}Executing: ${BOLD}chpasswd for user (non-interactive)${NC}"
    echo "$username:$USER_PASS" | chpasswd
else
    read -p "Enter username: " username
    run_cmd "useradd -m -G wheel -s /bin/bash $username"
    run_cmd "passwd $username"
fi
wait_step

msg "Configuring Sudo..."
run_cmd "sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers"
wait_step

msg "Installing Desktop Environment (XFCE4)..."
warn "I am about to install the XFCE4 Desktop and Ly display manager."
echo -e "${YELLOW}This is a large installation and will flood the screen.${NC}"
wait_step
run_cmd "pacman -S --noconfirm xorg xfce4 xfce4-goodies ly noto-fonts noto-fonts-extra ttf-liberation freetype2 cairo fontconfig"
wait_step

msg "Enabling Login Manager (Ly on tty2)..."
run_cmd "systemctl enable ly@tty2.service"
wait_step

msg "Installing and Configuring Starship Shell Prompt..."
run_cmd "pacman -S --noconfirm starship"

# Function to write starship config
write_starship_config() {
    local target_dir="$1"
    run_cmd "mkdir -p $target_dir/.config"
    cat <<'STARSHIP_EOF' > "$target_dir/.config/starship.toml"
add_newline = false

format = """
[$username@$hostname]($style) $directory $git_branch
$character
"""

[character]
success_symbol = "[➜](green)"

# error_symbol = "[✗](red)"
[username]
show_always = true

[hostname]
ssh_only = false

[directory]
truncation_length = 3
style = "cyan"
STARSHIP_EOF
}

# Configure for root
run_cmd "echo 'eval \"\$(starship init bash)\"' >> /root/.bashrc"
write_starship_config "/root"

# Configure for the new user
USER_HOME="/home/$username"
if [[ -d "$USER_HOME" ]]; then
    run_cmd "echo 'eval \"\$(starship init bash)\"' >> $USER_HOME/.bashrc"
    write_starship_config "$USER_HOME"
    run_cmd "chown -R $username:$username $USER_HOME/.config"
    run_cmd "chown $username:$username $USER_HOME/.bashrc"
fi
wait_step

msg "CHROOT SETUP COMPLETE!"
exit
EOF

run_cmd "chmod +x /mnt/chroot_setup.sh"
run_cmd "arch-chroot /mnt /chroot_setup.sh"

# --- Post Chroot cleanup ---
run_cmd "rm /mnt/chroot_setup.sh"

msg "Installation complete! You can now reboot."
echo -e "${YELLOW}After rebooting, your plain Arch Linux with ext4 is ready!${NC}"