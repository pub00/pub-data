#!/bin/bash
# ==============================================================================
# lib/config.sh — Profile Registry, Path Management & Settings
# ==============================================================================
#
# PURPOSE:
#   Manages all the data/configuration for G-Manager:
#   - Chrome binary detection (where is google-chrome installed?)
#   - Profile directory management (create, list, remove profile dirs)
#   - Persistent registry (profiles.conf — one profile name per line)
#   - Active profile detection (reads the symlink to know what's active)
#   - Auto-import of existing profiles from ~/chrome-profiles/
#
# WHY SEPARATE THIS?
#   The old script had hardcoded account names and paths scattered everywhere.
#   This module centralizes ALL path logic so:
#   1. If Chrome changes its config path, fix it in ONE place
#   2. Profile registry survives between script runs
#   3. Adding a new profile doesn't require editing the script
#
# REQUIRES: lib/ui.sh must be sourced first (for ui_info, ui_warn, etc.)
# ==============================================================================


# ==============================================================================
# PATHS & CONSTANTS
# ==============================================================================
# These define where everything lives on disk.
# Using readonly ensures they can't be accidentally changed mid-run.
#
# CHROME_CONFIG:  Where Chrome stores its configuration (standard Linux path).
# DEFAULT_FOLDER: The "Default" profile directory Chrome actively uses.
#                 This is what we swap via symlinks.
# BACKUP_FOLDER:  Where we move the ORIGINAL Default/ for safekeeping.
#                 Without this, switching profiles would destroy the original.
# PROFILES_DIR:   Our storage area for all isolated profile directories.
#                 [!!] THIS IS AN ENCRYPTED VAULT MOUNT POINT [!!]
#                 The profiles live inside a Secure Manager vault at:
#                 ~/chrome_profiles/.chrome_profiles/chrome_profiles
#                 This means profiles are encrypted at rest — they're only
#                 accessible when the vault is unlocked (mounted).
#                 Each profile gets a subfolder with its own "Default/" inside.
# CONFIG_DIR:     XDG-compliant config directory for G-Manager's own settings.
#                 Keeps $HOME clean (no dotfiles cluttering ls).
# PROFILES_REGISTRY: Plain text file — one profile name per line.
#                    This is how we "remember" what profiles exist.

# Resolve Secure Manager vault configuration dynamically if present.
# G-Manager can store profiles inside a vault named "chrome_profiles" managed by Secure Manager.
SEC_MGR_CONFIG="$HOME/.secure_manager_config"
RESOLVED_PROFILES_DIR=""
RESOLVED_VAULT_PARENT=""

if [[ -f "$SEC_MGR_CONFIG" ]]; then
    # Look for a vault named "chrome_profiles"
    # Format: name|enc|dec
    line=$(grep "^chrome_profiles|" "$SEC_MGR_CONFIG" 2>/dev/null | head -n 1)
    if [[ -n "$line" ]]; then
        RESOLVED_PROFILES_DIR=$(echo "$line" | cut -d'|' -f3)
        enc_path=$(echo "$line" | cut -d'|' -f2)
        RESOLVED_VAULT_PARENT=$(dirname "$enc_path")
    fi
fi

# Fallbacks if not resolved from config
if [[ -z "$RESOLVED_PROFILES_DIR" ]]; then
    RESOLVED_PROFILES_DIR="$HOME/.chrome_profiles/chrome_profiles"
fi
if [[ -z "$RESOLVED_VAULT_PARENT" ]]; then
    RESOLVED_VAULT_PARENT="$HOME/.chrome_profiles"
fi

readonly CHROME_CONFIG="${G_CHROME_CONFIG:-$HOME/.config/google-chrome}"
readonly DEFAULT_FOLDER="$CHROME_CONFIG/Default"
readonly BACKUP_FOLDER="$CHROME_CONFIG/Default_Backup"
readonly PROFILES_DIR="${G_PROFILES_DIR:-$RESOLVED_PROFILES_DIR}"
readonly CONFIG_DIR="${G_CONFIG_DIR:-$HOME/.config/g_manager}"
readonly PROFILES_REGISTRY="$CONFIG_DIR/profiles.conf"
readonly VAULT_PARENT="${RESOLVED_VAULT_PARENT}"

