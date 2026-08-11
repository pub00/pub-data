#!/bin/bash
# ==============================================================================
# lib/ui.sh — Terminal UI Functions (Pure Bash, No GUI Dependencies)
# ==============================================================================
#
# PURPOSE:
#   Provides reusable terminal interface functions — colored messages, menus,
#   text inputs, password prompts, directory pickers, and a spinner animation.
#   This is the SAME pattern used in Secure Manager 2.0, adapted for Git Helper.
#
# WHY >&2 EVERYWHERE?
#   When you capture output with: RESULT=$(ui_input "Name?")
#   Bash captures EVERYTHING printed to stdout into $RESULT.
#   But we want the user to SEE the prompt on screen!
#   So: prompts go to stderr (>&2) = visible on screen
#       final answer goes to stdout = captured into variable
#
# PORTABILITY:
#   Uses only ANSI escape codes (supported by every modern terminal)
#   and bash built-ins (read, printf, echo). No external dependencies.
# ==============================================================================


# --- COLORS ---
# ANSI escape codes: \033[ starts a color, 0m resets it.
# 'readonly' prevents accidental overwriting later in the script.
# These are defined as VARIABLES so we can use them inside strings
# with ${C_RED} syntax instead of typing the raw escape code every time.
readonly C_RESET='\033[0m'       # Turn off all formatting
readonly C_BOLD='\033[1m'        # Bold text
readonly C_DIM='\033[2m'         # Dim/faded text (for hints)
readonly C_RED='\033[0;31m'      # Errors, danger warnings
readonly C_GREEN='\033[0;32m'    # Success messages
readonly C_YELLOW='\033[1;33m'   # Warnings, prompts
readonly C_BLUE='\033[0;34m'     # Headers, decorative
readonly C_CYAN='\033[0;36m'     # Accents, menu numbers
readonly C_WHITE='\033[1;37m'    # Bright white for emphasis
readonly C_MAGENTA='\033[0;35m'  # Special highlights
readonly C_BG_BLUE='\033[44m'    # Blue background (for table headers)


# ==============================================================================
# SIMPLE MESSAGES
# ==============================================================================
# These replace zenity --info / --error / --warning with pure terminal output.
# Each function prints a colored prefix ([✓], [✗], etc.) followed by the message.

# --- ui_header ---
# Prints a styled section header with separator lines.
# Usage: ui_header "Clone Remote Repository"
#
# The ━ character is a box-drawing character (heavier than ─).
# We print to stderr (>&2) so it's always visible, even inside $(...).
ui_header() {
    echo -e "\n${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}" >&2
    echo -e "  ${C_BOLD}$1${C_RESET}" >&2
    echo -e "${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n" >&2
}

# --- ui_info / ui_error / ui_warn / ui_success ---
# Quick one-line status messages with colored icons.
# Usage: ui_info "Repository cloned successfully"
#        ui_error "Failed to connect to remote"
ui_info()    { echo -e "  ${C_GREEN}[✓]${C_RESET} $1" >&2; }
ui_error()   { echo -e "  ${C_RED}[✗]${C_RESET} $1" >&2; }
ui_warn()    { echo -e "  ${C_YELLOW}[!]${C_RESET} $1" >&2; }
ui_success() { echo -e "  ${C_GREEN}[★]${C_RESET} ${C_GREEN}$1${C_RESET}" >&2; }

# --- ui_divider ---
# Prints a thin horizontal line to separate sections.
# printf '%.0s─' {1..50} repeats the ─ character 50 times.
# %.0s means "print zero characters of the string" — a trick to repeat chars.
ui_divider() {
    echo -e "  ${C_DIM}$(printf '%.0s─' {1..50})${C_RESET}" >&2
}


# ==============================================================================
# INTERACTIVE INPUTS
# ==============================================================================

# --- ui_confirm ---
# Asks a yes/no question. Returns 0 (true) for yes, 1 (false) for no.
# Usage:  if ui_confirm "Delete everything?"; then echo "deleted"; fi
#         if ui_confirm "Continue?" "Y"; then ...   # defaults to Yes
#
# HOW IT WORKS:
#   ${2:-N}   = "if $2 is empty, default to N" (bash parameter expansion)
#   ${default^^} = convert to UPPERCASE (bash 4+ feature)
#   ${answer,,}  = convert to lowercase (bash 4+ feature)
#   [[ ... ]]    = the LAST command's exit code IS the function's return value
#                  In bash, 0 = true/success (opposite of most languages!)
ui_confirm() {
    local prompt="$1"
    # ${2:-N} means: use $2 if provided, otherwise default to "N"
    local default="${2:-N}"

    # Build the hint: "Y/n" if default is yes, "y/N" if default is no
    local hint
    if [[ "${default^^}" == "Y" ]]; then
        hint="Y/n"
    else
        hint="y/N"
    fi

    echo -en "  ${C_YELLOW}[?]${C_RESET} ${prompt} [${hint}]: " >&2

    local answer
    # -r = raw mode, don't treat backslashes as escape characters
    read -r answer

    # If user just pressed Enter, use the default
    [[ -z "$answer" ]] && answer="$default"

    # This comparison IS the return value: true if starts with 'y'
    [[ "${answer,,}" == "y"* ]]
}


