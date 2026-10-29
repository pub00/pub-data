#!/bin/bash
# ==============================================================================
# lib/backup.sh — Vault Backup & Restore
# ==============================================================================
#
# Handles compressing the encrypted data folder into a portable .tar.gz
# Restore is handled inside vault_create() (restore mode) in vault.sh
#
# REQUIRES: source lib/ui.sh, lib/config.sh first
# ==============================================================================


# --- backup_vault ---
# Compresses ONLY the encrypted data folder (not the mount point).
# The result is a portable .tar.gz that can be restored on any machine.
#
# Why only the 'data' folder?
#   The toggle script, icons, and shortcut are regenerated on restore.
#   Only the encrypted data + gocryptfs.conf are needed for portability.
#
# tar flags:
#   -c  = create archive
#   -z  = compress with gzip
#   -f  = output filename
#   -C  = change to this directory before archiving
#         So we do: cd to container, then grab 'data' folder
#         This means the archive contains 'data/...' not '/full/path/data/...'
backup_vault() {
    local name="$1"
    [[ -z "$name" ]] && return 1

    local enc container
    enc=$(config_get_enc "$name")
    container=$(config_get_container "$name")

    [[ -z "$enc" ]] && { ui_error "Vault '$name' not found."; return 1; }

    ui_header "Backup: $name"

    # Pick destination
    local dest
    dest=$(ui_pick_dir "Select backup destination")
    [[ -z "$dest" ]] && return 1

    # Build filename with vault name + date
    # tr ' ' '_' replaces spaces so the filename is shell-friendly
    local safe_name
    safe_name=$(echo "$name" | tr ' ' '_')
    local filename="${safe_name}_EncryptedData_$(date +%F_%H-%M).tar.gz"

    # Run backup with spinner
    ui_spinner_start "Compressing '$name' encrypted data..."
    tar -czf "$dest/$filename" -C "$container" data 2>/dev/null
    local status=$?
    ui_spinner_stop

    if [[ $status -eq 0 ]]; then
        ui_info "Backup created successfully!"
        ui_info "Location: $dest/$filename"
        ui_info "This backup contains only encrypted data — safe to store anywhere."
    else
        ui_error "Backup failed! Check if destination has enough space."
    fi
}