# CHROME_BIN is set by config_detect_chrome() at startup.
# We don't make it readonly because it's set AFTER this file is sourced.
# It holds the full path to the Chrome binary (e.g., /usr/bin/google-chrome).
CHROME_BIN=""


# ==============================================================================
# INITIALIZATION
# ==============================================================================

# --- config_init ---
# Ensures the app config directory and registry file exist.
# 'mkdir -p' creates parent directories if needed AND is safe if they exist.
# 'touch' creates empty files if missing, does nothing if they exist.
#
# NOTE: We do NOT create PROFILES_DIR here!
#   PROFILES_DIR is a vault mount point managed by Secure Manager.
#   If the vault isn't mounted, the directory either won't exist or
#   won't be writable. We check that separately in config_check_vault().
#
# This function is IDEMPOTENT: calling it 100 times has the same effect
# as calling it once. This is important because it runs every time the
# tool launches.
config_init() {
    # Create the app config directory (~/.config/g_manager/)
    # This is G-Manager's own config — NOT the encrypted vault.
    mkdir -p "$CONFIG_DIR"

    # Create the registry file if it doesn't exist
    # 'touch' is safe — it doesn't overwrite existing content
    touch "$PROFILES_REGISTRY"
}


# ==============================================================================
# VAULT STATUS CHECK
# ==============================================================================

# --- config_check_vault ---
# Checks if the encrypted vault (Secure Manager) is mounted and accessible.
# This MUST be called before any profile operation — if the vault is locked,
# profile directories are inaccessible (encrypted on disk).
#
# DETECTION LOGIC (3 states):
#   The vault uses gocryptfs (FUSE-based encryption).
#   The encrypted data lives in:  ~/chrome_profiles/.chrome_profiles/data/
#   The mount point (decrypted) is: ~/chrome_profiles/.chrome_profiles/chrome_profiles
#
#   STATE A: Vault NEVER CREATED
#     The parent .chrome_profiles/ directory doesn't exist at all.
#     → Show Secure Manager setup instructions.
#
#   STATE B: Vault EXISTS but is LOCKED (not mounted)
#     The parent directory exists (holds encrypted data), but gocryptfs
#     hasn't mounted the decrypted filesystem onto the mount point.
#     We detect this with 'mountpoint -q' — the definitive check.
#     → Tell user to open the vault first.
#
#   STATE C: Vault is UNLOCKED (mounted)
#     'mountpoint -q' confirms the FUSE filesystem is mounted.
#     → Good to go, even if empty (fresh vault).
#
# WHY 'mountpoint -q' AND NOT '-w' (writable check)?
#   The mount point directory CAN be writable even when the vault is LOCKED.
#   If someone created the directory with normal permissions, -w returns true
#   but the vault isn't actually mounted — you'd be writing to the raw
#   directory, NOT the encrypted filesystem. This is a false positive.
#
#   'mountpoint -q' checks if a FILESYSTEM is actually mounted at that path.
#   It's part of util-linux (available on every Linux distro).
#   The -q flag = quiet (no output, just exit code: 0=mounted, 1=not).
#   This is the SAME check your Secure Manager toggle script uses.
config_check_vault() {
    # The parent directory that Secure Manager creates for the vault.
    # This holds: data/ (encrypted files), chrome_profiles/ (mount point),
    # icons/, and the toggle script.
    # Resolved dynamically from the secure manager config.
    local vault_parent="${VAULT_PARENT}"

    # --- STATE A: Vault was never created ---
    # If the parent directory doesn't exist, the user has never set up
    # a vault here with Secure Manager.
    if [[ ! -d "$vault_parent" ]]; then
        ui_error "No encrypted vault found!"
        echo >&2
        ui_warn "G-Manager stores Chrome profiles inside an encrypted vault"
        ui_warn "for security. You need to create one first."
        echo >&2
        echo -e "  ${C_BOLD}Setup Instructions:${C_RESET}" >&2
        echo -e "    ${C_CYAN}1.${C_RESET} Open ${C_BOLD}Secure Manager${C_RESET}" >&2
        echo -e "    ${C_CYAN}2.${C_RESET} Choose ${C_BOLD}Create New Vault${C_RESET}" >&2
        echo -e "    ${C_CYAN}3.${C_RESET} Set location to:  ${C_CYAN}$HOME${C_RESET}" >&2
        echo -e "    ${C_CYAN}4.${C_RESET} Set vault name to: ${C_CYAN}.chrome_profiles${C_RESET}" >&2
        echo -e "    ${C_CYAN}5.${C_RESET} Unlock the vault, then run G-Manager again" >&2
        return 1
    fi

    # --- STATE B: Vault exists but is LOCKED (not mounted) ---
    # 'mountpoint -q' is the definitive check for whether gocryptfs
    # has mounted the decrypted filesystem at the mount point.
    #   -q = quiet mode (no output, just exit code)
    #   exit 0 = IS a mount point (vault is open)
    #   exit 1 = NOT a mount point (vault is locked)
    if ! mountpoint -q "$PROFILES_DIR" 2>/dev/null; then
        echo >&2
        ui_error "Vault is locked! [LOCKED]  Open the vault first before using G-Manager."
        return 1
    fi

    # --- STATE C: Vault is UNLOCKED (mounted) ---
    # mountpoint confirmed the FUSE filesystem is mounted.
    # Even if it's empty, that just means no profiles created yet (fresh).
    return 0
}


