#!/bin/bash
# ==============================================================================
# G-Manager — Chrome Multi-Account Profile Switcher (Main Entry Point)
# ==============================================================================
# A portable, terminal-based tool to manage multiple Google Chrome profiles.
# Works on any Linux distro — no GUI dependencies (no Zenity, no Dialog).
#
# FEATURES:
#   1. Create new profiles from email addresses
#   2. Switch between profiles via symlink swapping
#   3. List all profiles with sizes and status
#   4. Launch Chrome with the active profile
#   5. Restore original Chrome profile
#   6. Delete profiles safely
#
# REQUIREMENTS:
#   - Google Chrome (google-chrome or google-chrome-stable)
#   - Bash 4+ (for ${var,,} lowercase and associative arrays)
#   - Standard coreutils (ln, rm, mv, mkdir, readlink, du, pgrep)
#
# Usage: bash g_manager.sh
# ==============================================================================


# --- INITIALIZATION ---
# BASH_SOURCE[0] = the path of THIS script (even if sourced from elsewhere).
# dirname gets the parent directory.
# cd + pwd resolves symlinks and gives us the ABSOLUTE path.
# This ensures 'source lib/*.sh' works no matter WHERE you run the script from.
#
# Example: if you run "bash ~/Tools/G-manager/g_manager.sh" from /tmp,
# DIR will still be "/home/user/Tools/G-manager" (not /tmp).
DIR="$( cd "$( dirname "$(readlink -f "${BASH_SOURCE[0]}")" )" && pwd )"


# --- LOAD MODULES ---
# 'source' (or '.') runs another script in the CURRENT shell.
# Unlike 'bash script.sh' which runs in a SUBSHELL (separate environment),
# source shares all variables and functions with this script.
#
# ORDER MATTERS:
#   ui.sh must load first — config.sh and core.sh use its functions
#   config.sh must load before core.sh — core.sh uses config functions
source "$DIR/lib/ui.sh"
source "$DIR/lib/config.sh"
source "$DIR/lib/core.sh"


# --- DEPENDENCY CHECK ---
# Exits immediately if Chrome is not installed (shows install instructions).
# This MUST run before anything else — the tool is useless without Chrome.
core_check_deps


# --- INITIALIZE CONFIG DIRECTORY & REGISTRY ---
# Creates ~/.config/g_manager/ and profiles.conf.
# NOTE: This does NOT touch the vault/profiles directory.
config_init


# --- VAULT CHECK (First Run) ---
# The profiles live inside an encrypted vault managed by Secure Manager.
# Before we can do ANYTHING with profiles, the vault must be mounted.
# If it's locked or missing, we show instructions and exit.
echo >&2
ui_header "(i) Startup Check"

if ! config_check_vault; then
    echo >&2
    ui_error "Cannot continue without an unlocked vault."
    echo >&2
    read -r -p "  Press Enter to exit..."
    exit 1
fi
ui_info "Vault is unlocked -- profiles are accessible [OK]"


# --- AUTO-IMPORT EXISTING PROFILES ---
# Scans the vault for existing profile directories not yet registered.
# On subsequent runs, this does nothing (already imported).
config_import_existing


# --- ENSURE ORIGINAL PROFILE IS BACKED UP ---
# If Default/ is still a real directory (first time using G-Manager),
# moves it to Default_Backup/ for safekeeping. Idempotent.
core_ensure_backup

# Brief pause so user can see startup messages
sleep 1


# ==============================================================================
# MAIN MENU LOOP
# ==============================================================================
# This is the heart of the application — an infinite loop that:
#   1. Clears the screen
#   2. Shows the banner + status
#   3. Executes the chosen action
#   4. Pauses for user to read output
#   5. Loops back to step 1
#
# 'while true' runs forever until:
#   - User picks "Quit" (which calls 'exit 0')
#   - User presses Ctrl+C (which sends SIGINT)
# ==============================================================================

while true; do
    # Clear the terminal for a clean dashboard look
    clear

    # Show the app banner (ASCII art header)
    ui_banner

    # --- VAULT CHECK (Every Loop) ---
    # The vault could be locked DURING a session (e.g., auto-lock timeout,
    # or user manually locked it in another terminal).
    # We re-check every loop iteration to catch this.
    # If the vault becomes locked, we warn and exit instead of corrupting data.
    if ! config_check_vault; then
        echo >&2
        ui_error "Vault was locked during this session!"
        ui_warn "Unlock the vault and restart G-Manager."
        echo >&2
        read -r -p "  Press Enter to exit..."
        exit 1
    fi

    # Show active profile status on the dashboard
    # This reads the symlink in real-time so it's always accurate
    core_show_status

    # Display the main menu and capture user's choice
    # ui_menu echoes the TEXT of the selected option to stdout
    ACTION=$(ui_menu "Main Menu" \
        "[NEW] Create New Profile" \
        "[SW ] Switch Profile" \
        "[LS ] List All Profiles" \
        "[RUN] Launch Chrome" \
        "[ORG] Restore Original Profile" \
        "[DEL] Delete a Profile" \
        "[X  ] Quit")

    # 'case' is bash's version of switch/case from other languages.
    # It matches the string against each pattern and runs the matching block.
    # Each block ends with ;; (like 'break' in other languages).
    case "$ACTION" in

        "[NEW] Create New Profile")
            clear
            core_create_profile
            ;;

        "[SW ] Switch Profile")
            clear
            core_switch_profile
            ;;

        "[LS ] List All Profiles")
            clear
            core_list_all
            ;;

        "[RUN] Launch Chrome")
            clear
            core_launch_chrome
            ;;

        "[ORG] Restore Original Profile")
            clear
            core_restore_original
            ;;

        "[DEL] Delete a Profile")
            clear
            core_delete_profile
            ;;

        "[X  ] Quit")
            echo >&2
            ui_info "Goodbye! :)"
            echo >&2
            exit 0
            ;;
    esac

    # Pause so user can read the output before screen clears
    echo >&2
    read -r -p "  Press Enter to return to menu..."
done
