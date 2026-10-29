#!/bin/bash
# ==============================================================================
# lib/guard.sh — Auto-Lock Background Service (systemd + XDG Autostart)
# ==============================================================================
#
# Creates a systemd user service that monitors D-Bus signals for:
#   - Screen lock (all common DE screensaver interfaces)
#   - System sleep (login1 PrepareForSleep)
# When either fires, ALL open vaults are automatically locked.
#
# Also provides icon-sync on startup so that after reboot/poweroff
# (which unmounts FUSE but doesn't update icons), the shortcut icons
# correctly show the locked state.
#
# Auto-start strategy (dual approach for maximum compatibility):
#   1. XDG Autostart (.desktop in ~/.config/autostart/)
#      → Primary mechanism. Works on ALL desktop environments.
#      → Runs AFTER the graphical session is fully ready, so DISPLAY
#        and D-Bus session bus are guaranteed to be available.
#   2. systemd user service (WantedBy=default.target)
#      → Backup mechanism. Provides ExecStop (lock on shutdown),
#        Restart=always (crash recovery), and process management.
#      → Some DEs (XFCE, i3, MATE) never activate graphical-session.target,
#        so we use default.target instead.
#
# REQUIRES: CONFIG, ICON_DIR variables set
# ==============================================================================


# --- guard_sync_icons ---
# Syncs all shortcut icons to match actual vault mount state.
# Called on startup to fix stale icons (e.g., after reboot where FUSE
# mounts are gone but icons still show "open/decrypted").
guard_sync_icons() {
    [[ ! -s "$CONFIG" ]] && return 0

    while IFS="|" read -r name enc dec; do
        [[ -z "$name" ]] && continue

        local container
        container=$(dirname "$enc")
        container=$(realpath "$container" 2>/dev/null)
        [[ -z "$container" ]] && continue

        # Determine correct icon based on actual mount state
        local icon_file="encrypted.png"
        if mountpoint -q "$dec" 2>/dev/null; then
            icon_file="decrypted.png"
        fi

        local shortcuts=(
            "$HOME/Desktop/${name}.desktop"
            "$HOME/.local/share/applications/${name}.desktop"
        )
        for shortcut in "${shortcuts[@]}"; do
            if [[ -f "$shortcut" ]]; then
                local new_icon="$container/icons/$icon_file"
                if [[ -f "$new_icon" ]]; then
                    sed -i "s|Icon=.*|Icon=$new_icon|" "$shortcut"
                    touch "$shortcut"
                fi
            fi
        done
    done < "$CONFIG"
}