# ==============================================================================
# CHROME DETECTION
# ==============================================================================

# --- config_detect_chrome ---
# Searches for a Chrome binary on the system.
# Tries multiple names because different distros package Chrome differently:
#   - google-chrome       → most common (Ubuntu, Debian, Fedora)
#   - google-chrome-stable → some distros use this variant
#
# 'command -v' returns the path to an executable (or fails if not found).
# It's more portable than 'which' (which isn't POSIX-guaranteed).
#
# Sets the global CHROME_BIN variable to the found binary path.
# Returns 0 (true) if found, 1 (false) if not found.
config_detect_chrome() {
    # Array of possible Chrome binary names to search for.
    # We check in priority order: official Chrome first.
    local candidates=(
        "google-chrome"
        "google-chrome-stable"
    )

    local candidate
    for candidate in "${candidates[@]}"; do
        # 'command -v' returns the full path if found (exit 0)
        # or nothing (exit 1) if not found.
        # &>/dev/null suppresses all output — we only care about the exit code.
        if command -v "$candidate" &>/dev/null; then
            CHROME_BIN="$candidate"
            return 0
        fi
    done

    # None found
    return 1
}


# ==============================================================================
# ACTIVE PROFILE DETECTION
# ==============================================================================

# --- config_get_active_profile ---
# Determines which profile is currently linked (active) by reading the symlink.
#
# HOW IT WORKS:
#   The Default/ folder is either:
#   1. A REAL DIRECTORY → original Chrome profile (not managed by us)
#   2. A SYMLINK → points to one of our profile dirs
#   3. MISSING → something went wrong
#
#   We use 'readlink' to read where the symlink points.
#   'readlink -f' follows the ENTIRE chain of symlinks to the final target.
#   Then we extract the profile name from the path using parameter expansion.
#
# RETURNS:
#   The profile name (e.g., "Account_samisaween591") via stdout.
#   Returns "ORIGINAL" if Default/ is a real directory (not a symlink).
#   Returns 1 if Default/ is missing.
config_get_active_profile() {
    # --- Case 1: Default doesn't exist at all ---
    if [[ ! -e "$DEFAULT_FOLDER" && ! -L "$DEFAULT_FOLDER" ]]; then
        # -e checks if it exists (follows symlinks)
        # -L checks if it's a symlink (even a broken one)
        # We check BOTH because a broken symlink passes -L but fails -e
        return 1
    fi

    # --- Case 2: Default is a real directory (not a symlink) ---
    # -L returns true if the path IS a symlink
    # ! -L means "is NOT a symlink" — so it's a real directory
    if [[ ! -L "$DEFAULT_FOLDER" ]]; then
        echo "ORIGINAL"
        return 0
    fi

    # --- Case 3: Default IS a symlink — read where it points ---
    local target
    # readlink -f resolves the FULL path (follows all symlink chains)
    target=$(readlink -f "$DEFAULT_FOLDER" 2>/dev/null)

    if [[ -z "$target" ]]; then
        return 1
    fi

    # Extract the profile name from the path.
    # Path looks like: /home/user/chrome-profiles/Account_sami/Default
    # We want: Account_sami
    #
    # dirname "$target"  →  /home/user/chrome-profiles/Account_sami
    # basename "..."     →  Account_sami
    local profile_dir
    profile_dir=$(dirname "$target")
    local profile_name
    profile_name=$(basename "$profile_dir")

    echo "$profile_name"
    return 0
}


