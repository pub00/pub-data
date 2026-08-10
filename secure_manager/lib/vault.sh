#!/bin/bash
# ==============================================================================
# lib/vault.sh — Core Vault Operations
# ==============================================================================
#
# This file contains all gocryptfs vault operations:
#   - Create (new or restore from backup)
#   - Toggle (lock/unlock)
#   - Delete (nuclear or export-then-delete)
#   - Open folder, Recover password
#
# REQUIRES: source lib/ui.sh, lib/config.sh first
#           CONFIG, DIR, ICON_DIR must be set
# ==============================================================================


# --- vault_status ---
# Returns "open" or "closed" based on whether the mount point is active.
#
# mountpoint -q:
#   Silently checks if a path is a mount point (where gocryptfs attaches).
#   Returns 0 if mounted (open), 1 if not (closed).
vault_status() {
    local dec="$1"
    if mountpoint -q "$dec" 2>/dev/null; then
        echo "open"
    else
        echo "closed"
    fi
}


# --- _generate_toggle_script ---
# Creates the per-vault toggle script that lives inside the container.
# This script is what the desktop shortcut actually runs.
#
# "Here document" (cat << EOF):
#   Everything between << EOF and EOF is written to the file.
#   Variables with $ are expanded NOW (uses current values).
#   Variables with \$ are escaped — they stay as $VAR in the output
#   and get expanded LATER when the toggle script actually runs.
#
# Why a separate script per vault?
#   Each vault has unique paths. The desktop shortcut just calls this
#   script, so clicking the icon = one-click lock/unlock.
_generate_toggle_script() {
    local name="$1"
    local enc="$2"
    local dec="$3"
    local vault_icons="$4"
    local toggle_path="$5"
    local shortcut_path="$6"

    cat << EOF > "$toggle_path"
#!/bin/bash
ICON_PATH="$vault_icons"
SHORTCUT_LOCATION="$shortcut_path"

# Update the shortcut icon to reflect current state
set_icon() {
    if [ -f "\$SHORTCUT_LOCATION" ]; then
        sed -i "s|Icon=.*|Icon=\$ICON_PATH/\$1|" "\$SHORTCUT_LOCATION"
        touch "\$SHORTCUT_LOCATION"
    fi
}

# --- LOCK (vault is currently open) ---
if mountpoint -q "$dec"; then
    # Try clean unmount first
    if $FUSERMOUNT -u "$dec" 2>/dev/null; then
        chmod a-w "$dec"
        set_icon "encrypted.png"
        notify-send "Security Guard" "🔐 $name is now Locked." 2>/dev/null
    else
        # Vault is busy — ask user if they want to force close
        read -p "Vault is busy. Force close? [y/N]: " answer
        if [[ "\${answer,,}" == "y"* ]]; then
            fuser -km "$dec" 2>/dev/null
            sleep 0.5
            $FUSERMOUNT -uz "$dec"
            chmod a-w "$dec"
            set_icon "encrypted.png"
            notify-send "Security Guard" "🔐 $name Force Closed." 2>/dev/null
        fi
    fi
# --- UNLOCK (vault is currently closed) ---
else
    # Restore write permission so gocryptfs can mount here
    chmod u+rwx "$dec" 2>/dev/null
    while true; do
        # Pure terminal password input — no Zenity needed.
        # The .desktop shortcut has Terminal=true, so clicking the
        # icon opens the system's default terminal automatically.
        read -r -s -p "Password for $name: " PASS
        echo
        [ -z "\$PASS" ] && { chmod a-w "$dec" 2>/dev/null; exit 0; }

        if echo "\$PASS" | gocryptfs -q "$enc" "$dec" 2>/dev/null; then
            if mountpoint -q "$dec"; then
                set_icon "decrypted.png"
                notify-send "Security Guard" "🔓 $name is now Open." 2>/dev/null
                setsid xdg-open "$dec" >/dev/null 2>&1 &
                sleep 0.5
                break
            fi
        else
            echo "Incorrect password."
            read -p "Try again? [Y/n]: " retry
            [[ "\${retry,,}" == "n"* ]] && { chmod a-w "$dec" 2>/dev/null; exit 0; }
        fi
    done
fi
EOF
    chmod +x "$toggle_path"
}


