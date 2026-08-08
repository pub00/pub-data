#!/bin/bash
# ==============================================================================
# lib/config.sh — Git Configuration & Alias Management
# ==============================================================================
#
# PURPOSE:
#   Manages Git global configuration for the helper tool:
#   - Sets up global aliases (pushall, pushall-full) ONCE at startup
#   - Configures credential storage so PAT tokens aren't re-asked
#   - Detects the default branch of any repository (main/master/etc.)
#   - Validates if a directory is a git repository
#
# WHY SEPARATE THIS?
#   In the old approach, you'd manually type "git config --global alias.pushall ..."
#   every time. This module does it automatically and IDEMPOTENTLY — meaning
#   it's safe to run 100 times; it only adds the alias if it's missing.
#   If the format ever changes, you fix it in ONE place, not scattered commands.
#
# REQUIRES: lib/ui.sh must be sourced first (for ui_info, ui_warn, etc.)
# ==============================================================================


# ==============================================================================
# ALIAS MANAGEMENT
# ==============================================================================

# --- config_ensure_aliases ---
# Checks if our custom git aliases exist in git global config.
# If they're missing, creates them. If they already exist, does nothing.
#
# This function is IDEMPOTENT: calling it multiple times has the same effect
# as calling it once. This is important because it runs every time the tool
# launches — we don't want duplicate aliases.
#
# HOW WE CHECK:
#   git config --global --get alias.pushall
#   This command returns exit code 0 if found, 1 if not found.
#   We use the exit code (not the output) to decide if we need to add it.
#
# THE ALIASES:
#   pushall      → adds new/modified files, IGNORES deletions, commits, pushes
#   pushall-full → adds ALL changes INCLUDING deletions, commits, pushes
#
# WHY '!f() { ... }; f' SYNTAX?
#   Git aliases starting with ! run as shell commands (not git subcommands).
#   We wrap in a function f() so we can accept arguments ($1 for commit msg).
#   The 'f' at the end actually CALLS the function we just defined.
#   ${1:-update} means "use $1 if provided, otherwise default to 'update'"
config_ensure_aliases() {
    local added=0    # Counter: how many aliases we added this run

    # --- Check pushall alias ---
    # --get returns the value if found (exit 0) or nothing (exit 1)
    # 2>/dev/null suppresses error messages if the key doesn't exist
    if ! git config --global --get alias.pushall &>/dev/null; then
        # Alias not found → create it
        # --ignore-removal means: stage new + modified files, but if a file
        # was DELETED from disk, DON'T stage that deletion.
        # This lets you push your work without accidentally removing files
        # from the remote that you only deleted locally.
        git config --global alias.pushall \
            '!f() { git add --ignore-removal . && git commit -m "${1:-update}" && git push; }; f'
        ui_info "Created global alias: ${C_CYAN}git pushall${C_RESET} (push without deletions)"
        (( added++ ))
    fi

    # --- Check pushall-full alias ---
    if ! git config --global --get alias.pushall-full &>/dev/null; then
        # -A (or --all) stages EVERYTHING: new, modified, AND deleted files.
        # Use this when you intentionally deleted files and want the remote
        # to reflect those deletions too.
        git config --global alias.pushall-full \
            '!f() { git add -A && git commit -m "${1:-update}" && git push; }; f'
        ui_info "Created global alias: ${C_CYAN}git pushall-full${C_RESET} (push with deletions)"
        (( added++ ))
    fi

    # Only show the "already set" message if we didn't add anything new
    if (( added == 0 )); then
        ui_info "Git aliases already configured ${C_DIM}(pushall, pushall-full)${C_RESET}"
    fi
}


# ==============================================================================
# CREDENTIAL MANAGEMENT
# ==============================================================================

