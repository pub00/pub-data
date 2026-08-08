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
    echo -e "${BLUE}${BOLD}============================================================${NC}"
    echo -e "           ${BOLD}FAST AUTOMATED MODE INPUT COLLECTION${NC}"
    echo -e "${BLUE}${BOLD}============================================================${NC}"
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
        DEF_EFI="/dev/${TARGET_DEV}p1"
        DEF_ROOT="/dev/${TARGET_DEV}p2"
    fi

    echo -e "\n${BOLD}Is this a dual-boot installation (using an existing EFI partition)?${NC}"
    echo "  1) Yes (Dual-boot - preserve existing partitions)"
    echo "  2) No (Fresh Installation - WILL WIPE TARGET PARTITIONS)"
    ask_input "Choose type" "1" "INSTALL_TYPE"

    ask_input "EFI Partition path" "$DEF_EFI" "EFI_PART"
    ask_input "Root Partition path" "$DEF_ROOT" "ROOT_PART"
    BOOT_MOUNT="/mnt/boot/efi"

    echo ""
    ask_password "Encryption (LUKS) Password" "ENCRYPT_PASS"

    ask_input "PC Hostname" "citadel" "PC_NAME"
    ask_input "Bootloader ID" "GRUB_Encrypted_Arch" "BOOTLOADER_ID"

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
    echo -e "  ${BOLD}Encryption Key:${NC}     ${ENCRYPT_PASS}"
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
    echo -e "     • Will be encrypted with LUKS and formatted with Btrfs subvolumes."
    echo ""
    echo -e "  ${BOLD}3. Swap Partition:${NC}"
    echo -e "     • ${GREEN}No separate Swap partition is required in cfdisk!${NC}"
    echo -e "       The installer will automatically create a Btrfs Swapfile inside"
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
msg "Step 2: Encryption & File System"

if [[ "$INSTALL_MODE" == "2" ]]; then
    msg "Encrypting root partition with LUKS1 (non-interactive)..."
    echo -n "$ENCRYPT_PASS" | cryptsetup luksFormat --type luks1 -q --key-file=- "$ROOT_PART"
    check_success "LUKS Format"

    msg "Opening encrypted partition (non-interactive)..."
    echo -n "$ENCRYPT_PASS" | cryptsetup open "$ROOT_PART" cryptroot --key-file=-
    check_success "LUKS Open"
else
    echo -e "${CYAN}We are now encrypting the root partition using LUKS1 (for Grub compatibility).${NC}"
    until cryptsetup luksFormat --type luks1 "$ROOT_PART"; do
        warn "Encryption failed (did you type 'YES' correctly?)."
        read -p "Do you want to [r]etry or [a]bort? (r/a): " choice
        if [[ "$choice" != "r" ]]; then
            error "Installation aborted by user."
        fi
    done

    msg "Opening encrypted partition..."
    run_cmd "cryptsetup open $ROOT_PART cryptroot"
    check_success "LUKS Open"
fi

msg "Creating Btrfs filesystem on cryptroot..."
run_cmd "mkfs.btrfs -f /dev/mapper/cryptroot"
check_success "Btrfs creation"

msg "Creating Subvolumes..."
run_cmd "mount /dev/mapper/cryptroot /mnt"
run_cmd "btrfs subvolume create /mnt/@"
run_cmd "btrfs subvolume create /mnt/@home"
run_cmd "btrfs subvolume create /mnt/@snapshots"
run_cmd "btrfs subvolume create /mnt/@var_log"
if [[ "$SWAP_SIZE" -gt 0 ]]; then
    run_cmd "btrfs subvolume create /mnt/@swap"
fi
run_cmd "umount /mnt"

msg "Mounting Subvolumes with optimized options..."

# Mount Root subvolume
run_cmd "mount -o noatime,compress=zstd,space_cache=v2,subvol=@ /dev/mapper/cryptroot /mnt"

