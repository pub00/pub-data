#!/bin/bash
# ==============================================================================
# lib/core.sh — Core Chrome Profile Operations
# ==============================================================================
#
# PURPOSE:
#   All the actual profile management happens here — create, switch, delete,
#   restore, launch, list. Each function handles one menu action end-to-end.
#
# HOW THE SYMLINK TRICK WORKS:
#   Chrome reads its active profile from ~/.config/google-chrome/Default/
#   Instead of having one real Default/ directory, we:
#   1. Move the original Default/ → Default_Backup/ (once, for safekeeping)
#   2. Create a SYMLINK named "Default" pointing to ~/chrome-profiles/<name>/Default
#   3. Chrome follows the symlink and uses that profile's data
#   4. Switching = delete old symlink + create new one pointing elsewhere
#
# REQUIRES: lib/ui.sh and lib/config.sh must be sourced first.
# ==============================================================================


# ==============================================================================
# DEPENDENCY CHECK
# ==============================================================================

# --- core_check_deps ---
# Verifies Google Chrome is installed. If missing, shows install commands.
# This is the FIRST thing that runs — if Chrome isn't installed, the
# entire tool is useless, so we exit immediately.
#
# 'command -v' returns the path to an executable (or fails if not found).
# It's more portable than 'which' (which isn't POSIX-guaranteed).
core_check_deps() {
    local missing=()

    # 1. Check for Google Chrome
    if ! config_detect_chrome; then
        ui_error "Google Chrome is not installed!"
        ui_warn "Install it with one of these methods:"
        echo -e "  ${C_DIM}Ubuntu/Debian:${C_RESET}  wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && sudo dpkg -i google-chrome-stable_current_amd64.deb" >&2
        echo -e "  ${C_DIM}Arch (AUR):${C_RESET}     yay -S google-chrome" >&2
        echo -e "  ${C_DIM}Fedora:${C_RESET}         sudo dnf install google-chrome-stable" >&2
        exit 1
    fi

    # 2. Check for critical system tools
    # pgrep: for process detection (safety)
    # mountpoint: for vault status check
    # du/awk: for size calculation
    local tools=("pgrep" "mountpoint" "du" "awk" "readlink")
    local tool
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        ui_error "Missing required system tools: ${missing[*]}"
        ui_warn "Please install them via your package manager."
        exit 1
    fi

    return 0
}


# ==============================================================================
# BACKUP MANAGEMENT
# ==============================================================================

# --- core_ensure_backup ---
# One-time safety operation: backs up the original Default/ profile.
#
# WHEN THIS RUNS:
#   On first launch, Default/ is a real directory (Chrome's original profile).
#   We MOVE it to Default_Backup/ so we can replace Default/ with a symlink.
#   On subsequent launches, Default/ is already a symlink, so this does nothing.
#
# WHY MOVE (NOT COPY)?
#   1. Chrome profile dirs can be 1-5 GB — copying would be slow
#   2. We need Default/ to be GONE so we can create a symlink in its place
#   3. The backup preserves the original exactly (permissions, timestamps)
#
# IDEMPOTENT: Does nothing if backup already exists or Default/ is a symlink.
core_ensure_backup() {
    # If Default_Backup already exists, we've already done this before
    if [[ -d "$BACKUP_FOLDER" ]]; then
        return 0
    fi

    # If Default is a symlink, no backup needed (we're already managing it)
    # -L tests if the path IS a symbolic link
    if [[ -L "$DEFAULT_FOLDER" ]]; then
        return 0
    fi

    # If Default is a real directory, back it up
    if [[ -d "$DEFAULT_FOLDER" ]]; then
        ui_info "First run detected — backing up original Chrome profile..."
        ui_spinner_start "Moving Default/ → Default_Backup/ ..."

        # 'mv' is atomic on the same filesystem (instant rename, not copy)
        if mv "$DEFAULT_FOLDER" "$BACKUP_FOLDER"; then
            ui_spinner_stop
            ui_success "Original profile backed up to Default_Backup/"
        else
            ui_spinner_stop
            ui_error "Failed to back up original profile!"
            ui_error "Check permissions on: ${CHROME_CONFIG}"
            read -r -p "  Press Enter to exit..."
            exit 1
        fi
    fi
}