# --- ui_input ---
# Asks for text input with optional default value and TAB completion.
# Usage:  NAME=$(ui_input "Enter repo name")
#         URL=$(ui_input "Remote URL" "https://github.com/...")
#
# FLAGS:
#   -r = raw (don't eat backslashes — important for URLs with special chars)
#   -e = readline (enables TAB completion for file paths + arrow key history)
#
# The prompt goes to stderr (>&2) so it's visible on screen.
# The final value goes to stdout so $(...) captures it.
ui_input() {
    local prompt="$1"
    local default="$2"

    # Build the display string: "▸ Enter repo name [default]: "
    local display="  ${C_CYAN}▸${C_RESET} ${prompt}"
    # Only show default hint if one was provided
    [[ -n "$default" ]] && display+=" ${C_DIM}[${default}]${C_RESET}"
    display+=": "

    echo -en "$display" >&2
    local value
    read -r -e value    # -r = raw, -e = readline (TAB completion)

    # If user pressed Enter without typing, use the default
    [[ -z "$value" && -n "$default" ]] && value="$default"
    # If still empty (no default either), return error
    [[ -z "$value" ]] && return 1

    echo "$value"   # Goes to stdout = captured by $(ui_input ...)
}


# --- ui_password ---
# Asks for sensitive input (PAT tokens, passwords) without showing characters.
# Usage:  TOKEN=$(ui_password "Personal Access Token")
#
# FLAG:
#   -s = silent mode. Characters are NOT echoed to the terminal as user types.
#        This is ESSENTIAL for passwords/tokens — you don't want them visible
#        in terminal history or over someone's shoulder.
#
# The extra 'echo >&2' after read adds a newline because -s suppresses it
# (without it, the next line would print on the same line as the prompt).
ui_password() {
    local prompt="$1"

    echo -en "  ${C_CYAN}🔑${C_RESET} ${prompt}: " >&2
    local password
    read -r -s password    # -r = raw, -s = silent (hidden input)
    echo >&2               # Add newline after hidden input

    [[ -z "$password" ]] && return 1
    echo "$password"       # Goes to stdout for capture
}


