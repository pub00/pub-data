#!/bin/bash
# ==============================================================================
# Secure Vault Manager 2.0
# ==============================================================================
# A portable, terminal-based encrypted folder manager using gocryptfs.
# Works on any Linux desktop distro — no Zenity or GUI dependencies.
#
# Usage: bash secure_manager2.0.sh
# ==============================================================================


# --- INITIALIZATION ---
# ${BASH_SOURCE[0]} = the path of THIS script (even if sourced from elsewhere)
# dirname gets the parent directory, cd + pwd resolves to absolute path.
# This ensures all relative paths work no matter WHERE you run the script from.
DIR="$( cd "$( dirname "$(readlink -f "${BASH_SOURCE[0]}")" )" && pwd )"
CONFIG="$HOME/.secure_manager_config"
ICON_DIR="$DIR/icons"

# Ensure required directories exist
mkdir -p "$ICON_DIR"
touch "$CONFIG"


# --- LOAD MODULES ---
# 'source' (or '.') runs another script in the CURRENT shell.
# Unlike 'bash script.sh' which runs in a SUBshell (separate environment),
# source shares all variables and functions with this script.
# Order matters! ui.sh must load before vault.sh (which uses ui functions).
source "$DIR/lib/utils.sh"
source "$DIR/lib/ui.sh"
source "$DIR/lib/config.sh"
source "$DIR/lib/vault.sh"
source "$DIR/lib/backup.sh"
source "$DIR/lib/guard.sh"


# --- DEPENDENCY CHECK ---
check_dependencies

# --- DETECT FUSERMOUNT ---
# Must run after check_dependencies (gocryptfs install may pull in fuse3)
detect_fusermount


# --- START BACKGROUND GUARD ---
guard_setup


# ==============================================================================
# MAIN MENU LOOP
# ==============================================================================
# This is the heart of the application — an infinite loop that:
#   1. Shows the vault table
#   2. Presents action menu
#   3. Executes the chosen action
#   4. Loops back to step 1
#
# The 'while true' runs forever until the user picks Quit (or Ctrl+C).
# ==============================================================================

while true; do
    clear

    ui_header "🔐 Secure Vault Manager 2.0"
    guard_status

    # Show vault table (won't error if empty — just shows a message)
    ui_table "$CONFIG"

    # Main action menu
    ACTION=$(ui_menu "Actions" \
        "Toggle Vault (Lock/Unlock)" \
        "New Vault" \
        "Backup Vault" \
        "Open Folder" \
        "Recover Password" \
        "Delete Vault" \
        "Lock All Vaults" \
        "Screen Lock Exclusions" \
        "Quit")

    case "$ACTION" in
        "Toggle Vault (Lock/Unlock)")
            clear
            TARGET=$(ui_vault_select "$CONFIG" "Select vault to toggle")
            [[ -n "$TARGET" ]] && vault_toggle "$TARGET"
            ;;

        "New Vault")
            clear
            vault_create
            ;;

        "Backup Vault")
            clear
            TARGET=$(ui_vault_select "$CONFIG" "Select vault to backup")
            [[ -n "$TARGET" ]] && backup_vault "$TARGET"
            ;;

        "Open Folder")
            clear
            TARGET=$(ui_vault_select "$CONFIG" "Select vault to open")
            [[ -n "$TARGET" ]] && vault_open_folder "$TARGET"
            ;;

        "Recover Password")
            clear
            TARGET=$(ui_vault_select "$CONFIG" "Select vault to recover")
            [[ -n "$TARGET" ]] && vault_recover "$TARGET"
            ;;

        "Delete Vault")
            clear
            TARGET=$(ui_vault_select "$CONFIG" "Select vault to delete")
            [[ -n "$TARGET" ]] && vault_delete "$TARGET"
            ;;

        "Lock All Vaults")
            clear
            guard_lock_all
            ;;

        "Screen Lock Exclusions")
            clear
            vault_manage_exclusions
            ;;

        "Quit")
            ui_info "Goodbye! Your vaults are protected."
            exit 0
            ;;
    esac

    # Pause before refreshing so user can read the output
    echo ""
    read -p "  Press Enter to continue..."
done