# --- _generate_shortcut ---
# Creates a .desktop file on the user's desktop.
#
# .desktop files are the Linux standard for application shortcuts.
# Format is defined by freedesktop.org — works on GNOME, KDE, XFCE, etc.
#
# gio set ... metadata::trusted true:
#   On GNOME, new .desktop files are "untrusted" by default (security).
#   This marks it as trusted so it runs without the "untrusted" warning.
_generate_shortcut() {
    local name="$1"
    local toggle_path="$2"
    local icon_path="$3"
    local shortcut_path="$4"

    cat << EOF > "$shortcut_path"
[Desktop Entry]
Name=$name
Exec="$toggle_path"
Type=Application
Icon=$icon_path
Terminal=true
EOF
    chmod +x "$shortcut_path"

    # Mark as trusted on GNOME-based desktops
    if [ -d "$HOME/Desktop" ]; then
        gio set "$shortcut_path" metadata::trusted true 2>/dev/null
    fi
}


# ==============================================================================
# vault_create — Create a new vault or restore from backup
# ==============================================================================
#
# Flow:
#   1. Choose mode (new / restore)
#   2. Pick parent directory
#   3. Enter vault name
#   4. Create container structure
#   5. Initialize gocryptfs (or extract backup)
#   6. Copy icons, generate toggle script + shortcut
#   7. Register in config
vault_create() {

    ui_header "Create New Vault"

    # Step 1: Choose mode
    local mode
    mode=$(ui_menu "Vault Mode" "New Vault (Fresh Start)" "Restore from Backup (.tar.gz)")
    [[ -z "$mode" ]] && return 1

    # If restoring, select the backup file early
    local archive=""
    if [[ "$mode" == "Restore from Backup (.tar.gz)" ]]; then
        archive=$(ui_pick_file "Select backup archive" "*.tar.gz")
        [[ -z "$archive" ]] && return 1
    fi

    # Step 2: Pick parent directory
    local parent_dir
    parent_dir=$(ui_pick_dir "Select location for the vault")
    [[ -z "$parent_dir" ]] && return 1

    # Step 3: Enter vault name
    local name
    name=$(ui_input "Enter vault name")
    [[ -z "$name" ]] && return 1
    name=$(echo "$name" | xargs)       # Trim whitespace
    [[ -z "$name" ]] && return 1

    # Create a filesystem-safe version of the name
    # tr -cd keeps only alphanumeric chars, underscores, and hyphens
    local safe_name
    safe_name=$(echo "$name" | tr -cd '[:alnum:]_-')

    # Check for duplicates
    if config_exists "$name"; then
        ui_error "Vault name '$name' already exists."
        return 1
    fi

    # Step 4: Define the container structure
    # The container is a hidden folder (dot-prefix) that holds everything:
    #   .VaultName/
    #   ├── data/           ← encrypted files (gocryptfs)
    #   ├── VaultName/      ← mount point (decrypted view)
    #   ├── icons/          ← lock/unlock icons for shortcut
    #   └── toggle_*.sh     ← lock/unlock script
    local container="$parent_dir/.$safe_name"

    if [[ -d "$container" ]]; then
        ui_error "A vault folder already exists at this location."
        return 1
    fi

    local enc="$container/data"
    local dec="$container/$name"
    local vault_icons="$container/icons"
    local toggle_script="$container/toggle_${safe_name}.sh"
    local shortcut_path="$HOME/Desktop/${name}.desktop"

    # Create the directory structure
    # mkdir -p creates parent directories as needed, no error if they exist
    mkdir -p "$enc" "$dec" "$vault_icons"

    # Step 5: Initialize or restore
    if [[ "$mode" == "New Vault (Fresh Start)" ]]; then
        # gocryptfs -init creates encrypted filesystem in the target directory.
        # It asks for a password and shows a master key for recovery.
        while true; do
            echo ""
            ui_warn "Initializing encryption engine..."
            ui_info "You will be asked to set a password. REMEMBER IT!"
            echo ""

            gocryptfs -init "$enc"
            local status=$?

            if [[ $status -eq 0 ]]; then
                echo ""
                echo "==============================================================="
                ui_warn "           CRITICAL SECURITY INFORMATION"
                echo "==============================================================="
                ui_warn "Your Master Key was shown above."
                ui_warn "1. WRITE IT DOWN NOW."
                ui_warn "2. Without it, your data is LOST forever."
                echo "==============================================================="

                # Force explicit confirmation
                while true; do
                    local confirm
                    confirm=$(ui_input "Type 'SAVED' to continue")
                    if [[ "${confirm^^}" == "SAVED" ]]; then
                        clear
                        ui_info "Vault initialized successfully."
                        break
                    fi
                    ui_error "You must type 'SAVED' to continue!"
                done
                break
            else
                ui_error "Initialization failed (password mismatch?)."
                if ! ui_confirm "Try again?"; then
                    # Cleanup on abort
                    rm -rf "$container"
                    return 1
                fi
            fi
        done
    else
        # Restore mode: extract backup into container
        ui_spinner_start "Extracting backup..."
        tar -xzf "$archive" -C "$container" 2>/dev/null
        ui_spinner_stop

        # Verify the backup contains valid gocryptfs data
        if [[ ! -f "$enc/gocryptfs.conf" ]]; then
            ui_error "Invalid backup — 'gocryptfs.conf' missing in data folder."
            rm -rf "$container"
            return 1
        fi
        ui_info "Backup extracted successfully."
    fi

    # Step 6: Copy icons from the main project to this vault's container
    # Each vault gets its own copy so it's truly self-contained/portable
    if [[ -d "$ICON_DIR" ]]; then
        cp "$ICON_DIR/encrypted.png" "$ICON_DIR/decrypted.png" "$vault_icons/" 2>/dev/null
    fi

    # Step 7: Generate toggle script and desktop shortcut
    _generate_toggle_script "$name" "$enc" "$dec" "$vault_icons" "$toggle_script" "$shortcut_path"
    _generate_shortcut "$name" "$toggle_script" "$vault_icons/encrypted.png" "$shortcut_path"

    # Step 8: Register in config
    config_add "$name" "$enc" "$dec"

    # Start read-only since vault begins closed.
    # Prevents accidental writes to the raw mount point directory
    # which would bypass gocryptfs and cause sync issues.
    chmod a-w "$dec"

    ui_info "Vault '$name' created successfully!"
    ui_info "Container: $container"
    ui_info "Desktop shortcut created."
}


