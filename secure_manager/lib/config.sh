#!/bin/bash
# ==============================================================================
# lib/config.sh — Vault Configuration Management
# ==============================================================================
#
# The config file stores one vault per line in this format:
#   NAME|ENCRYPTED_PATH|DECRYPTED_PATH
#
# Example:
#   Work Files|/home/user/.Work_Files/data|/home/user/.Work_Files/Work Files
#   Personal|/home/user/.Personal/data|/home/user/.Personal/Personal
#
# WHY A SEPARATE FILE FOR THIS?
#   In v1, every function did its own grep/sed on the config file directly.
#   If the format ever changes, you'd have to fix it in 10+ places.
#   Now there's ONE place that knows the format — this file.
#   Everything else just calls config_get(), config_add(), etc.
#   This is called "encapsulation" — a core principle in clean code.
#
# REQUIRES: CONFIG variable must be set before sourcing this file.
#   CONFIG="$HOME/.secure_manager_config"
# ==============================================================================


# --- config_init ---
# Ensures the config file exists. 'touch' creates it if missing,
# does nothing if it already exists. Safe to call multiple times.
config_init() {
    touch "$CONFIG"
}


# --- config_list ---
# Prints every vault entry (raw lines from the config file).
# The 'cat' isn't strictly needed (you could redirect), but it's
# readable and makes intent clear: "show me the contents."
#
# We skip empty lines with the [[ -z ]] check to be safe,
# since config files can accumulate blank lines over time.
config_list() {
    [[ ! -s "$CONFIG" ]] && return 1    # -s = "file exists AND is not empty"

    while IFS="|" read -r name enc dec; do
        [[ -z "$name" ]] && continue
        echo "${name}|${enc}|${dec}"
    done < "$CONFIG"
}


# --- config_count ---
# Returns the number of vaults in the config.
#
# grep -c counts matching lines.
# '.' matches any character = "lines that aren't empty"
# 2>/dev/null silences errors if file doesn't exist.
config_count() {
    grep -c '.' "$CONFIG" 2>/dev/null || echo "0"
}


# --- config_exists ---
# Checks if a vault name is already registered.
# Returns 0 (true) if found, 1 (false) if not.
#
# grep flags:
#   -q  = quiet, don't print matches, just set return code
#   -F  = fixed string, don't treat input as regex
#         (important! vault names might contain dots or brackets)
#   "^$1|" = starts with NAME followed by pipe
#         ^ = start of line anchor
#         This prevents "Work" from matching "Work Files"
config_exists() {
    local name="$1"
    # We use a loop with == instead of grep because:
    #   grep -F treats ^ as literal (not anchor) — breaks matching
    #   grep without -F risks regex issues with special chars in names
    #   == does exact string comparison — always safe
    while IFS="|" read -r n _ _; do
        [[ "$n" == "$name" ]] && return 0
    done < "$CONFIG" 2>/dev/null
    return 1
}


# --- config_get ---
# Retrieves a specific vault's data by name.
# Echoes: NAME|ENC_PATH|DEC_PATH
# Returns 1 if not found.
#
# grep "^$name|" finds the line starting with that exact name.
# head -n 1 ensures we only get one result (safety measure).
config_get() {
    local name="$1"
    local line
    line=$(grep "^${name}|" "$CONFIG" 2>/dev/null | head -n 1)

    if [[ -z "$line" ]]; then
        return 1
    fi

    echo "$line"
}


# --- config_get_field ---
# Gets a specific field from a vault entry.
# Usage: ENC=$(config_get_field "MyVault" 2)
#
# Fields: 1=NAME, 2=ENC_PATH, 3=DEC_PATH
#
# cut -d'|' -f$field:
#   -d'|'  = use pipe as delimiter (split on |)
#   -f2    = grab field number 2
config_get_field() {
    local name="$1"
    local field="$2"

    config_get "$name" | cut -d'|' -f"$field"
}


# --- Convenience shortcuts ---
# These make the rest of the code more readable:
#   ENC=$(config_get_enc "MyVault")
# is clearer than:
#   ENC=$(config_get_field "MyVault" 2)

config_get_enc() { config_get_field "$1" 2; }   # Encrypted data path
config_get_dec() { config_get_field "$1" 3; }   # Decrypted mount path


# --- config_add ---
# Registers a new vault in the config file.
# Usage: config_add "Work Files" "/path/to/data" "/path/to/mount"
#
# The >> (double redirect) APPENDS to the file.
# Single > would OVERWRITE the entire file (dangerous!).
config_add() {
    local name="$1"
    local enc="$2"
    local dec="$3"

    # Safety: don't add duplicates
    if config_exists "$name"; then
        return 1
    fi

    echo "${name}|${enc}|${dec}" >> "$CONFIG"
}


# --- config_remove ---
# Removes a vault entry from the config file by name.
# Usage: config_remove "Work Files"
#
# sed -i:
#   -i = "in-place" editing (modifies the file directly)
#   Without -i, sed would print to stdout and the file stays unchanged.
#
# The pattern /^NAME|/d:
#   /^..../  = match lines starting with this pattern
#   d        = delete those lines
#
# WHY we escape special chars:
#   Vault names could contain dots, brackets, etc. that have special
#   meaning in regex. 'sed' uses regex by default, so we need to
#   escape them. But since our names are user-provided and typically
#   simple, the ^ anchor + | delimiter make false matches very unlikely.
#
# A safer approach would be to rebuild the file without the target line,
# which is what the while-read loop does as a fallback.
config_remove() {
    local name="$1"

    if [[ ! -f "$CONFIG" ]]; then
        return 1
    fi

    # Build a temp file without the target line (safest approach)
    # This avoids sed regex issues with special characters in names.
    #
    # mktemp creates a unique temporary file like /tmp/tmp.Xf3kQ9
    # We write everything EXCEPT the target line to it, then replace.
    local tmpfile
    tmpfile=$(mktemp)

    while IFS="|" read -r n enc dec; do
        [[ -z "$n" ]] && continue
        [[ "$n" == "$name" ]] && continue    # Skip the one we're removing
        echo "${n}|${enc}|${dec}"
    done < "$CONFIG" > "$tmpfile"

    # mv = atomic replace (either fully succeeds or fully fails)
    # This is safer than writing directly to $CONFIG while reading it.
    mv "$tmpfile" "$CONFIG"
}


# --- config_list_names ---
# Returns just the vault names (one per line).
# Useful for building menus without exposing paths.
#
# cut -d'|' -f1 grabs everything before the first pipe.
config_list_names() {
    [[ ! -s "$CONFIG" ]] && return 1

    while IFS="|" read -r name _ _; do
        [[ -n "$name" ]] && echo "$name"
    done < "$CONFIG"
}


# --- config_get_container ---
# Returns the container directory (parent of the encrypted data folder).
# The container holds: data/, icons/, toggle_*.sh
#
# dirname "/home/user/.MyVault/data" → "/home/user/.MyVault"
config_get_container() {
    local name="$1"
    local enc
    enc=$(config_get_enc "$name")
    [[ -z "$enc" ]] && return 1
    dirname "$enc"
}
