get_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID:-unknown}"
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    else
        uname -s | tr '[:upper:]' '[:lower:]'
    fi
}

log() {
    local GREEN='\033[0;32m'
    local NC='\033[0m'
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    local RED='\033[0;31m'
    local NC='\033[0m'
    echo -e "${RED}[ERROR]${NC} $1"
}

ask_option() {
    local prompt="$1"
    shift

    declare -A opts
    while [[ $# -gt 0 ]]; do
        key="${1,,}"
        shift
        for alias in $key; do
            opts["${alias,,}"]="${key%% *}"
        done
    done

    while true; do
        read -rp "$prompt (${!opts[*]}): " answer
        answer="${answer,,}"

        if [[ -n "${opts[$answer]}" ]]; then
            echo "${opts[$answer]}"
            return 0
        fi

        echo "Invalid option."
    done
}

install_package() {
    pkg="$1"
    os=$(get_os)

    case "$os" in
        ubuntu|debian)
            sudo apt update && sudo apt install -y "$pkg"
            ;;
        fedora)
            sudo dnf install -y "$pkg"
            ;;
        arch)
            sudo pacman -S --noconfirm "$pkg"
            ;;
        opensuse*|suse)
            sudo zypper install -y "$pkg"
            ;;
        *)
            error "Unsupported distro. Please install $pkg manually."
            return 1
            ;;
    esac
}

check_dependencies() {
    if ! command -v sudo >/dev/null 2>&1; then
        error "sudo is required to install packages."
        exit 1
    fi
    # Check gocryptfs
    if ! command -v gocryptfs >/dev/null 2>&1; then
        error "gocryptfs is not installed."

        if [[ $(ask_option "Install now?" yes no) == "yes" ]]; then
            install_package gocryptfs || {
                error "Installation failed."
                exit 1
            }

            # تحقق مرة ثانية
            if ! command -v gocryptfs >/dev/null 2>&1; then
                error "gocryptfs still not found after installation."
                exit 1
            fi

            log "gocryptfs installed successfully."
        else
            error "Script cannot continue without gocryptfs."
            exit 1
        fi   
    fi
}


# --- Detect fusermount command ---
# fuse3 provides 'fusermount3', fuse2 provides 'fusermount'.
# Both support identical flags: -u (unmount) and -z (lazy unmount).
# This must be called AFTER check_dependencies (which may install fuse via gocryptfs).
detect_fusermount() {
    if command -v fusermount3 >/dev/null 2>&1; then
        FUSERMOUNT="fusermount3"
    elif command -v fusermount >/dev/null 2>&1; then
        FUSERMOUNT="fusermount"
    else
        error "Neither fusermount nor fusermount3 found. Install fuse2 or fuse3."
        exit 1
    fi
}