# ==============================================================================
# vault_toggle — Lock or unlock a vault from the terminal
# ==============================================================================
#
# If open → unmount (lock)
# If closed → ask password → mount (unlock) → open in file manager
vault_toggle() {
    local name="$1"
    [[ -z "$name" ]] && return 1

    local enc dec container
    enc=$(config_get_enc "$name")
    dec=$(config_get_dec "$name")
    container=$(config_get_container "$name")

    [[ -z "$enc" ]] && { ui_error "Vault '$name' not found in config."; return 1; }

    local vault_icons="$container/icons"
    local shortcut_path="$HOME/Desktop/${name}.desktop"

    # Helper to update shortcut icon
    _set_shortcut_icon() {
        local icon_file="$1"
        if [[ -f "$shortcut_path" ]]; then
            sed -i "s|Icon=.*|Icon=${vault_icons}/${icon_file}|" "$shortcut_path"
            touch "$shortcut_path"
        fi
    }

    if [[ "$(vault_status "$dec")" == "open" ]]; then
        # --- LOCK ---
        ui_info "Locking '$name'..."
        if $FUSERMOUNT -u "$dec" 2>/dev/null; then
            # Remove write permission — prevents raw writes that bypass gocryptfs
            chmod a-w "$dec"
            _set_shortcut_icon "encrypted.png"
            notify-send "Security Guard" "🔐 $name is now Locked." 2>/dev/null
            ui_info "'$name' is now LOCKED."
        else
            ui_warn "Vault is busy (files may be open)."
            if ui_confirm "Force close?"; then
                fuser -km "$dec" 2>/dev/null
                sleep 0.5
                $FUSERMOUNT -uz "$dec"
                chmod a-w "$dec"
                _set_shortcut_icon "encrypted.png"
                notify-send "Security Guard" "🔐 $name Force Closed." 2>/dev/null
                ui_info "'$name' force locked."
            fi
        fi
    else
        # --- UNLOCK ---
        # Restore write permission on mount point (was read-only when locked)
        chmod u+rwx "$dec" 2>/dev/null
        while true; do
            local pass
            pass=$(ui_password "Unlock '$name'")
            if [[ -z "$pass" ]]; then
                chmod a-w "$dec" 2>/dev/null
                return 1
            fi

            if echo "$pass" | gocryptfs -q "$enc" "$dec" 2>/dev/null; then
                if mountpoint -q "$dec"; then
                    _set_shortcut_icon "decrypted.png"
                    notify-send "Security Guard" "🔓 $name is now Open." 2>/dev/null
                    ui_info "'$name' is now OPEN."
                    setsid xdg-open "$dec" >/dev/null 2>&1 &
                    return 0
                fi
            else
                ui_error "Incorrect password."
                if ! ui_confirm "Try again?"; then
                    chmod a-w "$dec" 2>/dev/null
                    return 1
                fi
            fi
        done
    fi
}