# Create mount points
run_cmd "mkdir -p /mnt/{boot,home,.snapshots,var/log}"
if [[ "$SWAP_SIZE" -gt 0 ]]; then
    run_cmd "mkdir -p /mnt/swap"
fi

# Mount subvolumes
run_cmd "mount -o noatime,compress=zstd,space_cache=v2,subvol=@home /dev/mapper/cryptroot /mnt/home"
run_cmd "mount -o noatime,compress=zstd,space_cache=v2,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots"
run_cmd "mount -o noatime,compress=zstd,space_cache=v2,subvol=@var_log /dev/mapper/cryptroot /mnt/var/log"

if [[ "$SWAP_SIZE" -gt 0 ]]; then
    run_cmd "mount -o noatime,subvol=@swap /dev/mapper/cryptroot /mnt/swap"
    msg "Creating ${SWAP_SIZE}GB Swapfile on Btrfs (@swap)..."
    run_cmd "btrfs filesystem mkswapfile --size ${SWAP_SIZE}g /mnt/swap/swapfile"
    run_cmd "swapon /mnt/swap/swapfile"
    check_success "Btrfs Swapfile Creation"
fi

# Mount Boot/EFI
run_cmd "mkdir -p /mnt/boot/efi"
run_cmd "mount $EFI_PART /mnt/boot/efi"

check_success "Subvolume mounting"
run_cmd "lsblk /dev/mapper/cryptroot"
wait_step

# ==============================================================================
msg "Step 3: Installing Base System"
warn "I am about to install the base system packages (base, linux, firmware, btrfs-progs, etc.)."
echo -e "${YELLOW}This will generate a lot of output and may fill your screen.${NC}"
wait_step

run_cmd "pacstrap -K /mnt base linux linux-firmware btrfs-progs cryptsetup grub efibootmgr nano networkmanager snapper dkms"
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
if [[ "$SWAP_SIZE" -gt 0 ]] && [[ -f "/mnt/swap/swapfile" ]]; then
    RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile 2>/dev/null | awk '{print $1}')
    msg "Btrfs Swapfile resume offset for Hibernate: ${RESUME_OFFSET}"
fi

# --- Generate snpsht utility on the target system ---
msg "Installing 'snpsht' utility to /usr/local/bin/..."
cat <<'SNPSHT_EOF' > /mnt/usr/local/bin/snpsht
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

CRYPT_DEV="/dev/mapper/cryptroot"

msg() { echo -e "\n${BLUE}${BOLD}[snpsht]${NC} ${CYAN}$1${NC}"; }
success() { echo -e "${GREEN}${BOLD}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}${BOLD}[!]${NC} $1"; }
error() { echo -e "${RED}${BOLD}[ERROR]${NC} $1"; }
brief() { echo -e "${YELLOW}>> WHY: $1${NC}"; }
run_cmd() { 
    echo -e "${CYAN}Executing: ${BOLD}$1${NC}"
    eval "$1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)."
        exit 1
    fi
}

show_dashboard() {
    clear
    echo -e "${BLUE}${BOLD}====================================================${NC}"
    echo -e "   ${BOLD}snpsht - Btrfs Manager${NC}"
    echo -e "${BLUE}${BOLD}====================================================${NC}"
    if systemctl is-active --quiet grub-btrfsd; then
        echo -ne "  Status: [ ${GREEN}${BOLD}HEALTHY${NC} ] - "
        echo -e "Grub-Btrfs Daemon is running."
    else
        echo -ne "  Status: [ ${RED}${BOLD}WARNING${NC} ] - "
        echo -e "Grub-Btrfs Daemon is NOT running."
    fi
    echo -e "${BLUE}${BOLD}----------------------------------------------------${NC}"
}