# --- config_setup_credential_store ---
# Configures git to save HTTPS credentials (username + PAT token) to disk
# so you don't have to re-enter them for every push/pull.
#
# HOW IT WORKS:
#   git config --global credential.helper store
#   This tells git: "When the user enters credentials, save them in
#   ~/.git-credentials as plain text so they're reused next time."
#
# SECURITY NOTE:
#   The 'store' helper saves credentials in PLAIN TEXT at ~/.git-credentials.
#   This is fine for personal machines. For shared/public machines, consider
#   'cache' (stores in memory for a timeout) or a credential manager.
#
# WHY NOT CHECK FIRST?
#   Unlike aliases, setting credential.helper to the same value is harmless.
#   Git just overwrites the existing value. No duplicates possible.
#   But we check anyway for a cleaner user experience (skip the message if
#   already configured).
config_setup_credential_store() {
    local current
    current=$(git config --global --get credential.helper 2>/dev/null)

    if [[ "$current" == "store" ]]; then
        ui_info "Credential storage already configured ${C_DIM}(store mode)${C_RESET}"
        return 0
    fi

    git config --global credential.helper store
    ui_info "Configured credential storage: ${C_CYAN}git credentials will be saved${C_RESET}"
    ui_warn "Credentials are stored in ${C_DIM}~/.git-credentials${C_RESET} (plain text)"
}

# --- config_ensure_identity ---
# Verifies that git global user.name and user.email are set.
# If missing, prompts the user to enter them.
config_ensure_identity() {
    local name
    name=$(git config --global user.name)
    local email
    email=$(git config --global user.email)

    if [[ -n "$name" && -n "$email" ]]; then
        ui_info "Git identity already configured: ${C_CYAN}${name} <${email}>${C_RESET}"
        return 0
    fi

    ui_warn "Git identity (name/email) is not configured."
    echo -e "  ${C_DIM}This is required for your commits to show your name on GitHub.${C_RESET}" >&2

    if [[ -z "$name" ]]; then
        name=$(ui_input "Enter your Full Name (e.g., John Doe)")
        [[ -z "$name" ]] && return 1
        git config --global user.name "$name"
    fi

    if [[ -z "$email" ]]; then
        email=$(ui_input "Enter your Git Email (the one used for GitHub)")
        [[ -z "$email" ]] && return 1
        git config --global user.email "$email"
    fi

    ui_success "Git identity saved: ${C_CYAN}${name} <${email}>${C_RESET}"
}

# --- config_ensure_global_auth ---
# Verifies that GitHub credentials exist in ~/.git-credentials.
# If missing, prompts the user for username + PAT token and saves them.
config_ensure_global_auth() {
    # Ensure helper is set first
    config_setup_credential_store

    # Check if any github.com credentials exist
    if [[ -f "$HOME/.git-credentials" ]] && grep -q "github.com" "$HOME/.git-credentials"; then
        ui_info "Global GitHub credentials already found."
        return 0
    fi

    ui_warn "No GitHub credentials found on this system."
    echo -e "  ${C_DIM}Please provide your username and Personal Access Token (PAT).${C_RESET}" >&2

    local user
    user=$(ui_input "GitHub username")
    [[ -z "$user" ]] && return 1

    local pat
    pat=$(ui_password "GitHub PAT token")
    [[ -z "$pat" ]] && return 1

    # Save to store
    echo "https://${user}:${pat}@github.com" >> "$HOME/.git-credentials"
    chmod 600 "$HOME/.git-credentials"
    
    ui_success "GitHub credentials saved to: ${C_DIM}~/.git-credentials${C_RESET}"
}


# ==============================================================================
# REPOSITORY UTILITIES
# ==============================================================================