# ==============================================================================
# vault_delete — Permanently remove a vault
# ==============================================================================
#
# Two options:
#   1. Nuclear Delete — destroy everything (encrypted data, shortcut, config)
#   2. Export & Delete — save decrypted files first, then delete vault
vault_delete() {
    local name="$1"
    [[ -z "$name" ]] && return 1

    local enc dec container shortcut
    enc=$(config_get_enc "$name")
    dec=$(config_get_dec "$name")
    container=$(config_get_container "$name")
    shortcut="$HOME/Desktop/${name}.desktop"

    # Option 1: Nuclear delete
    if ui_confirm "NUCLEAR DELETE: Permanently destroy ALL data in '$name'?" "N"; then

        # Unmount if open
        if mountpoint -q "$dec" 2>/dev/null; then
            $FUSERMOUNT -u "$dec" 2>/dev/null || {
                fuser -km "$dec" 2>/dev/null
                $FUSERMOUNT -uz "$dec"
            }
        fi

        # Restore write so rm -rf can clean up directory contents
        chmod u+rwx "$dec" 2>/dev/null
        rm -rf "$container"
        rm -f "$shortcut"
        config_remove "$name"
        ui_info "Vault '$name' and all data destroyed."
        return 0
    fi

    # Option 2: Export then delete
    if ui_confirm "Export decrypted files first, then delete vault?"; then
        local dest
        dest=$(ui_pick_dir "Select export destination")
        [[ -z "$dest" ]] && return 1

        # Must unlock to export
        if ! mountpoint -q "$dec" 2>/dev/null; then
            ui_info "Unlocking vault for export..."
            # Restore write permission for gocryptfs mount
            chmod u+rwx "$dec" 2>/dev/null
            local pass
            pass=$(ui_password "Unlock '$name'")
            [[ -z "$pass" ]] && return 1
            echo "$pass" | gocryptfs -q "$enc" "$dec" 2>/dev/null
        fi

        if mountpoint -q "$dec" 2>/dev/null; then
            local export_file="${name}_EXPORT_$(date +%F).tar.gz"

            ui_spinner_start "Exporting decrypted data..."
            tar -czf "$dest/$export_file" -C "$dec" . 2>/dev/null
            local tar_status=$?
            ui_spinner_stop

            if [[ $tar_status -eq 0 ]]; then
                $FUSERMOUNT -u "$dec" 2>/dev/null
                rm -rf "$container"
                rm -f "$shortcut"
                config_remove "$name"
                ui_info "Export saved to: $dest/$export_file"
                ui_info "Vault removed."
            else
                ui_error "Export failed. Vault NOT deleted (your data is safe)."
            fi
        else
            ui_error "Failed to unlock vault. Cancelled."
        fi
    else
        ui_info "Deletion cancelled."
    fi
}