# --- guard_setup ---
# Generates the guard script + systemd service, then starts it.
guard_setup() {
    local guard_dir="$HOME/.local/bin"
    local guard_script="$guard_dir/vault-guard.sh"
    local service_dir="$HOME/.config/systemd/user"
    local service_file="$service_dir/vault-guard.service"

    # Always sync icons on startup — after reboot, FUSE mounts are gone
    # but the shortcut icons may still show "decrypted" (open) state.
    guard_sync_icons

    # Skip service setup if already running
    if systemctl --user is-active --quiet vault-guard.service 2>/dev/null; then
        ui_info "Security Guard: Already active."
        return 0
    fi

    mkdir -p "$guard_dir" "$service_dir"

    # Generate the guard script
    # This script does the actual locking when a D-Bus signal arrives.
    #
    # dbus-monitor:
    #   Listens for D-Bus messages (Linux's inter-process communication).
    #   --session = user session bus (screen lock signals)
    #   --system  = system bus (sleep/suspend signals)
    #   We run both in a subshell and pipe their combined output.
    #
    # "boolean true":
    #   Both ScreenSaver.ActiveChanged and PrepareForSleep send
    #   "boolean true" when activating. We grep for this to trigger lock.
    cat << 'GUARD_SCRIPT_START' > "$guard_script"
#!/bin/bash
CONFIG="$HOME/.secure_manager_config"

# Detect fusermount command (fuse3 provides fusermount3, fuse2 provides fusermount)
if command -v fusermount3 >/dev/null 2>&1; then
    FUSERMOUNT="fusermount3"
elif command -v fusermount >/dev/null 2>&1; then
    FUSERMOUNT="fusermount"
else
    echo "ERROR: Neither fusermount nor fusermount3 found."
    exit 1
fi

sync_icons_to_state() {
    # Sync shortcut icons to match actual mount state.
    # After reboot/poweroff, FUSE mounts are gone but icons may still
    # show "decrypted" (open). This corrects them.
    [ ! -f "$CONFIG" ] && return

    while IFS="|" read -r NAME ENC DEC; do
        [ -z "$DEC" ] && continue

        local V_CONTAINER
        V_CONTAINER=$(realpath "$(dirname "$ENC")")

        # Determine correct icon based on actual mount state
        local ICON_FILE="encrypted.png"
        if mountpoint -q "$DEC" 2>/dev/null; then
            ICON_FILE="decrypted.png"
        fi

        SHORTCUTS=(
            "$HOME/Desktop/${NAME}.desktop"
            "$HOME/.local/share/applications/${NAME}.desktop"
        )
        for SHORTCUT in "${SHORTCUTS[@]}"; do
            if [ -f "$SHORTCUT" ]; then
                local NEW_ICON="$V_CONTAINER/icons/$ICON_FILE"
                if [ -f "$NEW_ICON" ]; then
                    sed -i "s|Icon=.*|Icon=$NEW_ICON|" "$SHORTCUT"
                    touch "$SHORTCUT"
                fi
            fi
        done
    done < "$CONFIG"
}

lock_all_vaults() {
    local mode="$1"
    [ ! -f "$CONFIG" ] && return
    local IGNORE_FILE="$HOME/.secure_manager_ignore_lock"

    while IFS="|" read -r NAME ENC DEC; do
        [ -z "$DEC" ] && continue

        if [ "$mode" = "normal" ] && [ -f "$IGNORE_FILE" ]; then
            if grep -Fxq "$NAME" "$IGNORE_FILE" 2>/dev/null; then
                continue
            fi
        fi

        local IS_OPEN=false
        local V_CONTAINER
        V_CONTAINER=$(realpath "$(dirname "$ENC")")

        if mountpoint -q "$DEC"; then
            IS_OPEN=true

            # Kill processes using the mount point
            ps -eo pid=,cmd= | while read -r pid cmd; do
                [ -z "$pid" ] && continue
                if [[ "$cmd" == *"$DEC"* && "$cmd" != *gocryptfs* && "$cmd" != *vault-guard.sh* && "$pid" != "$$" ]]; then
                    kill -9 "$pid"
                fi
            done

            sleep 0.5
            $FUSERMOUNT -uz "$DEC"
            sleep 0.3

            # Reset mount point directory
            if [ -d "$DEC" ]; then
                rmdir "$DEC" 2>/dev/null && mkdir "$DEC"
            fi

            # Set read-only — prevents raw writes that bypass gocryptfs
            chmod a-w "$DEC"
        fi

        # Update shortcut icons to locked state
        if [ "$IS_OPEN" = true ] || [ "$mode" = "force" ]; then
            SHORTCUTS=(
                "$HOME/Desktop/${NAME}.desktop"
                "$HOME/.local/share/applications/${NAME}.desktop"
            )
            for SHORTCUT in "${SHORTCUTS[@]}"; do
                if [ -f "$SHORTCUT" ]; then
                    NEW_ICON="$V_CONTAINER/icons/encrypted.png"
                    if [ -f "$NEW_ICON" ]; then
                        sed -i "s|Icon=.*|Icon=$NEW_ICON|" "$SHORTCUT"
                        touch "$SHORTCUT"
                    fi
                fi
            done
            [ "$IS_OPEN" = true ] && notify-send "Security Guard" "🔐 Vault '$NAME' auto-locked." -i security-high 2>/dev/null
        fi
    done < "$CONFIG"
}

# Direct invocation modes (for ExecStop / ExecStartPost)
if [ "$1" = "--lock-all" ]; then
    lock_all_vaults "force"
    exit 0
fi
if [ "$1" = "--sync-icons" ]; then
    sync_icons_to_state
    exit 0
fi

# Sync icons on guard startup (fixes stale icons after reboot)
sync_icons_to_state

# Listen for screen lock / sleep signals via D-Bus.
# Monitor ALL common screensaver interfaces simultaneously so we catch
# the signal regardless of which DE is running. Also monitor the system
# bus for sleep/suspend. Using multiple match rules in a single
# dbus-monitor call is more reliable than detecting the DE (which often
# fails in systemd service environments where XDG_CURRENT_DESKTOP is
# unset and process detection is unreliable).
(
    dbus-monitor --session \
        "type='signal',interface='org.gnome.ScreenSaver',member='ActiveChanged'" \
        "type='signal',interface='org.freedesktop.ScreenSaver',member='ActiveChanged'" \
        "type='signal',interface='org.xfce.ScreenSaver',member='ActiveChanged'" \
        "type='signal',interface='org.cinnamon.ScreenSaver',member='ActiveChanged'" \
        "type='signal',interface='org.mate.ScreenSaver',member='ActiveChanged'" &
    dbus-monitor --system \
        "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"
) | while read -r line; do
    if echo "$line" | grep -q "boolean true"; then
        lock_all_vaults "normal"
    fi
done
GUARD_SCRIPT_START

    chmod +x "$guard_script"

    # Generate systemd service file
    #
    # Critical: Import DBUS_SESSION_BUS_ADDRESS and DISPLAY from the user
    # session into the service environment. Without these, dbus-monitor
    # --session cannot connect and screen lock signals are never received.
    #
    # ExecStartPost syncs icons on service startup — this fixes stale
    # icons after reboot (FUSE mounts don't survive reboot, but icons
    # were never updated to reflect the closed state).
    #
    # WantedBy=default.target (not graphical-session.target):
    #   Many DEs (XFCE, i3, MATE, Cinnamon) never activate
    #   graphical-session.target, causing the service to never auto-start.
    #   default.target is always reached when the user session starts.
    cat << EOF > "$service_file"
[Unit]
Description=Secure Vault Auto-Lock Guard

[Service]
ExecStartPre=/bin/bash -c 'systemctl --user import-environment DISPLAY DBUS_SESSION_BUS_ADDRESS XDG_CURRENT_DESKTOP 2>/dev/null || true'
ExecStart=$guard_script
ExecStartPost=$guard_script --sync-icons
ExecStop=$guard_script --lock-all
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

    # --- XDG Autostart (primary auto-start mechanism) ---
    # .desktop files in ~/.config/autostart/ are launched by ALL desktop
    # environments after the graphical session is fully ready (DISPLAY,
    # D-Bus session bus are guaranteed to be available).
    # This is more reliable than systemd targets like graphical-session.target
    # which many DEs (XFCE, i3, MATE, etc.) never activate.
    #
    # Flow: XDG autostart → import env vars → restart systemd service
    # This ensures the systemd service always has fresh session env vars.
    local autostart_dir="$HOME/.config/autostart"
    local autostart_file="$autostart_dir/vault-guard.desktop"
    mkdir -p "$autostart_dir"

    cat << EOF > "$autostart_file"
[Desktop Entry]
Type=Application
Name=Vault Guard
Comment=Auto-lock guard for encrypted vaults
Exec=/bin/bash -c 'systemctl --user import-environment DISPLAY DBUS_SESSION_BUS_ADDRESS XDG_CURRENT_DESKTOP 2>/dev/null; systemctl --user restart vault-guard.service 2>/dev/null'
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-MATE-Autostart-enabled=true
EOF

    # Reload and start
    systemctl --user daemon-reload
    systemctl --user enable vault-guard.service
    systemctl --user restart vault-guard.service
    ui_info "Security Guard: Started and enabled (with auto-start on login)."
}


# --- guard_status ---
# Shows whether the auto-lock service is running.
guard_status() {
    if systemctl --user is-active --quiet vault-guard.service 2>/dev/null; then
        ui_info "Security Guard: ● Active (protecting your vaults)"
    else
        ui_warn "Security Guard: ○ Inactive"
    fi
}


# --- guard_lock_all ---
# Manually triggers locking of all open vaults.
guard_lock_all() {
    local guard_script="$HOME/.local/bin/vault-guard.sh"
    if [[ -x "$guard_script" ]]; then
        ui_spinner_start "Locking all vaults..."
        bash "$guard_script" --lock-all
        ui_spinner_stop
        ui_info "All vaults locked."
    else
        ui_error "Guard script not found. Run setup first."
    fi
}