# ==============================================================================
# PROFILE REGISTRY (profiles.conf)
# ==============================================================================
# The registry is a simple text file with one profile name per line.
# This lets us "remember" what profiles exist even if the user hasn't
# launched the tool in a while.

# --- config_list_profiles ---
# Returns all registered profile names, one per line.
# Returns 1 (error) if no profiles exist — useful for quick checks:
#   if ! config_list_profiles >/dev/null; then echo "no profiles"; fi
#
# We filter out empty lines with [[ -n "$line" ]] to handle edge cases
# like trailing newlines in the file.
config_list_profiles() {
    # -s = file exists AND is not empty (has size > 0)
    if [[ ! -s "$PROFILES_REGISTRY" ]]; then
        return 1    # No profiles registered
    fi

    # Read each line and print non-empty ones
    # IFS= prevents 'read' from trimming leading/trailing whitespace
    # -r prevents backslash interpretation
    while IFS= read -r line; do
        [[ -n "$line" ]] && echo "$line"
    done < "$PROFILES_REGISTRY"
}

# --- config_profile_count ---
# Returns the number of registered profiles as a number.
# 'grep -c' counts matching lines. '.' matches any non-empty line.
# We use || echo "0" as a fallback in case the file doesn't exist.
config_profile_count() {
    if [[ ! -s "$PROFILES_REGISTRY" ]]; then
        echo "0"
        return
    fi
    grep -c '.' "$PROFILES_REGISTRY" 2>/dev/null || echo "0"
}

# --- config_add_profile ---
# Adds a profile name to the registry.
# Usage: config_add_profile "Account_samisaween591"
#
# DEDUPLICATION:
#   grep -qxF "$name" prevents adding the same profile twice.
#   -q = quiet (don't print, just set exit code)
#   -x = match the WHOLE line (not partial — "/home" won't match "/home/user")
#   -F = fixed string (treat as literal text, not regex)
config_add_profile() {
    local name="$1"

    # Check if already registered
    if grep -qxF "$name" "$PROFILES_REGISTRY" 2>/dev/null; then
        # Already exists — not an error, just skip silently
        return 0
    fi

    # Append the profile name to the registry
    # >> = append (don't overwrite existing content)
    echo "$name" >> "$PROFILES_REGISTRY"
}