# ==============================================================================
# vault_open_folder — Open decrypted folder in file manager
# ==============================================================================
vault_open_folder() {
    local name="$1"
    local dec
    dec=$(config_get_dec "$name")

    if mountpoint -q "$dec" 2>/dev/null; then
        setsid xdg-open "$dec" >/dev/null 2>&1 &
        ui_info "Opening '$name' in file manager."
    else
        ui_error "Vault '$name' is closed. Unlock it first."
    fi
}


# ==============================================================================
# vault_recover — Reset password using master key
# ==============================================================================
#
# gocryptfs -passwd -masterkey:
#   Allows setting a new password if you have the master key.
#   This is the ONLY way to recover access if you forget your password.
vault_recover() {
    local name="$1"
    local enc
    enc=$(config_get_enc "$name")

    ui_header "Password Recovery: $name"
    ui_warn "You need your MASTER KEY to reset the password."

    local key
    key=$(ui_input "Paste your Master Key")
    [[ -z "$key" ]] && return 1

    ui_info "A terminal prompt will appear. Set your NEW password."
    echo ""

    # Run gocryptfs password change with the master key
    gocryptfs -passwd -masterkey "$key" "$enc"

    if [[ $? -eq 0 ]]; then
        ui_info "Password reset successfully!"
    else
        ui_error "Recovery failed. Check your master key."
    fi
}


# ==============================================================================
# vault_manage_exclusions — Toggle screen lock exclusion for vaults
# ==============================================================================
# Allow user to choose which vaults stay open during screen lock.
# They will still lock on system shutdown/restart or manual "Lock All".
vault_manage_exclusions() {
    local ignore_file="$HOME/.secure_manager_ignore_lock"
    touch "$ignore_file" 2>/dev/null

    while true; do
        clear
        ui_header "Screen Lock Exclusions"
        ui_info "Vaults selected here will NOT be locked when the screen locks."
        ui_info "They WILL still be locked on system shutdown or manual 'Lock All'."
        echo >&2

        local count=0
        local vaults=()
        
        while IFS="|" read -r n _ _; do
            [[ -z "$n" ]] && continue
            vaults+=("$n")
            ((count++))
        done < "$CONFIG"

        if (( count == 0 )); then
            ui_warn "No vaults exist."
            echo >&2
            read -p "  Press Enter to return..."
            return
        fi

        for (( i=0; i<count; i++ )); do
            local v="${vaults[$i]}"
            if grep -Fxq "$v" "$ignore_file" 2>/dev/null; then
                echo -e "  ${C_CYAN}$((i+1)))${C_RESET} [${C_GREEN}X${C_RESET}] $v" >&2
            else
                echo -e "  ${C_CYAN}$((i+1)))${C_RESET} [ ] $v" >&2
            fi
        done
        echo -e "  ${C_CYAN}0)${C_RESET} Done / Return" >&2
        echo >&2

        echo -en "  ${C_YELLOW}▸${C_RESET} Toggle vault [0-${count}]: " >&2
        local choice
        read -r choice

        if [[ "$choice" == "0" ]]; then
            return
        elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            local selected="${vaults[$((choice-1))]}"
            if grep -Fxq "$selected" "$ignore_file" 2>/dev/null; then
                # Remove it
                grep -Fxv "$selected" "$ignore_file" > "${ignore_file}.tmp"
                mv "${ignore_file}.tmp" "$ignore_file"
            else
                # Add it
                echo "$selected" >> "$ignore_file"
            fi
        else
            ui_error "Invalid choice."
            sleep 1
        fi
    done
}