# --- config_detect_branch ---
# Detects the default branch of a remote repository.
# Returns the branch name (e.g., "main", "master", "develop").
#
# WHY IS THIS NEEDED?
#   Not all repos use "main" — older repos use "master", some use "develop".
#   Hardcoding "main" would break on repos with different default branches.
#   This function auto-detects the correct branch name.
#
# HOW IT WORKS (3 strategies, from most to least reliable):
#   1. git symbolic-ref refs/remotes/origin/HEAD — fastest, works if HEAD is set
#   2. git remote show origin — queries the remote server (needs network)
#   3. Falls back to "main" if both fail
#
# The sed command extracts just the branch name from the full ref:
#   "refs/remotes/origin/main" → "main"
config_detect_branch() {
    local repo_dir="${1:-.}"    # Default to current directory

    # Strategy 1: Check local symbolic ref (fast, no network needed)
    # symbolic-ref shows what refs/remotes/origin/HEAD points to
    local branch
    branch=$(git -C "$repo_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's|refs/remotes/origin/||')

    if [[ -n "$branch" ]]; then
        echo "$branch"
        return 0
    fi

    # Strategy 2: Ask the remote server (slower, needs network)
    # "git remote show origin" prints info including "HEAD branch: main"
    # We grep for that line and extract the branch name
    branch=$(git -C "$repo_dir" remote show origin 2>/dev/null \
        | grep 'HEAD branch' \
        | sed 's/.*: //')

    if [[ -n "$branch" ]]; then
        echo "$branch"
        return 0
    fi

    # Strategy 3: Fallback to "main" (most common modern default)
    echo "main"
}


# --- config_check_git_repo ---
# Checks if a given directory is inside a valid git repository.
# Returns 0 (true) if yes, 1 (false) if no.
#
# HOW IT WORKS:
#   git rev-parse --is-inside-work-tree
#   This prints "true" and exits 0 if inside a git repo.
#   Prints nothing and exits 128 if NOT inside a git repo.
#
# The -C flag tells git to operate in a specific directory
# instead of the current working directory:
#   git -C /some/path rev-parse ...
#   This is better than cd-ing because we don't change the shell's
#   working directory (which could cause bugs elsewhere).
config_check_git_repo() {
    local dir="${1:-.}"
    dir=$(realpath -- "$dir" 2>/dev/null || echo "$dir")

    # 1. Basic check: does git even see a repo here?
    if ! git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
        return 1
    fi

    # 2. Strict check: is this the ROOT of the repo?
    # We compare the directory's realpath with git's idea of the "toplevel".
    local toplevel
    toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
    toplevel=$(realpath -- "$toplevel" 2>/dev/null || echo "$toplevel")

    if [[ "$dir" == "$toplevel" ]]; then
        return 0    # It IS a git repo root
    fi

    return 1    # It's just a subfolder inside another repo
}


# --- config_get_remote_url ---
# Gets the remote origin URL of a git repository.
# Usage: URL=$(config_get_remote_url "/path/to/repo")
#
# git remote get-url origin
#   Returns the URL configured for the 'origin' remote.
#   Most repos have a single remote called 'origin'.
config_get_remote_url() {
    local dir="${1:-.}"
    git -C "$dir" remote get-url origin 2>/dev/null
}


# --- config_get_current_branch ---
# Gets the current checked-out branch name.
# Usage: BRANCH=$(config_get_current_branch "/path/to/repo")
#
# git branch --show-current (Git 2.22+)
#   Prints just the branch name, nothing else.
#   This is cleaner than: git rev-parse --abbrev-ref HEAD
config_get_current_branch() {
    local dir="${1:-.}"
    git -C "$dir" branch --show-current 2>/dev/null
}


# ==============================================================================
# REPO MANAGEMENT — Persistent Repo Registry
# ==============================================================================
#
# PURPOSE:
#   Instead of typing the repo path every time you push/reset, you register
#   repos once and then select them from a list. One repo is always "active"
#   and shown on the dashboard. Push/reset operate on the active repo.
#
# FILES:
#   ~/.config/git_helper/repos.conf   — One repo path per line
#   ~/.config/git_helper/active.conf  — Single line: path of the active repo
#
# WHY ~/.config/?
#   This follows the XDG Base Directory Specification — the standard place
#   for user-specific application config on Linux. Most modern apps use this.
#   It keeps your $HOME directory clean (no dotfiles cluttering ls).

# --- Config directory setup ---
# We define REPO_CONFIG_DIR here so all functions can use it.
# The 'readonly' prevents accidental changes later.
REPO_CONFIG_DIR="${HOME}/.config/git_helper"
REPO_CONFIG_FILE="${REPO_CONFIG_DIR}/repos.conf"
REPO_ACTIVE_FILE="${REPO_CONFIG_DIR}/active.conf"

# --- config_repo_init ---
# Ensures the config directory and files exist.
# 'mkdir -p' creates parent directories if needed AND is safe if they exist.
# 'touch' creates empty files if missing, does nothing if they exist.
config_repo_init() {
    mkdir -p "$REPO_CONFIG_DIR"
    touch "$REPO_CONFIG_FILE"
    touch "$REPO_ACTIVE_FILE"
}

# --- config_repo_add ---
# Registers a new repo path in the config file.
# Usage: config_repo_add "/home/user/Desktop/Learning"
#
# We validate that:
#   1. The path is a valid directory
#   2. The path is a git repository
#   3. The path isn't already registered (no duplicates)
#
# grep -qxF: -q = quiet, -x = match whole line, -F = fixed string
# This prevents partial matches (e.g., "/home" matching "/home/user")
config_repo_add() {
    local repo_path="$1"

    # Validate it's a directory
    if [[ ! -d "$repo_path" ]]; then
        ui_error "Not a valid directory: ${repo_path}"
        return 1
    fi

    # Validate it's a git repo
    if ! config_check_git_repo "$repo_path"; then
        ui_warn "Not a git repository root: ${repo_path}"
        
        # New Feature: Offer to initialize if it's not a repo yet
        if ui_confirm "Would you like to initialize this folder as a new Git repository?" "Y"; then
            ui_spinner_start "Initializing repository..."
            if git -C "$repo_path" init 2>/dev/null; then
                ui_spinner_stop
                ui_success "Repository initialized successfully!"
            else
                ui_spinner_stop
                ui_error "Failed to initialize repository."
                return 1
            fi
        else
            return 1
        fi
    fi

    # Resolve to absolute path (handles ~/stuff, ../stuff, etc.)
    repo_path=$(realpath -- "$repo_path" 2>/dev/null)

    # Check for duplicates
    # grep -qxF: -q quiet, -x match ENTIRE line, -F fixed string (no regex)
    if grep -qxF "$repo_path" "$REPO_CONFIG_FILE" 2>/dev/null; then
        ui_warn "Repo already registered: ${repo_path}"
        return 0
    fi

    # Append to config file
    echo "$repo_path" >> "$REPO_CONFIG_FILE"
    ui_success "Repo added: ${C_CYAN}${repo_path}${C_RESET}"

    # If this is the first repo, automatically set it as active
    # wc -l counts lines. We use awk to strip whitespace from wc output.
    local count
    count=$(grep -c '.' "$REPO_CONFIG_FILE" 2>/dev/null || echo "0")
    if (( count == 1 )); then
        config_repo_set_active "$repo_path"
        ui_info "Auto-selected as active repo (it's the only one)"
    fi
}

# --- config_repo_remove ---
# Removes a repo path from the config file.
# Usage: config_repo_remove "/home/user/Desktop/Learning"
#
# We rebuild the file without the target line (same safe approach as
# Secure Manager's config_remove — avoids sed regex issues).
config_repo_remove() {
    local repo_path="$1"

    # Resolve to absolute path for consistent matching
    repo_path=$(realpath -- "$repo_path" 2>/dev/null || echo "$repo_path")

    if [[ ! -f "$REPO_CONFIG_FILE" ]]; then
        ui_error "No repos registered yet."
        return 1
    fi

    # Rebuild config without the target path
    local tmpfile
    tmpfile=$(mktemp)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == "$repo_path" ]] && continue
        echo "$line"
    done < "$REPO_CONFIG_FILE" > "$tmpfile"

    mv "$tmpfile" "$REPO_CONFIG_FILE"
    ui_info "Repo removed: ${C_DIM}${repo_path}${C_RESET}"

    # If the removed repo was the active one, clear the active selection
    local active
    active=$(config_repo_get_active)
    if [[ "$active" == "$repo_path" ]]; then
        echo "" > "$REPO_ACTIVE_FILE"
        ui_warn "Active repo was removed. Please select a new one."
    fi
}