auto_setup() {
    if [[ ! -f "/etc/snapper/configs/root" ]]; then
        msg "First-time setup detected. Configuring Snapper..."
        brief "Enabling grub-btrfs daemon..."
        run_cmd "systemctl enable --now grub-btrfsd"
        brief "Resetting .snapshots..."
        run_cmd "umount /.snapshots 2>/dev/null"
        run_cmd "rm -rf /.snapshots 2>/dev/null"
        brief "Creating config..."
        run_cmd "snapper -c root create-config /"
        brief "Fixing subvolume..."
        run_cmd "btrfs subvolume delete /.snapshots 2>/dev/null"
        run_cmd "mkdir /.snapshots"
        run_cmd "mount -a"
        run_cmd "chmod 750 /.snapshots"
        brief "Disabling automatic timeline snapshots..."
        run_cmd "sed -i 's/TIMELINE_CREATE=\"yes\"/TIMELINE_CREATE=\"no\"/' /etc/snapper/configs/root"
        run_cmd "systemctl disable --now snapper-timeline.timer"
        run_cmd "systemctl disable --now snapper-cleanup.timer"
        brief "First snapshot..."
        run_cmd "snapper -c root create --description 'after fresh installation'"
        brief "Update grub..."
        run_cmd "grub-mkconfig -o /boot/grub/grub.cfg"
        success "Initial setup complete!"
        read -p "Press Enter to continue to the menu..."
    fi
}

create_snapshot() {
    msg "Create New Snapshot"
    read -p "Enter description: " desc
    [[ -z "$desc" ]] && desc="manual snapshot"
    run_cmd "snapper -c root create --description '$desc'"
    success "Snapshot created: $desc"
    run_cmd "grub-mkconfig -o /boot/grub/grub.cfg"
}

delete_snapshot() {
    list_snapshots
    echo ""
    read -p "Enter Snapshot ID to DELETE: " sid
    [[ -z "$sid" ]] && return
    warn "Are you sure you want to delete snapshot #$sid? (y/N)"
    read -p "> " confirm
    if [[ "$confirm" == "y" ]]; then
        run_cmd "snapper -c root delete $sid"
        success "Snapshot #$sid deleted."
        run_cmd "grub-mkconfig -o /boot/grub/grub.cfg"
    fi
}

list_snapshots() {
    msg "Available Snapshots"
    run_cmd "snapper -c root list"
}

restore_snapshot() {
    list_snapshots
    echo ""
    read -p "Enter Snapshot ID to restore: " sid
    [[ -z "$sid" ]] && return
    msg "Starting Safe Restore..."
    TEMP_MNT=$(mktemp -d /mnt/snpsht.XXXXXX)
    run_cmd "mount -o subvol=/ $CRYPT_DEV $TEMP_MNT"

    # 1. Rename current @ instead of deleting
    TS=$(date +%Y%m%d_%H%M%S)
    OLD_NAME="@_old_$TS"
    msg "Renaming current system to $OLD_NAME..."
    run_cmd "mv $TEMP_MNT/@ $TEMP_MNT/$OLD_NAME"

    # 2. Restore snapshot
    msg "Restoring snapshot #$sid to @..."
    run_cmd "btrfs subvolume snapshot $TEMP_MNT/@snapshots/$sid/snapshot $TEMP_MNT/@"

    # 3. Force disk sync
    msg "Syncing changes to disk..."
    run_cmd "sync"

    run_cmd "umount $TEMP_MNT"
    run_cmd "rmdir $TEMP_MNT"

    success "RESTORE COMPLETE!"
    warn "Your old system is saved as $OLD_NAME."
    warn "You can delete it using the 'Cleanup' option AFTER you reboot."
    echo -e "${RED}${BOLD}!!! REBOOT NOW TO LOAD THE RESTORED SYSTEM !!!${NC}"
}

recursive_subvolume_delete() {
    local mnt=$1
    local subvol=$2
    btrfs subvolume list -o "$mnt" | awk '{print $9}' | grep "^$subvol/" | tac | while read -r nested; do
        run_cmd "btrfs subvolume delete \"$mnt/$nested\""
    done
    run_cmd "btrfs subvolume delete \"$mnt/$subvol\""
}