# --- ui_menu ---
# Displays a numbered menu and returns the text of the chosen option.
# Usage:  CHOICE=$(ui_menu "Pick Action" "Clone" "Push" "Reset" "Quit")
#
# HOW IT WORKS:
#   'shift' removes $1 (the title), so "$@" becomes just the options.
#   ${#options[@]} = number of elements in the array.
#   The while loop keeps asking until user enters a valid number.
#   =~ is bash regex match. ^[0-9]+$ = "string contains ONLY digits".
#   (( )) is arithmetic evaluation — lets us use >= and <= with numbers.
ui_menu() {
    local title="$1"
    # 'shift' removes the first argument ($1), so now $@ = remaining args
    shift
    # (...) creates an array from all remaining arguments
    local options=("$@")
    local count=${#options[@]}    # Array length

    echo -e "\n  ${C_BOLD}${title}${C_RESET}" >&2
    ui_divider

    # Print each option with its number
    local i
    for (( i=0; i<count; i++ )); do
        echo -e "  ${C_CYAN}$((i+1)))${C_RESET} ${options[$i]}" >&2
    done
    echo >&2

    # Validation loop: keep asking until we get a valid number
    while true; do
        echo -en "  ${C_YELLOW}▸${C_RESET} Choose [1-${count}]: " >&2
        local choice
        read -r choice

        # =~ is regex match: ^[0-9]+$ means "one or more digits, nothing else"
        # (( )) does arithmetic comparison
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            # Echo the TEXT of the chosen option (not the number)
            echo "${options[$((choice-1))]}"
            return 0
        fi
        ui_error "Invalid choice. Enter a number between 1 and ${count}."
    done
}


# --- ui_pick_dir ---
# Asks user to select or type a directory path, with TAB completion.
# Usage:  DEST=$(ui_pick_dir "Select repo location")
#
# KEY DETAILS:
#   -e flag on read enables TAB completion for filesystem paths!
#   ${dir/#\~/$HOME} manually expands ~ to /home/user because
#     'read -e' doesn't always expand tilde automatically.
#   realpath converts relative paths ("./stuff") to absolute ("/home/user/stuff")
#   -d flag on [[ ]] checks if the path is a valid directory.
ui_pick_dir() {
    local prompt="$1"
    local default="$2"

    echo -e "  ${C_DIM}(TAB completion enabled — type a path and press TAB)${C_RESET}" >&2
    while true; do
        local display="  ${C_CYAN}📁${C_RESET} ${prompt}"
        [[ -n "$default" ]] && display+=" ${C_DIM}[${default}]${C_RESET}"
        display+=": "

        echo -en "$display" >&2
        local dir_path
        read -r -e dir_path

        # Use default if user pressed Enter without typing
        [[ -z "$dir_path" && -n "$default" ]] && dir_path="$default"
        [[ -z "$dir_path" ]] && return 1

        # Expand ~ to actual home directory path
        # ${var/#pattern/replacement} replaces pattern at the START of var
        dir_path="${dir_path/#\~/$HOME}"
        # Convert to absolute path (resolves ../ and ./ too)
        dir_path=$(realpath -- "$dir_path" 2>/dev/null || echo "$dir_path")

        if [[ -d "$dir_path" ]]; then
            echo "$dir_path"
            return 0
        fi

        # Directory doesn't exist — offer to create it
        if ui_confirm "Directory doesn't exist. Create it?"; then
            if mkdir -p "$dir_path" 2>/dev/null; then
                ui_info "Created: $dir_path"
                echo "$dir_path"
                return 0
            else
                ui_error "Failed to create directory: ${dir_path}"
            fi
        fi
    done
}


# ==============================================================================
# SPINNER — Background Progress Indicator
# ==============================================================================
# Replaces: zenity --progress --pulsate
# Shows a spinning animation while long-running commands execute.
#
# Usage:
#   ui_spinner_start "Cloning repository..."
#   git clone https://... 2>&1
#   ui_spinner_stop
#
# HOW IT WORKS:
#   The spinner runs in a SUBSHELL sent to the BACKGROUND with &
#   $! = PID (Process ID) of the last background process
#   \r = carriage return — moves cursor to start of line (animation trick)
#   kill sends a signal to stop the background process
#   trap ensures cleanup even if the script exits unexpectedly
#
# The braille characters (⠋⠙⠹...) create a smooth rotation effect.
_SPINNER_PID=""

ui_spinner_start() {
    # Stop any existing spinner first to prevent orphan processes
    ui_spinner_stop 2>/dev/null
    
    local message="$1"
    # Braille pattern characters that animate a rotating dot
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    # Start spinner in a background subshell
    (
        local i=0
        while true; do
            # ${chars:offset:length} extracts one character at position i
            # $((i % ${#chars})) wraps around when we reach the end
            printf "\r  ${C_CYAN}${chars:$((i % ${#chars})):1}${C_RESET} ${message}" >&2
            sleep 0.1
            (( i++ ))
        done
    ) &    # & sends to background

    # $! = PID of the subprocess we just started
    _SPINNER_PID=$!
    # trap = "if the script exits for ANY reason, run this cleanup command"
    # This prevents orphan spinner processes if user hits Ctrl+C
    trap 'ui_spinner_stop 2>/dev/null' EXIT
}

ui_spinner_stop() {
    if [[ -n "$_SPINNER_PID" ]]; then
        # kill sends SIGTERM to stop the spinner subprocess
        kill "$_SPINNER_PID" 2>/dev/null
        # wait prevents "Terminated" messages from appearing
        wait "$_SPINNER_PID" 2>/dev/null
        _SPINNER_PID=""
        # Clear the spinner line (overwrite with spaces)
        printf "\r  %-60s\r" " " >&2
    fi
}


# --- ui_banner ---
# Displays the application banner/logo.
# Called once at the top of each menu refresh.
# Uses a heredoc (<<'EOF') for multi-line strings — cleaner than multiple echo.
# The single quotes around 'EOF' prevent variable expansion inside the banner,
# but we use echo -e separately for colored text below it.
ui_banner() {
    echo -e "${C_CYAN}" >&2
    cat >&2 <<'EOF'
    ╔═══════════════════════════════════════════════╗
    ║                                               ║
    ║          ⚡  Git Helper Dashboard  ⚡          ║
    ║                                               ║
    ║     Clone · Push · Reset · Copy — Made Easy   ║
    ║                                               ║
    ╚═══════════════════════════════════════════════╝
EOF
    echo -e "${C_RESET}" >&2
}