# --- config_repo_list ---
# Returns all registered repo paths (one per line).
# Returns 1 if no repos are registered (for easy checking).
config_repo_list() {
    if [[ ! -s "$REPO_CONFIG_FILE" ]]; then
        return 1    # No repos
    fi

    # Read and print each non-empty line
    while IFS= read -r line; do
        [[ -n "$line" ]] && echo "$line"
    done < "$REPO_CONFIG_FILE"
}

# --- config_repo_count ---
# Returns the number of registered repos.
config_repo_count() {
    if [[ ! -s "$REPO_CONFIG_FILE" ]]; then
        echo "0"
        return
    fi
    grep -c '.' "$REPO_CONFIG_FILE" 2>/dev/null || echo "0"
}

# --- config_repo_set_active ---
# Sets the active repo (the one that push/reset will operate on).
# Usage: config_repo_set_active "/home/user/Desktop/Learning"
#
# We write a single line to active.conf. Using > (overwrite, not >>).
config_repo_set_active() {
    local repo_path="$1"
    echo "$repo_path" > "$REPO_ACTIVE_FILE"
}

# --- config_repo_get_active ---
# Returns the path of the currently active repo.
# Returns empty string (and exit 1) if none is set.
#
# 'head -n 1' ensures we only read the first line (safety).
# The sed command removes any leading/trailing whitespace/newlines while preserving spaces inside the path.
config_repo_get_active() {
    if [[ ! -s "$REPO_ACTIVE_FILE" ]]; then
        return 1
    fi

    local active
    # The sed command removes any leading/trailing whitespace/newlines while preserving internal spaces.
    active=$(head -n 1 "$REPO_ACTIVE_FILE" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if [[ -z "$active" ]]; then
        return 1
    fi

    # Verify the path still exists and is still a git repo
    if [[ ! -d "$active" ]] || ! config_check_git_repo "$active"; then
        return 1
    fi

    echo "$active"
}

# --- config_repo_show_status ---
# Displays the active repo status on the dashboard.
# Shows: repo name, path, branch, and remote URL.
# This is called from the main menu loop to show current state.
config_repo_show_status() {
    local active
    active=$(config_repo_get_active)

    if [[ -z "$active" ]]; then
        echo -e "  ${C_YELLOW}[!]${C_RESET} ${C_DIM}No active repo selected. Use 'Manage Repos' to add one.${C_RESET}" >&2
        return 1
    fi

    # Extract the repo name (last component of the path)
    # basename "/home/user/Desktop/Learning" → "Learning"
    local name
    name=$(basename "$active")

    local branch
    branch=$(config_get_current_branch "$active")

    local remote_url
    remote_url=$(config_get_remote_url "$active")

    # Display a compact status box
    echo -e "  ${C_GREEN}●${C_RESET} ${C_BOLD}Active Repo:${C_RESET} ${C_CYAN}${name}${C_RESET}" >&2
    echo -e "    ${C_DIM}Path:   ${active}${C_RESET}" >&2
    echo -e "    ${C_DIM}Branch: ${branch:-unknown}${C_RESET}" >&2
    [[ -n "$remote_url" ]] && echo -e "    ${C_DIM}Remote: ${remote_url}${C_RESET}" >&2
    echo >&2
}

# --- config_repo_select_interactive ---
# Shows a numbered list of registered repos and lets user pick one.
# Returns the selected repo path via stdout.
# Used by the "Manage Repos" menu to switch the active repo.
config_repo_select_interactive() {
    local prompt="${1:-Select a repo}"

    # Build array of repos
    local repos=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && repos+=("$line")
    done < "$REPO_CONFIG_FILE"

    local count=${#repos[@]}

    if (( count == 0 )); then
        ui_warn "No repos registered. Add one first."
        return 1
    fi

    # Show the list with status info
    echo -e "\n  ${C_BOLD}Registered Repos:${C_RESET}" >&2
    ui_divider

    local active
    active=$(config_repo_get_active)

    local i
    for (( i=0; i<count; i++ )); do
        local repo="${repos[$i]}"
        local name
        name=$(basename "$repo")

        # Show a marker for the active repo
        local marker=""
        [[ "$repo" == "$active" ]] && marker=" ${C_GREEN}← active${C_RESET}"

        echo -e "  ${C_CYAN}$((i+1)))${C_RESET} ${C_BOLD}${name}${C_RESET}${marker}" >&2
        echo -e "     ${C_DIM}${repo}${C_RESET}" >&2
    done
    echo >&2

    # Ask user to pick
    while true; do
        echo -en "  ${C_YELLOW}▸${C_RESET} ${prompt} [1-${count}]: " >&2
        local choice
        read -r choice

        [[ -z "$choice" ]] && return 1

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            echo "${repos[$((choice-1))]}"
            return 0
        fi
        ui_error "Invalid choice."
    done
}

# --- core_manage_repos ---
# Interactive menu for managing the repo registry.
# Options: Add, Remove, Switch active, Back.
# This is a sub-menu called from the main dashboard.
core_manage_repos() {
    while true; do
        clear
        ui_header "📂 Manage Repositories"

        # Show current repos
        local count
        count=$(config_repo_count)
        if (( count > 0 )); then

            # Show the list without selecting
            local repos=()
            while IFS= read -r line; do
                [[ -n "$line" ]] && repos+=("$line")
            done < "$REPO_CONFIG_FILE"

            local active
            active=$(config_repo_get_active)

            echo -e "  ${C_BOLD}Registered Repos (${count}):${C_RESET}" >&2
            ui_divider
            local i
            for (( i=0; i<${#repos[@]}; i++ )); do
                local repo="${repos[$i]}"
                local name
                name=$(basename "$repo")
                local marker=""
                [[ "$repo" == "$active" ]] && marker=" ${C_GREEN}← active${C_RESET}"
                echo -e "  ${C_CYAN}$((i+1)))${C_RESET} ${C_BOLD}${name}${C_RESET}${marker}" >&2
                echo -e "     ${C_DIM}${repo}${C_RESET}" >&2
            done
            echo >&2
        else
            echo -e "  ${C_DIM}No repos registered yet.${C_RESET}" >&2
            echo >&2
        fi

        # Sub-menu
        local action
        action=$(ui_menu "Repo Management" \
            "➕  Add a repo" \
            "🔄  Switch active repo" \
            "🌐  Set/Change Remote URL" \
            "➖  Remove a repo" \
            "🔙  Back to main menu")

        case "$action" in
            "➕  Add a repo")
                echo >&2
                local new_path
                new_path=$(ui_pick_dir "Path to the git repository")
                if [[ $? -eq 0 && -n "$new_path" ]]; then
                    config_repo_add "$new_path"
                fi
                echo >&2
                read -r -p "  Press Enter to continue..."
                ;;

            "🔄  Switch active repo")
                echo >&2
                local selected
                selected=$(config_repo_select_interactive "Switch to")
                if [[ $? -eq 0 && -n "$selected" ]]; then
                    config_repo_set_active "$selected"
                    ui_success "Active repo set to: ${C_CYAN}$(basename "$selected")${C_RESET}"
                fi
                echo >&2
                read -r -p "  Press Enter to continue..."
                ;;

            "🌐  Set/Change Remote URL")
                echo >&2
                local target_repo
                target_repo=$(config_repo_select_interactive "Select repo to update remote")
                if [[ $? -eq 0 && -n "$target_repo" ]]; then
                    local current_remote
                    current_remote=$(config_get_remote_url "$target_repo")
                    [[ -n "$current_remote" ]] && ui_info "Current Remote: ${C_DIM}${current_remote}${C_RESET}"

                    local new_url
                    new_url=$(ui_input "New Remote HTTPS URL" "https://github.com/user/repo.git")
                    if [[ -n "$new_url" ]]; then
                        ui_info "Setting remote URL to: ${C_CYAN}${new_url}${C_RESET}"
                        
                        # Add or set the remote
                        if [[ -z "$current_remote" ]]; then
                            git -C "$target_repo" remote add origin "$new_url" 2>&1
                        else
                            git -C "$target_repo" remote set-url origin "$new_url" 2>&1
                        fi
                        
                        if [[ $? -eq 0 ]]; then
                            ui_success "Remote URL updated successfully!"
                            # Test the connection
                            ui_spinner_start "Verifying connection..."
                            if git -C "$target_repo" ls-remote origin >/dev/null 2>&1; then
                                ui_spinner_stop
                                ui_success "Connection verified — repository is ready!"
                            else
                                ui_spinner_stop
                                ui_warn "URL set, but could not verify connection. Check your PAT and URL."
                            fi
                        else
                            ui_error "Failed to set remote URL."
                        fi
                    fi
                fi
                echo >&2
                read -r -p "  Press Enter to continue..."
                ;;

            "➖  Remove a repo")
                echo >&2
                local to_remove
                to_remove=$(config_repo_select_interactive "Remove")
                if [[ $? -eq 0 && -n "$to_remove" ]]; then
                    local rname
                    rname=$(basename "$to_remove")
                    if ui_confirm "Remove '${rname}' from the list? (does NOT delete files)" "N"; then
                        config_repo_remove "$to_remove"
                    else
                        ui_warn "Cancelled."
                    fi
                fi
                echo >&2
                read -r -p "  Press Enter to continue..."
                ;;

            "🔙  Back to main menu")
                return 0
                ;;
        esac
    done
}