cleanup_broken() {
    msg "Searching for leftover subvolumes (@_broken or @_old)..."
    TEMP_MNT=$(mktemp -d /mnt/snpsht.XXXXXX)
    run_cmd "mount -o subvol=/ $CRYPT_DEV $TEMP_MNT"

    BROKEN_SUBS=$(find "$TEMP_MNT" -maxdepth 1 -name "@_broken_*" -o -name "@_old_*")

    if [[ -z "$BROKEN_SUBS" ]]; then
        success "No broken subvolumes found."
    else
        echo -e "Found the following backups:"
        for sub in $BROKEN_SUBS; do echo " - $(basename "$sub")"; done
        read -p "Do you want to delete ALL of them? (y/N): " choice
        if [[ "$choice" == "y" ]]; then
            for sub_path in $BROKEN_SUBS; do
                local sub_name=$(basename "$sub_path")
                warn "Deleting $sub_name recursively..."
                recursive_subvolume_delete "$TEMP_MNT" "$sub_name"
            done
            success "Cleanup finished."
        fi
    fi
    run_cmd "umount $TEMP_MNT"
    run_cmd "rmdir $TEMP_MNT"
}

check_root
auto_setup
while true; do
    show_dashboard
    echo "  1) Create New Snapshot"
    echo "  2) Delete Snapshot"
    echo "  3) List Snapshots"
    echo "  4) Restore from Snapshot (Rollback)"
    echo "  5) Cleanup @_broken subvolumes"
    echo "  6) Exit"
    echo ""
    read -p "Select an option [1-6]: " opt
    case $opt in
        1) create_snapshot ;;
        2) delete_snapshot ;;
        3) list_snapshots ;;
        4) restore_snapshot ;;
        5) cleanup_broken ;;
        6) exit 0 ;;
        *) warn "Invalid option." ;;
    esac
    read -p "Press Enter to return to menu..."
done
SNPSHT_EOF

chmod +x /mnt/usr/local/bin/snpsht

echo ""
echo -e "${YELLOW}${BOLD}+----------------------------------------------------------+${NC}"
echo -e "${YELLOW}${BOLD}|  REMINDER: snpsht (Btrfs Snapshot Manager)               |${NC}"
echo -e "${YELLOW}${BOLD}|                                                          |${NC}"
echo -e "${YELLOW}${BOLD}|  Saved to:  /usr/local/bin/snpsht                        |${NC}"
echo -e "${YELLOW}${BOLD}|                                                          |${NC}"
echo -e "${YELLOW}${BOLD}|  To edit:   nano /usr/local/bin/snpsht                   |${NC}"
echo -e "${YELLOW}${BOLD}|  To run:    sudo snpsht                                  |${NC}"
echo -e "${YELLOW}${BOLD}+----------------------------------------------------------+${NC}"
wait_step

# Write host variables for chroot setup
cat <<VAR_EOF > /mnt/chroot_setup.sh
#!/bin/bash
BOOT_MOUNT="$BOOT_MOUNT"
INSTALL_TYPE="$INSTALL_TYPE"
ROOT_PART="$ROOT_PART"
INSTALL_MODE="$INSTALL_MODE"
ENCRYPT_PASS="$ENCRYPT_PASS"
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
    run_cmd "echo \"root:$ROOT_PASS\" | chpasswd"
else
    msg "Set ROOT password:"
    run_cmd "passwd"
fi
wait_step

# --- 5. Mkinitcpio ---
msg "Configuring Mkinitcpio..."
preview_file "/etc/mkinitcpio.conf" "HOOKS" "Adding sd-encrypt, resume (if swap exists), btrfs, and the secure Keyfile."

# 5a. Create LUKS Keyfile in the standard systemd location
msg "Generating Secure LUKS Keyfile..."
run_cmd "mkdir -p /etc/cryptsetup-keys.d"
run_cmd "dd bs=512 count=4 if=/dev/urandom iflag=fullblock of=/etc/cryptsetup-keys.d/cryptroot.key"
run_cmd "chmod 000 /etc/cryptsetup-keys.d/cryptroot.key"

