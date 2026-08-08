#!/bin/bash
# ==============================================================================
# Git Helper Dashboard — Main Entry Point
# ==============================================================================
# A portable, terminal-based Git workflow helper.
# Works on any Linux distro — no GUI dependencies.
#
# FEATURES:
#   1. Clone remote repos with PAT authentication
#   2. Push changes (keeping deleted files on remote)
#   3. Push all changes (including deletions)
#   4. Hard reset local repo to match remote
#   5. One-time file copy from another repo
#
# Usage: bash git_helper.sh
# ==============================================================================


# --- INITIALIZATION ---
# BASH_SOURCE[0] = the path of THIS script (even if sourced from elsewhere).
# dirname gets the parent directory.
# cd + pwd resolves symlinks and gives us the ABSOLUTE path.
# This ensures 'source lib/*.sh' works no matter WHERE you run the script from.
#
# Example: if you run "bash ~/Desktop/git_helper/git_helper.sh" from /tmp,
# DIR will still be "/home/user/Desktop/git_helper" (not /tmp).
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
# Exits immediately if git is not installed (shows install instructions).
core_check_deps


# --- INITIALIZE REPO CONFIG ---
# Ensures the config directory (~/.config/git_helper/) and files exist.
# Safe to call every launch — creates only if missing.
config_repo_init


# --- SETUP: Mandatory Global Config ---
# This ensures the user has set their Name/Email and GitHub credentials
# BEFORE they can access the main menu. Prevents "identity unknown" errors.
ui_header "⚙️  Startup Check"
config_ensure_aliases

if ! config_ensure_identity; then
    ui_error "Mandatory Git identity setup failed. Exiting."
    exit 1
fi

if ! config_ensure_global_auth; then
    ui_error "Mandatory GitHub authentication setup failed. Exiting."
    exit 1
fi

# Verify stored credentials for the active repository (if any)
if config_repo_get_active > /dev/null 2>&1; then
    # Determine remote host for active repo
    active_repo=$(config_repo_get_active)
    remote_url=$(config_get_remote_url "$active_repo")
    if [[ -n "$remote_url" ]]; then
        host=$(echo "$remote_url" | sed 's|https://||' | sed 's|/.*||')
        # If we have previously validated this host, skip credential check
        if [[ -f "${REPO_CONFIG_DIR}/cred_validated" ]] && grep -Fxq "$host" "${REPO_CONFIG_DIR}/cred_validated"; then
            ui_success "Stored credentials for ${host} already validated."
        else
            core_ensure_credentials
        fi
    else
        core_ensure_credentials
    fi
fi

# Brief pause so user can see the startup messages
sleep 1


# ==============================================================================
# MAIN MENU LOOP
# ==============================================================================
# This is the heart of the application — an infinite loop that:
#   1. Clears the screen
#   2. Shows the banner + menu
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

    # --- Show active repo status ---
    # This tells the user which repo push/reset will operate on.
    # If no repo is set, it shows a hint to use Manage Repos.
    config_repo_show_status

    # Display the main menu and capture user's choice
    # ui_menu echoes the TEXT of the selected option to stdout
    ACTION=$(ui_menu "Main Menu" \
        "📥  Clone Remote Repo" \
        "📤  Push Changes (keep deleted files)" \
        "📤  Push All Changes (including deletions)" \
        "🔄  Hard Reset to Remote (⚠️  destructive)" \
        "📋  Copy from Another Repo" \
        "📂  Manage Repos (add/remove/switch)" \
        "❌  Quit")

    # 'case' is bash's version of switch/case from other languages.
    # It matches the string against each pattern and runs the matching block.
    # Each block ends with ;; (like 'break' in other languages).
    case "$ACTION" in

        "📥  Clone Remote Repo")
            clear
            core_clone_repo
            ;;

        "📤  Push Changes (keep deleted files)")
            clear
            core_push_no_delete
            ;;

        "📤  Push All Changes (including deletions)")
            clear
            core_push_full
            ;;

        "🔄  Hard Reset to Remote (⚠️  destructive)")
            clear
            core_hard_reset
            ;;

        "📋  Copy from Another Repo")
            clear
            core_copy_from_repo
            ;;

        "📂  Manage Repos (add/remove/switch)")
            # core_manage_repos has its own sub-menu loop
            # so we don't need the "Press Enter" pause after it
            core_manage_repos
            continue    # Skip the pause, go straight back to main menu
            ;;

        "❌  Quit")
            echo >&2
            ui_info "Goodbye! Happy coding 🚀"
            echo >&2
            exit 0
            ;;
    esac

    # Pause so user can read the output before screen clears
    echo >&2
    read -r -p "  Press Enter to return to menu..."
done