# ==============================================================================
# DASHBOARD STATUS DISPLAY
# ==============================================================================

# --- core_show_status ---
# Shows the current state on the main dashboard.
# Displays: active profile, profile count, Chrome binary, symlink target.
#
# This is called from the main menu loop (like config_repo_show_status
# in Git Helper) so the user always knows the current state.
core_show_status() {
    local active
    active=$(config_get_active_profile)
    local count
    count=$(config_profile_count)

    # Show Chrome binary info
    echo -e "  ${C_DIM}Chrome: ${CHROME_BIN}${C_RESET}" >&2

    # Show active profile with visual indicators
    if [[ -z "$active" ]]; then
        echo -e "  ${C_RED}(*)${C_RESET} ${C_DIM}No profile linked (Default/ is missing)${C_RESET}" >&2
    elif [[ "$active" == "ORIGINAL" ]]; then
        echo -e "  ${C_GREEN}(*)${C_RESET} ${C_BOLD}Active:${C_RESET} ${C_CYAN}Original Chrome Profile${C_RESET}" >&2
    else
        # Show active profile name and its size
        local size
        size=$(config_get_profile_size "$active")
        echo -e "  ${C_GREEN}(*)${C_RESET} ${C_BOLD}Active:${C_RESET} ${C_CYAN}${active}${C_RESET} ${C_DIM}(${size})${C_RESET}" >&2

        # Also show the actual symlink target for transparency
        local target
        target=$(readlink "$DEFAULT_FOLDER" 2>/dev/null)
        [[ -n "$target" ]] && echo -e "    ${C_DIM}--> ${target}${C_RESET}" >&2
    fi

    echo -e "  ${C_DIM}Profiles: ${count} registered${C_RESET}" >&2
    echo >&2
}


# ==============================================================================
# FEATURE 1: Create New Profile
# ==============================================================================

# --- core_create_profile ---
# Creates a new Chrome profile from an email address.
#
# FLOW:
#   1. Ask for email address
#   2. Auto-generate profile name (Account_<username>)
#   3. Let user customize the name if they want
#   4. Check for duplicates
#   5. Create the directory structure
#   6. Register in profiles.conf
#   7. Offer to switch to the new profile immediately
#
# The profile starts EMPTY. When Chrome launches with it, Chrome will
# create all necessary files (cookies, history, extensions, etc.)
# and prompt the user to sign into their Google account.
core_create_profile() {
    ui_header "[NEW] Create New Profile"

    # --- Step 1: Get email ---
    local email
    email=$(ui_input "Google account email")
    if [[ $? -ne 0 || -z "$email" ]]; then
        ui_warn "Cancelled."
        return 1
    fi

    # --- Step 2: Auto-generate name from email ---
    # config_email_to_name handles: extract username, lowercase, sanitize
    local auto_name
    auto_name=$(config_email_to_name "$email")

    echo >&2
    ui_info "Auto-generated name: ${C_CYAN}${auto_name}${C_RESET}"

    # --- Step 3: Let user customize if they want ---
    local profile_name
    profile_name=$(ui_input "Profile name (edit or press Enter)" "$auto_name")
    if [[ $? -ne 0 || -z "$profile_name" ]]; then
        profile_name="$auto_name"
    fi

    # --- Step 4: Check for duplicates ---
    if config_profile_exists "$profile_name"; then
        ui_error "Profile '${profile_name}' already exists!"
        return 1
    fi

    # Also check if the directory exists on disk (even if not registered)
    local profile_path
    profile_path=$(config_get_profile_path "$profile_name")
    if [[ -d "$profile_path" ]]; then
        ui_warn "Directory already exists: ${profile_path}"
        if ! ui_confirm "Use existing directory?" "Y"; then
            return 1
        fi
    fi

    # --- Step 5: Create directory structure ---
    # mkdir -p creates parent directories too:
    # ~/chrome-profiles/Account_sami/Default/
    # The -p flag means "no error if existing, make parents as needed"
    if ! mkdir -p "$profile_path"; then
        ui_error "Failed to create profile directory: ${profile_path}"
        return 1
    fi

    # --- Step 6: Register in profiles.conf ---
    config_add_profile "$profile_name"

    ui_divider
    ui_success "Profile created: ${C_CYAN}${profile_name}${C_RESET}"
    ui_info "Location: ${C_DIM}${profile_path}${C_RESET}"
    ui_info "Email: ${C_DIM}${email}${C_RESET}"
    echo >&2

    # --- Step 7: Offer to switch immediately ---
    if ui_confirm "Switch to this profile now?" "Y"; then
        _do_switch "$profile_name"
    fi
}