# --- config_remove_profile ---
# Removes a profile name from the registry.
# Usage: config_remove_profile "Account_samisaween591"
#
# WHY NOT sed?
#   sed with special characters in the profile name can cause regex issues.
#   Instead, we rebuild the file WITHOUT the target line — simple and safe.
#   This is the same approach used in Git Helper and Secure Manager.
config_remove_profile() {
    local name="$1"

    if [[ ! -f "$PROFILES_REGISTRY" ]]; then
        return 1
    fi

    # Create a temp file, copy everything EXCEPT the target line
    local tmpfile
    tmpfile=$(mktemp)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue       # Skip empty lines
        [[ "$line" == "$name" ]] && continue  # Skip the target
        echo "$line"
    done < "$PROFILES_REGISTRY" > "$tmpfile"

    # Replace the original file with the filtered version
    mv "$tmpfile" "$PROFILES_REGISTRY"
}

# --- config_profile_exists ---
# Checks if a profile exists in the registry AND the directory exists on disk.
# Returns 0 (true) if both conditions are met, 1 (false) otherwise.
#
# WHY CHECK BOTH?
#   The registry might list a profile that was manually deleted from disk.
#   Or a directory might exist that isn't registered.
#   We need BOTH to consider a profile valid.
config_profile_exists() {
    local name="$1"

    # Check registry
    if ! grep -qxF "$name" "$PROFILES_REGISTRY" 2>/dev/null; then
        return 1
    fi

    # Check directory exists on disk
    # The actual Chrome data is inside <profile>/Default/
    if [[ ! -d "${PROFILES_DIR}/${name}/Default" ]]; then
        return 1
    fi

    return 0
}


# ==============================================================================
# PROFILE PATH HELPERS
# ==============================================================================

# --- config_get_profile_path ---
# Returns the full path to a profile's Default directory.
# Usage: path=$(config_get_profile_path "Account_sami")
#        → /home/user/chrome-profiles/Account_sami/Default
#
# Chrome expects the symlink to point to a "Default" directory,
# which is why each profile has its own Default/ subdirectory.
config_get_profile_path() {
    local name="$1"
    echo "${PROFILES_DIR}/${name}/Default"
}

# --- config_get_profile_size ---
# Returns the human-readable size of a profile directory.
# Usage: size=$(config_get_profile_size "Account_sami")
#        → "1.2G"
#
# 'du -sh' = disk usage, -s = summary (total only), -h = human-readable
# 'awk' extracts just the size number (first column) from du's output.
# The || echo "?" is a fallback if the directory doesn't exist.
config_get_profile_size() {
    local name="$1"
    local profile_path="${PROFILES_DIR}/${name}"

    if [[ -d "$profile_path" ]]; then
        du -sh "$profile_path" 2>/dev/null | awk '{print $1}'
    else
        echo "?"
    fi
}


# ==============================================================================
# CHROME PROCESS DETECTION
# ==============================================================================

# --- config_is_chrome_running ---
# Checks if Google Chrome is currently running.
# Returns 0 (true) if running, 1 (false) if not.
#
# WHY IS THIS CRITICAL?
#   Switching the symlink while Chrome is running causes DATA CORRUPTION.
#   Chrome holds file locks on the profile directory. If we swap the
#   symlink out from under it, Chrome may:
#   1. Write to the WRONG profile (the new target)
#   2. Corrupt cookies, history, or extension data
#   3. Create orphaned lock files that prevent Chrome from starting
#
# 'pgrep' searches for running processes by name.
#   -f = match against the FULL command line (not just the process name)
#   This catches both "google-chrome" and "google-chrome-stable"
# We also check for "chrome" as the actual process name differs from
# the binary name (Chrome runs as multiple "chrome" processes).
config_is_chrome_running() {
    # Check for chrome processes.
    # pgrep -x matches the EXACT process name.
    # Chrome's main process is just called "chrome" internally.
    # We also check for the full binary name variants.
    if pgrep -x "chrome" &>/dev/null; then
        return 0    # Chrome IS running
    fi
    if pgrep -x "google-chrome" &>/dev/null; then
        return 0
    fi
    if pgrep -f "google-chrome" &>/dev/null; then
        return 0
    fi

    return 1    # Chrome is NOT running
}


# ==============================================================================
# EMAIL → PROFILE NAME CONVERSION
# ==============================================================================

