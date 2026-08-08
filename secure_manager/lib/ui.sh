#!/bin/bash
# ==============================================================================
# lib/ui.sh — Terminal UI Functions (Replaces Zenity)
# ==============================================================================
#
# WHY >&2 EVERYWHERE?
#   When you capture output: RESULT=$(ui_input "Name?")
#   Bash captures EVERYTHING printed to stdout into $RESULT.
#   But we want the user to SEE the prompt on screen!
#   So: prompts go to stderr (>&2) = visible on screen
#       final answer goes to stdout = captured into variable
# ==============================================================================


# --- COLORS ---
# ANSI escape codes: \033[ starts a color, 0m resets it.
# 'readonly' prevents accidental overwriting later.
readonly C_RESET='\033[0m'
readonly C_BOLD='\033[1m'
readonly C_DIM='\033[2m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_BLUE='\033[0;34m'
readonly C_CYAN='\033[0;36m'
readonly C_BG_BLUE='\033[44m'
readonly C_WHITE='\033[1;37m'


# --- SIMPLE MESSAGES ---
# Replaces: zenity --info / --error / --warning

ui_header() {
    echo -e "\n${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}" >&2
    echo -e "  ${C_BOLD}$1${C_RESET}" >&2
    echo -e "${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n" >&2
}

ui_info()  { echo -e "  ${C_GREEN}[✓]${C_RESET} $1" >&2; }
ui_error() { echo -e "  ${C_RED}[✗]${C_RESET} $1" >&2; }
ui_warn()  { echo -e "  ${C_YELLOW}[!]${C_RESET} $1" >&2; }

ui_divider() {
    echo -e "  ${C_DIM}$(printf '%.0s─' {1..50})${C_RESET}" >&2
}


# --- ui_confirm ---
# Replaces: zenity --question --text="message"
# Usage:  if ui_confirm "Delete vault?"; then echo "yes"; fi
#
# How:  Returns 0 (true) for yes, 1 (false) for no.
#       In bash, 0 = success/true (opposite of most languages!)
#       The ${2:-N} means: "if $2 is empty, default to N"
#       The ${answer,,} converts to lowercase for comparison.
ui_confirm() {
    local prompt="$1"
    local default="${2:-N}"

    local hint
    if [[ "${default^^}" == "Y" ]]; then
        hint="Y/n"
    else
        hint="y/N"
    fi

    echo -en "  ${C_YELLOW}[?]${C_RESET} ${prompt} [${hint}]: " >&2

    local answer
    read -r answer          # -r = raw, don't eat backslashes

    [[ -z "$answer" ]] && answer="$default"
    [[ "${answer,,}" == "y"* ]]   # This IS the return value (true/false)
}


# --- ui_input ---
# Replaces: zenity --entry --text="Enter name"
# Usage:  NAME=$(ui_input "Enter vault name")
#
# Flags:  -r = raw (don't eat backslashes)
#         -e = readline (gives TAB completion + arrow keys)
ui_input() {
    local prompt="$1"
    local default="$2"

    local display="  ${C_CYAN}▸${C_RESET} ${prompt}"
    [[ -n "$default" ]] && display+=" ${C_DIM}[${default}]${C_RESET}"
    display+=": "

    echo -en "$display" >&2
    local value
    read -r -e value

    [[ -z "$value" && -n "$default" ]] && value="$default"
    [[ -z "$value" ]] && return 1

    echo "$value"   # Goes to stdout = captured by $(...)
}


# --- ui_password ---
# Replaces: zenity --password
# Usage:  PASS=$(ui_password "Unlock vault")
#
# Flag:  -s = silent, hides what user types (essential for passwords)
# The extra 'echo >&2' adds a newline because -s suppresses it.
ui_password() {
    local prompt="$1"

    echo -en "  ${C_CYAN}🔑${C_RESET} ${prompt}: " >&2
    local password
    read -r -s password
    echo >&2               # Newline after hidden input

    [[ -z "$password" ]] && return 1
    echo "$password"
}


# --- ui_menu ---
# Replaces: zenity --list --column="Action" "opt1" "opt2"
# Usage:  CHOICE=$(ui_menu "Pick Action" "Create" "Delete" "Quit")
#
# 'shift' removes $1, so $@ becomes just the options.
# ${#options[@]} = array length.   ${options[$i]} = element at index i.
# Echoes the TEXT of the chosen option (not the number).
ui_menu() {
    local title="$1"
    shift
    local options=("$@")
    local count=${#options[@]}

    echo -e "\n  ${C_BOLD}${title}${C_RESET}" >&2
    ui_divider

    local i
    for (( i=0; i<count; i++ )); do
        echo -e "  ${C_CYAN}$((i+1)))${C_RESET} ${options[$i]}" >&2
    done
    echo >&2

    while true; do
        echo -en "  ${C_YELLOW}▸${C_RESET} Choose [1-${count}]: " >&2
        local choice
        read -r choice

        # =~ is regex match. ^[0-9]+$ = "only digits"
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            echo "${options[$((choice-1))]}"
            return 0
        fi
        ui_error "Invalid choice."
    done
}


# --- ui_pick_dir ---
# Replaces: zenity --file-selection --directory
# Usage:  DEST=$(ui_pick_dir "Select backup destination")
#
# The -e flag on read enables TAB completion for paths!
# realpath converts "~/stuff" to "/home/user/stuff"
# ${dir/#\~/$HOME} manually expands ~ (read -e doesn't always do it)
ui_pick_dir() {
    local prompt="$1"

    echo -e "  ${C_DIM}(TAB completion enabled)${C_RESET}" >&2
    while true; do
        echo -en "  ${C_CYAN}📁${C_RESET} ${prompt}: " >&2
        local dir_path
        read -r -e dir_path

        [[ -z "$dir_path" ]] && return 1

        dir_path="${dir_path/#\~/$HOME}"
        dir_path=$(realpath -- "$dir_path" 2>/dev/null)

        if [[ -d "$dir_path" ]]; then
            echo "$dir_path"
            return 0
        fi
        ui_error "Not a valid directory: ${dir_path}"
    done
}


# --- ui_pick_file ---
# Replaces: zenity --file-selection --file-filter="*.tar.gz"
# Usage:  FILE=$(ui_pick_file "Select backup" "*.tar.gz")
ui_pick_file() {
    local prompt="$1"
    local hint="$2"

    echo -e "  ${C_DIM}(TAB completion enabled)${C_RESET}" >&2
    [[ -n "$hint" ]] && echo -e "  ${C_DIM}Expected: ${hint}${C_RESET}" >&2

    while true; do
        echo -en "  ${C_CYAN}📄${C_RESET} ${prompt}: " >&2
        local file_path
        read -r -e file_path

        [[ -z "$file_path" ]] && return 1

        file_path="${file_path/#\~/$HOME}"
        file_path=$(realpath -- "$file_path" 2>/dev/null)

        if [[ -f "$file_path" ]]; then
            echo "$file_path"
            return 0
        fi
        ui_error "Not a valid file: ${file_path}"
    done
}


# --- ui_table ---
# Replaces: build_table + zenity --list (the vault dashboard)
# Usage:  ui_table "$CONFIG_FILE"
#
# printf formatting: %-20s = left-aligned, 20 chars wide
# du -sh = summarize size in human-readable format
# mountpoint -q = silently check if path is mounted (0=yes, 1=no)
ui_table() {
    local config_file="$1"

    if [[ ! -s "$config_file" ]]; then
        echo -e "\n  ${C_DIM}No vaults yet. Create one to get started!${C_RESET}\n" >&2
        return 1
    fi

    echo >&2
    printf "  ${C_BG_BLUE}${C_WHITE} %-4s %-20s %-8s %-12s %-30s ${C_RESET}\n" \
        "#" "VAULT" "SIZE" "STATUS" "LOCATION" >&2

    local index=1
    while IFS="|" read -r name enc dec; do
        [[ -z "$name" ]] && continue

        local status
        if mountpoint -q "$dec" 2>/dev/null; then
            status="${C_GREEN}● OPEN${C_RESET}"
        else
            status="${C_RED}● CLOSED${C_RESET}"
        fi

        local size
        size=$(du -sh "$enc" 2>/dev/null | cut -f1)
        [[ -z "$size" ]] && size="—"

        local location
        location=$(dirname "$enc")

        printf "  %-4s %-20s %-8s " "$index" "$name" "$size" >&2
        echo -e "$(printf '%-12b' "$status") ${C_DIM}${location}${C_RESET}" >&2

        (( index++ ))
    done < "$config_file"

    echo >&2
}


# --- ui_vault_select ---
# Replaces: build_table | zenity --list --print-column=2
# Usage:  SELECTED=$(ui_vault_select "$CONFIG" "Select vault")
#
# Shows the table, then asks user to pick by number.
# Returns the NAME of the selected vault.
ui_vault_select() {
    local config_file="$1"
    local prompt="${2:-Select a vault}"

    ui_table "$config_file" || return 1

    # Count vaults
    local count=0
    while IFS="|" read -r name _ _; do
        [[ -n "$name" ]] && (( count++ ))
    done < "$config_file"

    (( count == 0 )) && return 1

    while true; do
        echo -en "  ${C_YELLOW}▸${C_RESET} ${prompt} [1-${count}]: " >&2
        local choice
        read -r choice

        [[ -z "$choice" ]] && return 1

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            local idx=1
            while IFS="|" read -r name _ _; do
                [[ -z "$name" ]] && continue
                if (( idx == choice )); then
                    echo "$name"
                    return 0
                fi
                (( idx++ ))
            done < "$config_file"
        fi
        ui_error "Invalid choice."
    done
}


# --- SPINNER (background progress indicator) ---
# Replaces: zenity --progress --pulsate
# Usage:
#   ui_spinner_start "Compressing..."
#   tar -czf backup.tar.gz data/
#   ui_spinner_stop
#
# $! = PID of last background process (the & sends it to background)
# \r = carriage return (overwrites same line = animation effect)
# trap = cleanup if script exits unexpectedly
_SPINNER_PID=""

ui_spinner_start() {
    local message="$1"
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    (
        local i=0
        while true; do
            printf "\r  ${C_CYAN}${chars:$((i % ${#chars})):1}${C_RESET} ${message}" >&2
            sleep 0.1
            (( i++ ))
        done
    ) &

    _SPINNER_PID=$!
    trap 'ui_spinner_stop 2>/dev/null' EXIT
}

ui_spinner_stop() {
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null
        wait "$_SPINNER_PID" 2>/dev/null
        _SPINNER_PID=""
        printf "\r  %-60s\r" " " >&2    # Clear spinner line
    fi
}