# ==============================================================================
# FEATURE 2: Switch Profile
# ==============================================================================

# --- core_switch_profile ---
# Shows all profiles and lets the user pick one to switch to.
# Handles the symlink swap with safety checks.
core_switch_profile() {
    ui_header "[SW ] Switch Profile"

    # --- Build profile list ---
    local profiles=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && profiles+=("$line")
    done < "$PROFILES_REGISTRY"

    # Add the "Restore Original" option if backup exists
    if [[ -d "$BACKUP_FOLDER" ]]; then
        profiles+=("[ORG] ORIGINAL (restore backup)")
    fi

    local count=${#profiles[@]}
    if (( count == 0 )); then
        ui_warn "No profiles found. Create one first!"
        return 1
    fi

    # --- Show profiles with details ---
    local active
    active=$(config_get_active_profile)

    echo -e "\n  ${C_BOLD}Available Profiles:${C_RESET}" >&2
    ui_divider

    local i
    for (( i=0; i<count; i++ )); do
        local name="${profiles[$i]}"

        # Handle the special "original" option
        if [[ "$name" == "[ORG] ORIGINAL (restore backup)" ]]; then
            local marker=""
            [[ "$active" == "ORIGINAL" ]] && marker=" <-- active"
            echo -e "  ${C_CYAN}$((i+1)))${C_RESET} ${C_BOLD}${name}${C_RESET}${marker}" >&2
            continue
        fi

        # Regular profile: show name, size, and active marker
        local size
        size=$(config_get_profile_size "$name")
        local marker=""
        [[ "$name" == "$active" ]] && marker=" <-- active"

        echo -e "  ${C_CYAN}$((i+1)))${C_RESET} ${C_BOLD}${name}${C_RESET} ${C_DIM}(${size})${C_RESET}${marker}" >&2
    done
    echo >&2

    # --- Get user's choice ---
    local choice
    while true; do
        echo -en "  ${C_YELLOW}>${C_RESET} Choose [1-${count}]: " >&2
        read -r choice

        [[ -z "$choice" ]] && return 1

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            break
        fi
        ui_error "Invalid choice."
    done

    local selected="${profiles[$((choice-1))]}"

    # --- Handle "Restore Original" ---
    if [[ "$selected" == "[ORG] ORIGINAL (restore backup)" ]]; then
        core_restore_original
        return $?
    fi

    # --- Check if already active ---
    if [[ "$selected" == "$active" ]]; then
        ui_info "This profile is already active."
        return 0
    fi

    # --- Do the switch ---
    _do_switch "$selected"
}


# --- _do_switch ---
# Internal helper that performs the actual symlink swap.
# Separated from core_switch_profile so core_create_profile can reuse it.
#
# STEPS:
#   1. Check if Chrome is running (CRITICAL safety check)
#   2. Remove old symlink (or backup real Default/)
#   3. Create new symlink pointing to the chosen profile
#   4. Verify the symlink works
#   5. Offer to launch Chrome
#
# Prefixed with _ to indicate it's "private" (convention, not enforced).
_do_switch() {
    local profile_name="$1"
    local profile_path
    profile_path=$(config_get_profile_path "$profile_name")

    # --- Safety Check: Is Chrome running? ---
    # Switching while Chrome is running causes data corruption!
    # Chrome holds file locks on the profile directory.
    if config_is_chrome_running; then
        echo >&2
        ui_error "${C_RED}Chrome is currently running!${C_RESET}"
        ui_warn "Switching profiles while Chrome is open can ${C_RED}corrupt${C_RESET} your data."
        ui_warn "Please close Chrome first, then try again."
        echo >&2

        if ! ui_confirm "Force switch anyway? (NOT recommended)" "N"; then
            ui_warn "Switch cancelled. Close Chrome and try again."
            return 1
        fi
        ui_warn "Proceeding despite Chrome running — be careful!"
    fi

    # --- Ensure profile directory exists ---
    if [[ ! -d "$profile_path" ]]; then
        mkdir -p "$profile_path"
    fi

    # --- Handle current Default/ ---
    # Case 1: Default is a symlink → just remove it
    if [[ -L "$DEFAULT_FOLDER" ]]; then
        # rm removes the symlink itself, NOT what it points to
        rm "$DEFAULT_FOLDER"

    # Case 2: Default is a real directory → back it up first
    elif [[ -d "$DEFAULT_FOLDER" ]]; then
        if [[ ! -d "$BACKUP_FOLDER" ]]; then
            ui_info "Backing up original profile..."
            mv "$DEFAULT_FOLDER" "$BACKUP_FOLDER"
        else
            ui_error "Default/ exists as a real directory AND backup already exists."
            ui_error "Cannot proceed safely. Please resolve manually."
            return 1
        fi
    fi

    # --- Create new symlink ---
    # 'ln -s TARGET LINK_NAME' creates a symbolic link.
    # -s = symbolic (soft link). Without -s, it creates a hard link.
    # After this: Default/ → ~/chrome-profiles/<name>/Default
    if ! ln -s "$profile_path" "$DEFAULT_FOLDER"; then
        ui_error "Failed to create symlink!"
        ui_error "  ${DEFAULT_FOLDER} → ${profile_path}"

        # Try to restore backup if we just broke things
        if [[ -d "$BACKUP_FOLDER" && ! -e "$DEFAULT_FOLDER" ]]; then
            ui_warn "Attempting to restore backup..."
            mv "$BACKUP_FOLDER" "$DEFAULT_FOLDER"
        fi
        return 1
    fi

    # --- Verify ---
    ui_divider
    ui_success "Switched to: ${C_CYAN}${profile_name}${C_RESET}"
    ui_info "Symlink: ${C_DIM}${DEFAULT_FOLDER} → ${profile_path}${C_RESET}"
    echo >&2

    # --- Offer to launch Chrome ---
    if ui_confirm "Launch Chrome now?" "Y"; then
        core_launch_chrome
    fi
}


# ==============================================================================
# FEATURE 3: Restore Original Profile
# ==============================================================================

# --- core_restore_original ---
# Restores the original Chrome profile from Default_Backup/.
#
# FLOW:
#   1. Check if Chrome is running (safety)
#   2. Remove the current symlink
#   3. Move Default_Backup/ back to Default/
#   4. The original profile is now active again
#
# After this, Chrome behaves as if G-Manager was never used.
core_restore_original() {
    ui_header "[ORG] Restore Original Profile"

    # Check if backup exists
    if [[ ! -d "$BACKUP_FOLDER" ]]; then
        ui_error "No backup found at: ${BACKUP_FOLDER}"
        ui_warn "The original profile may have never been backed up."
        return 1
    fi

    # Check if already restored (Default is a real directory, not a symlink)
    if [[ -d "$DEFAULT_FOLDER" && ! -L "$DEFAULT_FOLDER" ]]; then
        ui_info "Original profile is already active (Default/ is a real directory)."
        return 0
    fi

    # Safety check: Chrome running?
    if config_is_chrome_running; then
        ui_error "Chrome is currently running! Close it first."
        return 1
    fi

    if ! ui_confirm "Restore original Chrome profile?" "Y"; then
        ui_warn "Cancelled."
        return 0
    fi

    # Remove the current symlink (if it is one)
    if [[ -L "$DEFAULT_FOLDER" ]]; then
        rm "$DEFAULT_FOLDER"
    fi

    # Move backup back to Default/
    if mv "$BACKUP_FOLDER" "$DEFAULT_FOLDER"; then
        ui_success "Original profile restored successfully!"
        ui_info "Chrome will now use your original account."
    else
        ui_error "Failed to restore! Check permissions."
        return 1
    fi
}


# ==============================================================================
# FEATURE 4: Delete a Profile
# ==============================================================================

# --- core_delete_profile ---
# Permanently deletes a profile (directory + registry entry).
#
# SAFETY:
#   - Double-confirmation because this is DESTRUCTIVE (rm -rf)
#   - If the deleted profile was active, we offer to switch/restore
#   - Never deletes the original backup
core_delete_profile() {
    ui_header "[DEL] Delete a Profile"
    echo -e "  ${C_RED}[!!] This permanently deletes a profile and all its data.${C_RESET}" >&2
    echo >&2

    # --- Build profile list ---
    local profiles=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && profiles+=("$line")
    done < "$PROFILES_REGISTRY"

    local count=${#profiles[@]}
    if (( count == 0 )); then
        ui_warn "No profiles to delete."
        return 1
    fi

    # --- Show profiles ---
    local active
    active=$(config_get_active_profile)

    local i
    for (( i=0; i<count; i++ )); do
        local name="${profiles[$i]}"
        local size
        size=$(config_get_profile_size "$name")
        local marker=""
        [[ "$name" == "$active" ]] && marker=" <-- ACTIVE"
        echo -e "  ${C_CYAN}$((i+1)))${C_RESET} ${name} ${C_DIM}(${size})${C_RESET}${marker}" >&2
    done
    echo >&2

    # --- Get choice ---
    local choice
    while true; do
        echo -en "  ${C_YELLOW}>${C_RESET} Choose profile to delete [1-${count}]: " >&2
        read -r choice
        [[ -z "$choice" ]] && return 1
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            break
        fi
        ui_error "Invalid choice."
    done

    local selected="${profiles[$((choice-1))]}"
    local selected_path="${PROFILES_DIR}/${selected}"

    # --- Double confirmation ---
    echo >&2
    ui_warn "About to delete: ${C_RED}${selected}${C_RESET}"
    ui_warn "Location: ${C_DIM}${selected_path}${C_RESET}"

    if ! ui_confirm "Are you SURE you want to delete '${selected}'?" "N"; then
        ui_warn "Cancelled."
        return 0
    fi
    if ! ui_confirm "This cannot be undone. Proceed?" "N"; then
        ui_warn "Cancelled."
        return 0
    fi

    # --- If this is the active profile, handle the symlink first ---
    if [[ "$selected" == "$active" ]]; then
        ui_warn "This is the currently active profile!"
        # Remove the symlink so Chrome doesn't point to a deleted directory
        if [[ -L "$DEFAULT_FOLDER" ]]; then
            rm "$DEFAULT_FOLDER"
        fi

        # Try to restore original, or leave Default/ missing
        if [[ -d "$BACKUP_FOLDER" ]]; then
            mv "$BACKUP_FOLDER" "$DEFAULT_FOLDER"
            ui_info "Restored original profile as active."
        else
            ui_warn "No backup found. Default/ is now missing — create or switch to a profile."
        fi
    fi

    # --- Delete the profile directory ---
    # rm -rf: -r = recursive (delete dirs), -f = force (no prompts)
    if rm -rf "$selected_path"; then
        # Remove from registry
        config_remove_profile "$selected"
        ui_success "Profile '${selected}' deleted permanently."
    else
        ui_error "Failed to delete: ${selected_path}"
        return 1
    fi
}


# ==============================================================================
# FEATURE 5: Launch Chrome
# ==============================================================================

# --- core_launch_chrome ---
# Launches Google Chrome in the background, detached from the terminal.
#
# 'disown' removes the process from the shell's job table.
# Without disown, closing the terminal would also kill Chrome.
# '&>/dev/null' suppresses Chrome's console output (it's very noisy).
# '&' sends the process to the background.
core_launch_chrome() {
    local active
    active=$(config_get_active_profile)

    if [[ -z "$active" ]]; then
        ui_error "No profile is active! Switch to a profile first."
        return 1
    fi

    ui_info "Launching Chrome with profile: ${C_CYAN}${active}${C_RESET}"

    # Launch Chrome in the background, detached from terminal
    # &>/dev/null = redirect both stdout and stderr to /dev/null
    # & = run in background
    # disown = detach from shell (survives terminal close)
    "$CHROME_BIN" &>/dev/null &
    disown

    ui_success "Chrome launched! [RUN]"
}


# ==============================================================================
# FEATURE 6: List All Profiles
# ==============================================================================

# --- core_list_all ---
# Pretty-prints all registered profiles with details.
# Shows: name, size, active status, directory path.
core_list_all() {
    ui_header "[LS ] All Registered Profiles"

    local profiles=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && profiles+=("$line")
    done < "$PROFILES_REGISTRY"

    local count=${#profiles[@]}
    if (( count == 0 )); then
        ui_warn "No profiles registered."
        ui_info "Use ${C_CYAN}Create New Profile${C_RESET} to add one."
        return 0
    fi

    local active
    active=$(config_get_active_profile)

    # --- Table header ---
    echo -e "  ${C_BOLD}${C_WHITE}  #  Profile Name                      Size     Status${C_RESET}" >&2
    ui_divider

    local i
    for (( i=0; i<count; i++ )); do
        local name="${profiles[$i]}"
        local size
        size=$(config_get_profile_size "$name")
        local status="${C_DIM}inactive${C_RESET}"
        local path
        path=$(config_get_profile_path "$name")

        # Check if this is the active profile
        if [[ "$name" == "$active" ]]; then
            status="${C_GREEN}(*) active${C_RESET}"
        fi

        # Check if directory exists on disk
        if [[ ! -d "${PROFILES_DIR}/${name}" ]]; then
            status="${C_RED}(X) missing${C_RESET}"
        fi

        # printf for aligned columns
        # %-35s = left-aligned, 35 chars wide (pads with spaces)
        # We use echo -e for color support (printf doesn't expand \033)
        echo -e "  ${C_CYAN}$(printf '%2d' $((i+1))))${C_RESET} $(printf '%-35s' "$name") ${C_DIM}$(printf '%-8s' "$size")${C_RESET} ${status}" >&2
        echo -e "       ${C_DIM}${path}${C_RESET}" >&2
    done

    echo >&2
    echo -e "  ${C_DIM}Total: ${count} profile(s)${C_RESET}" >&2

    # Show backup status
    if [[ -d "$BACKUP_FOLDER" ]]; then
        local backup_size
        backup_size=$(du -sh "$BACKUP_FOLDER" 2>/dev/null | awk '{print $1}')
        echo -e "  ${C_DIM}Original backup: ${backup_size} (Default_Backup/)${C_RESET}" >&2
    fi
}