# --- config_email_to_name ---
# Converts an email address to a clean profile directory name.
# Usage: name=$(config_email_to_name "samisaween591@gmail.com")
#        → "Account_samisaween591"
#
# HOW IT WORKS:
#   1. Extract the part BEFORE the @ symbol
#   2. Convert to lowercase (${var,,} — bash 4+ feature)
#   3. Replace dots and special chars with underscores
#   4. Prefix with "Account_"
#
# WHY SANITIZE?
#   Directory names shouldn't contain special characters (dots, spaces, etc.)
#   that could cause issues with shell commands or filesystem operations.
#   Underscores are universally safe in directory names.
config_email_to_name() {
    local email="$1"

    # Extract username part (everything before @)
    # ${var%%pattern} removes the LONGEST match of pattern from the END.
    # So "user@gmail.com" → "user" (removes @gmail.com)
    local username="${email%%@*}"

    # Convert to lowercase
    # ${var,,} converts ALL characters to lowercase (bash 4+ feature)
    username="${username,,}"

    # Replace dots and special characters with underscores
    # tr replaces each character in SET1 with the corresponding char in SET2
    # '.+-' are common email characters that aren't safe for dir names
    username=$(echo "$username" | tr '.+-' '___')

    # Remove any remaining non-alphanumeric characters (except underscores)
    # sed 's/[^a-z0-9_]//g' strips anything that isn't a-z, 0-9, or _
    username=$(echo "$username" | sed 's/[^a-z0-9_]//g')

    # Remove leading/trailing underscores and collapse multiple underscores
    # sed 's/__*/_/g' replaces 2+ consecutive underscores with single
    # sed 's/^_//' removes leading underscore
    # sed 's/_$//' removes trailing underscore
    username=$(echo "$username" | sed 's/__*/_/g; s/^_//; s/_$//')

    # Prefix with "Account_"
    echo "Account_${username}"
}


# ==============================================================================
# AUTO-IMPORT EXISTING PROFILES
# ==============================================================================

# --- config_import_existing ---
# Scans the vault mount point for existing profile directories that aren't
# yet registered in our profiles.conf registry, and imports them automatically.
#
# PURPOSE:
#   When you run G-Manager for the first time, you may have existing profiles
#   in the vault. This function detects and imports them so you don't have
#   to manually re-add each one.
#
# HOW IT WORKS:
#   1. List all directories in ~/chrome-profiles/
#   2. Check if each has a "Default/" subdirectory (valid Chrome profile)
#   3. If not already in the registry, add it
#
# This is IDEMPOTENT — safe to run every launch. Already-registered
# profiles are silently skipped (config_add_profile handles dedup).
config_import_existing() {
    local imported=0

    # Iterate over all directories in the profiles storage
    # The glob pattern */ matches only directories (the trailing / is key)
    # We use a for loop because the number of profiles is small (< 100)
    local entry
    for entry in "${PROFILES_DIR}"/*/; do
        # Skip if the glob didn't match anything
        # When no dirs exist, bash returns the literal glob string "*/".
        [[ ! -d "$entry" ]] && continue

        # Extract just the directory name (e.g., "Account_01_samisaween591")
        # basename strips the path prefix
        local name
        name=$(basename "$entry")

        # Skip if it doesn't have a Default/ subdirectory
        # (not a valid Chrome profile structure)
        if [[ ! -d "${entry}Default" ]]; then
            continue
        fi

        # Check if already registered
        if grep -qxF "$name" "$PROFILES_REGISTRY" 2>/dev/null; then
            continue    # Already in registry, skip
        fi

        # Import: add to registry
        config_add_profile "$name"
        ui_info "Auto-imported: ${C_CYAN}${name}${C_RESET}"
        (( imported++ ))
    done

    # Only show summary if we actually imported something
    if (( imported > 0 )); then
        ui_success "Imported ${imported} existing profile(s) from ${C_DIM}${PROFILES_DIR}${C_RESET}"
    fi
}