if [[ "$INSTALL_MODE" == "2" ]]; then
    run_cmd "echo -n \"$ENCRYPT_PASS\" | cryptsetup luksAddKey $ROOT_PART /etc/cryptsetup-keys.d/cryptroot.key --key-file=-"
else
    warn "Adding the keyfile to LUKS. Please type your password one last time."
    run_cmd "cryptsetup luksAddKey $ROOT_PART /etc/cryptsetup-keys.d/cryptroot.key"
fi

# 5b. Add Keyfile to initramfs
run_cmd "sed -i 's|^FILES=()|FILES=(/etc/cryptsetup-keys.d/cryptroot.key)|' /etc/mkinitcpio.conf"

# 5c. Update Hooks (including resume hook if offset is present)
run_cmd "sed -i 's/udev/systemd/g' /etc/mkinitcpio.conf"
run_cmd "sed -i 's/keyboard/keyboard keymap/g' /etc/mkinitcpio.conf"

if [[ -n "$RESUME_OFFSET" ]]; then
    run_cmd "sed -i 's/block/block sd-encrypt resume btrfs/g' /etc/mkinitcpio.conf"
else
    run_cmd "sed -i 's/block/block sd-encrypt btrfs/g' /etc/mkinitcpio.conf"
fi
run_cmd "sed -i 's/  */ /g' /etc/mkinitcpio.conf"

preview_after "/etc/mkinitcpio.conf"
wait_step

msg "Running mkinitcpio -P..."
run_cmd "mkinitcpio -P"
check_success "Mkinitcpio"
wait_step

msg "Installing grub-btrfs and inotify-tools..."
warn "I am about to install: grub-btrfs inotify-tools"
wait_step
run_cmd "pacman -S --noconfirm grub-btrfs inotify-tools"
wait_step

# --- 6. Bootloader ---
msg "Configuring Grub..."
LUKS_UUID=$(blkid -s UUID -o value "$ROOT_PART")
preview_file "/etc/default/grub" "GRUB CONFIGURATION" "Enabling Cryptodisk and setting Kernel cmdline with LUKS and Resume options."

# 6a. Enable Cryptodisk
run_cmd "echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub"

# 6b. Set Kernel CMDLINE (With Hibernate resume parameter if Swapfile exists)
if [[ -n "$RESUME_OFFSET" ]]; then
    run_cmd "sed -i 's|GRUB_CMDLINE_LINUX=\"|GRUB_CMDLINE_LINUX=\"rd.luks.name=$LUKS_UUID=cryptroot root=/dev/mapper/cryptroot resume=/dev/mapper/cryptroot resume_offset=$RESUME_OFFSET rw |' /etc/default/grub"
else
    run_cmd "sed -i 's|GRUB_CMDLINE_LINUX=\"|GRUB_CMDLINE_LINUX=\"rd.luks.name=$LUKS_UUID=cryptroot root=/dev/mapper/cryptroot rw |' /etc/default/grub"
fi

preview_after "/etc/default/grub"
wait_step

msg "Installing Grub to $BOOT_MOUNT..."
if [[ "$INSTALL_MODE" == "2" ]]; then
    bootloader_id="$BOOTLOADER_ID"
else
    read -p "Type your Bootloader ID [Default: GRUB_Encrypted_Arch]: " bootloader_id
    [[ -z "$bootloader_id" ]] && bootloader_id="GRUB_Encrypted_Arch"
fi
run_cmd "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=${bootloader_id}"
run_cmd "grub-mkconfig -o /boot/grub/grub.cfg"
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
    run_cmd "echo \"$username:$USER_PASS\" | chpasswd"
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
echo -e "${YELLOW}After rebooting, simply type ${BOLD}snpsht${NC}${YELLOW} to finish the setup!${NC}"