#!/bin/bash
# ==============================================================================
# lib/core.sh — Core Git Operations
# ==============================================================================
#
# PURPOSE:
#   All the actual git work happens here — clone, push, reset, copy.
#   Each function handles one menu action end-to-end.
#
# REQUIRES: lib/ui.sh and lib/config.sh must be sourced first.
# ==============================================================================


# ==============================================================================
# DEPENDENCY CHECK
# ==============================================================================

# --- core_check_deps ---
# Verifies git is installed. If missing, shows distro-specific install commands.
# 'command -v' returns the path to an executable (or fails if not found).
# It's more portable than 'which' (which isn't POSIX-guaranteed).
core_check_deps() {
    if command -v git &>/dev/null; then
        return 0
    fi

    ui_error "Git is not installed!"
    echo >&2
    ui_warn "Install it with one of these commands:"
    echo -e "  ${C_DIM}Ubuntu/Debian:${C_RESET}  sudo apt install git" >&2
    echo -e "  ${C_DIM}Arch/Manjaro:${C_RESET}   sudo pacman -S git" >&2
    echo -e "  ${C_DIM}Fedora/RHEL:${C_RESET}    sudo dnf install git" >&2
    echo >&2
    exit 1
}


# ==============================================================================
# HELPER: Get the active repo
# ==============================================================================

# --- _get_active_repo ---
# Internal helper that returns the active repo path.
# If no active repo is set, shows an error and returns 1.
#
# This replaces the old _ask_repo_dir() which asked every time.
# Now the user sets their repo ONCE via "Manage Repos" and all
# push/reset operations use it automatically.
#
# Prefixed with _ to indicate it's "private" (convention, not enforced).
_get_active_repo() {
    local repo_dir
    repo_dir=$(config_repo_get_active)

    if [[ -z "$repo_dir" ]]; then
        ui_error "No active repo selected!"
        ui_warn "Go to ${C_CYAN}Manage Repos${C_RESET} to add and select a repository first."
        return 1
    fi

    # Double-check it's still a valid git repo (user might have deleted it)
    if ! config_check_git_repo "$repo_dir"; then
        ui_error "Active repo is no longer a valid git repository: ${repo_dir}"
        ui_warn "Go to ${C_CYAN}Manage Repos${C_RESET} to update your selection."
        return 1
    fi

    echo "$repo_dir"
}


# ==============================================================================
# FEATURE 1: Clone Remote Repository
# ==============================================================================

# --- core_clone_repo ---
# Full flow: ask URL → ask path → ask PAT → init → remote add → pull.
#
# WHY git init + remote add + pull INSTEAD OF git clone?
#   Both work, but init+remote gives us more control:
#   - We can set up the credential store BEFORE the first pull
#   - We can handle the PAT token embedding in the URL
#   - We can create the directory structure exactly how we want
#   git clone does all of this in one command but is a "black box".
#
# CREDENTIAL EMBEDDING:
#   When using a PAT with HTTPS, git needs authentication.
#   We store credentials via 'git credential-store' which saves them
#   in ~/.git-credentials after the first successful authentication.
#   Format: https://USERNAME:TOKEN@github.com
core_clone_repo() {
    ui_header "📥 Clone Remote Repository"

    # --- Step 1: Get the remote URL ---
    local remote_url
    remote_url=$(ui_input "Remote HTTPS URL" "https://github.com/user/repo.git")
    [[ $? -ne 0 || -z "$remote_url" ]] && return 1

    # Basic validation: must look like an HTTPS git URL
    # =~ is bash regex match. We check for https:// prefix.
    if [[ ! "$remote_url" =~ ^https:// ]]; then
        ui_error "URL must start with https:// (HTTPS protocol)"
        return 1
    fi

    # --- Step 2: Get the local directory path ---
    local local_dir
    local_dir=$(ui_pick_dir "Local directory to clone into" "$HOME")
    [[ $? -ne 0 || -z "$local_dir" ]] && return 1

    # --- Step 3: Ask for Personal Access Token (PAT) ---
    # PATs are used instead of passwords for GitHub HTTPS authentication.
    # Since 2021, GitHub no longer accepts passwords for git operations.
    ui_warn "GitHub requires a Personal Access Token (PAT) for HTTPS."
    echo -e "  ${C_DIM}Generate one at: GitHub → Settings → Developer Settings → Tokens${C_RESET}" >&2

    local pat=""
    if ui_confirm "Do you have a PAT token?" "Y"; then
        pat=$(ui_password "Enter your PAT token")
        [[ $? -ne 0 ]] && ui_warn "No token provided — git may ask for credentials during pull"
    fi

    # --- Step 4: Ask for GitHub username if PAT provided ---
    local git_user=""
    if [[ -n "$pat" ]]; then
        git_user=$(ui_input "GitHub username")
        [[ $? -ne 0 || -z "$git_user" ]] && return 1
    fi

    # --- Step 5: Setup credential store ---
    # This tells git to save credentials in ~/.git-credentials after first use
    config_setup_credential_store

    # --- Step 6: Initialize the repository ---
    ui_divider
    ui_info "Initializing repository in: ${C_CYAN}${local_dir}${C_RESET}"

    # git init: creates the .git/ directory that makes a folder a "git repo"
    # -C flag = run git in the specified directory (avoids cd)
    if ! git -C "$local_dir" init 2>&1; then
        ui_error "Failed to initialize repository"
        return 1
    fi

    # --- Step 7: Add remote origin ---
    # 'origin' is the conventional name for the primary remote repository.
    # You can have multiple remotes (origin, upstream, etc.) but origin is standard.

    # Remove existing origin if present (in case dir was already partially setup)
    git -C "$local_dir" remote remove origin 2>/dev/null

    git -C "$local_dir" remote add origin "$remote_url"
    ui_info "Remote 'origin' set to: ${C_DIM}${remote_url}${C_RESET}"

    # --- Step 8: Pre-store credentials if PAT was provided ---
    # We write directly to ~/.git-credentials so git doesn't prompt
    if [[ -n "$pat" && -n "$git_user" ]]; then
        # Extract the hostname from the URL (e.g., github.com)
        # sed removes the https:// prefix and everything after the first /
        local host
        host=$(echo "$remote_url" | sed 's|https://||' | sed 's|/.*||')

        # Write credential in the format git expects:
        # https://username:token@hostname
        local cred_line="https://${git_user}:${pat}@${host}"

        # Check if this credential already exists to avoid duplicates
        # grep -qF: -q = quiet, -F = fixed string (no regex)
        if ! grep -qF "$cred_line" "$HOME/.git-credentials" 2>/dev/null; then
            echo "$cred_line" >> "$HOME/.git-credentials"
            # Protect the file: only the owner can read/write
            chmod 600 "$HOME/.git-credentials"
        fi
        ui_info "Credentials saved for ${C_CYAN}${host}${C_RESET}"
    fi

    # --- Step 9: Pull from remote ---
    ui_info "Pulling from remote..."
    ui_spinner_start "Fetching repository contents..."

    # Try to pull. We capture stderr too because git sends progress to stderr.
    # 2>&1 redirects stderr to stdout so we can capture both.
    local pull_output
    pull_output=$(git -C "$local_dir" pull origin main 2>&1)
    local pull_exit=$?
    ui_spinner_stop

    if [[ $pull_exit -ne 0 ]]; then
        # Pull failed — maybe branch is 'master' not 'main'
        ui_warn "Pull from 'main' failed. Trying 'master'..."
        pull_output=$(git -C "$local_dir" pull origin master 2>&1)
        pull_exit=$?
    fi

    if [[ $pull_exit -ne 0 ]]; then
        ui_error "Pull failed. Output:"
        echo -e "  ${C_DIM}${pull_output}${C_RESET}" >&2
        ui_warn "Repository was initialized but pull failed. Check your URL and credentials."
        return 1
    fi

    # --- Step 10: Show success + auto-register ---
    ui_divider
    ui_success "Repository cloned successfully!"
    ui_info "Location: ${C_CYAN}${local_dir}${C_RESET}"

    # Show repo status summary
    local file_count
    file_count=$(find "$local_dir" -not -path '*/.git/*' -type f | wc -l)
    ui_info "Files: ${C_CYAN}${file_count}${C_RESET}"

    local branch
    branch=$(config_get_current_branch "$local_dir")
    ui_info "Branch: ${C_CYAN}${branch:-unknown}${C_RESET}"

    # Auto-register the cloned repo and set it as active
    # This way the user doesn't have to manually add it via Manage Repos
    config_repo_add "$local_dir"
    config_repo_set_active "$local_dir"
    ui_info "Set as active repo automatically"
}


# ==============================================================================
# FEATURE 2: Push Changes (Keep Deleted Files)
# ==============================================================================

# --- core_push_no_delete ---
# Stages new + modified files (ignores deletions), commits, and pushes.
# Uses the global alias 'pushall' we set up in config.sh.
#
# WHY --ignore-removal?
#   Sometimes you delete a file locally (maybe for cleanup or testing)
#   but you don't want that deletion to propagate to the remote repo.
#   --ignore-removal tells git: "only look at files that EXIST on disk".
core_push_no_delete() {
    ui_header "📤 Push Changes (Keep Deleted Files)"
    ui_info "This will push ${C_CYAN}new and modified${C_RESET} files only."
    ui_info "Deleted files will ${C_YELLOW}NOT${C_RESET} be removed from the remote."
    echo >&2

    # --- Get the active repo (set once via Manage Repos) ---
    local repo_dir
    repo_dir=$(_get_active_repo)
    [[ $? -ne 0 || -z "$repo_dir" ]] && return 1

    # --- Show current status ---
    ui_divider
    ui_info "Repository: ${C_CYAN}${repo_dir}${C_RESET}"
    local branch
    branch=$(config_get_current_branch "$repo_dir")
    ui_info "Branch: ${C_CYAN}${branch:-unknown}${C_RESET}"
    echo >&2

    # Show what will be staged (preview for the user)
    echo -e "  ${C_BOLD}Changed files:${C_RESET}" >&2
    # git status --short shows a compact list: M=modified, ?=untracked, D=deleted
    git -C "$repo_dir" status --short 2>/dev/null | head -20 | while read -r line; do
        echo -e "    ${C_DIM}${line}${C_RESET}" >&2
    done
    echo >&2

    # --- Ask for commit message ---
    local commit_msg
    commit_msg=$(ui_input "Commit message" "update")
    [[ $? -ne 0 ]] && commit_msg="update"

    # --- Confirm and push ---
    if ! ui_confirm "Push changes now?" "Y"; then
        ui_warn "Push cancelled."
        return 0
    fi

    ui_spinner_start "Pushing changes..."
    # We run the commands directly instead of the alias for better error handling
    # --ignore-removal = stage everything EXCEPT deletions
    local output
    git -C "$repo_dir" add --ignore-removal . 2>/dev/null

    output=$(git -C "$repo_dir" commit -m "$commit_msg" 2>&1)
    local commit_exit=$?

    if [[ $commit_exit -ne 0 ]]; then
        ui_spinner_stop
        # Exit code 1 from commit usually means "nothing to commit"
        if echo "$output" | grep -q "nothing to commit"; then
            ui_info "Nothing to commit — working tree is clean."
            return 0
        fi
        ui_error "Commit failed: ${output}"
        return 1
    fi

    output=$(git -C "$repo_dir" push 2>&1)
    local push_exit=$?

    # --- AUTO-UPSTREAM: Handle "no upstream branch" ---
    # This happens when you push a new branch for the first time.
    # We detect the error and automatically run --set-upstream.
    if [[ $push_exit -ne 0 ]] && echo "$output" | grep -q "no upstream branch"; then
        ui_warn "No upstream branch set. Configuring automatically..."
        local branch_name
        branch_name=$(config_get_current_branch "$repo_dir")
        [[ -z "$branch_name" ]] && branch_name=$(config_detect_branch "$repo_dir")
        
        ui_spinner_start "Setting upstream and pushing..."
        output=$(git -C "$repo_dir" push --set-upstream origin "$branch_name" 2>&1)
        push_exit=$?
        ui_spinner_stop
        
        if [[ $push_exit -eq 0 ]]; then
            ui_spinner_stop
            ui_success "Upstream configured and changes pushed!"
            return 0
        fi
    fi

    ui_spinner_stop

    # --- AUTO-SYNC: Handle "rejected because remote is ahead" ---
    # This happens when someone (or you from another machine) pushed commits
    # to the remote that you don't have locally. Git refuses the push because
    # it would overwrite those remote commits.
    #
    # FIX: pull --rebase fetches the remote commits and replays YOUR local
    # commits ON TOP of them, creating a clean linear history (no merge commits).
    # Then we retry the push.
    #
    # WHY --rebase INSTEAD OF merge?
    #   'git pull' (default) = fetch + merge → creates an ugly merge commit
    #   'git pull --rebase'  = fetch + rebase → clean linear history
    #   Rebase literally "replays" your commits after the remote ones,
    #   as if you had pulled first before making your changes.
    if [[ $push_exit -ne 0 ]] && echo "$output" | grep -qE 'rejected|fetch first|non-fast-forward'; then
        ui_warn "Remote has newer commits. Syncing automatically..."
        echo >&2

        # Detect the branch name so we pull the right one
        local branch_name
        branch_name=$(config_get_current_branch "$repo_dir")
        [[ -z "$branch_name" ]] && branch_name=$(config_detect_branch "$repo_dir")

        ui_spinner_start "Pulling remote changes (rebase)..."
        local pull_output
        pull_output=$(git -C "$repo_dir" pull --rebase origin "$branch_name" 2>&1)
        local pull_exit=$?
        ui_spinner_stop

        if [[ $pull_exit -ne 0 ]]; then
            # Verify stored credentials for the active repository (if any)
if config_repo_get_active > /dev/null 2>&1; then
    # Extract remote host for the active repo
    local active_repo=$(config_repo_get_active)
    local remote_url=$(config_get_remote_url "$active_repo")
    if [[ -n "$remote_url" ]]; then
        local host=$(echo "$remote_url" | sed 's|https://||' | sed 's|/.*||')
        # If this host hasn't been validated before, run the check
        if ! grep -Fxq "$host" "${REPO_CONFIG_DIR}/cred_validated" 2>/dev/null; then
            core_ensure_credentials
        else
            ui_success "Stored credentials for ${host} already validated."
        fi
    fi
fi
            # 'git rebase --abort' undoes the partial rebase, restoring the
            # repo to its state before we ran pull --rebase.
            git -C "$repo_dir" rebase --abort 2>/dev/null
            ui_error "Auto-sync failed — there are conflicts between your changes and the remote."
            echo -e "  ${C_DIM}${pull_output}${C_RESET}" >&2
            echo >&2
            ui_warn "To fix this manually:"
            echo -e "  ${C_DIM}1. cd ${repo_dir}${C_RESET}" >&2
            echo -e "  ${C_DIM}2. git pull --rebase origin ${branch_name}${C_RESET}" >&2
            echo -e "  ${C_DIM}3. Resolve conflicts, then: git rebase --continue${C_RESET}" >&2
            echo -e "  ${C_DIM}4. git push${C_RESET}" >&2
            return 1
        fi

        ui_success "Remote changes integrated successfully!"
        echo >&2

        # Retry the push now that we're in sync
        ui_spinner_start "Retrying push..."
        output=$(git -C "$repo_dir" push 2>&1)
        push_exit=$?
        ui_spinner_stop

        if [[ $push_exit -ne 0 ]]; then
            ui_error "Push still failed after sync:"
            echo -e "  ${C_DIM}${output}${C_RESET}" >&2
            return 1
        fi

    elif [[ $push_exit -ne 0 ]]; then
        # Some other push error (not a sync issue)
        ui_error "Push failed:"
        echo -e "  ${C_DIM}${output}${C_RESET}" >&2
        return 1
    fi

    ui_success "Changes pushed successfully! (deletions preserved on remote)"
}


# ==============================================================================
# FEATURE 3: Push All Changes (Including Deletions)
# ==============================================================================

# --- core_push_full ---
# Stages ALL changes (new, modified, AND deleted), commits, and pushes.
# Uses 'git add -A' which is the most aggressive staging mode.
#
# WHY -A (--all)?
#   -A stages EVERYTHING in the working tree:
#   - New files (untracked → staged)
#   - Modified files (changes → staged)
#   - Deleted files (removal → staged)
#   This makes the remote an exact mirror of your local state.
core_push_full() {
    ui_header "📤 Push All Changes (Including Deletions)"
    ui_warn "This will push ${C_RED}ALL changes${C_RESET} including ${C_RED}file deletions${C_RESET}."
    echo >&2

    # --- Get the active repo (set once via Manage Repos) ---
    local repo_dir
    repo_dir=$(_get_active_repo)
    [[ $? -ne 0 || -z "$repo_dir" ]] && return 1

    # --- Show current status ---
    ui_divider
    ui_info "Repository: ${C_CYAN}${repo_dir}${C_RESET}"
    local branch
    branch=$(config_get_current_branch "$repo_dir")
    ui_info "Branch: ${C_CYAN}${branch:-unknown}${C_RESET}"
    echo >&2

    # Show changed files including deletions
    echo -e "  ${C_BOLD}All changes (including deletions):${C_RESET}" >&2
    git -C "$repo_dir" status --short 2>/dev/null | head -20 | while read -r line; do
        # Color deleted files red, everything else dim
        if [[ "$line" == D* || "$line" == *D\ * ]]; then
            echo -e "    ${C_RED}${line}${C_RESET}" >&2
        else
            echo -e "    ${C_DIM}${line}${C_RESET}" >&2
        fi
    done
    echo >&2

    # --- Ask for commit message ---
    local commit_msg
    commit_msg=$(ui_input "Commit message" "update")
    [[ $? -ne 0 ]] && commit_msg="update"

    # --- Confirm ---
    if ! ui_confirm "Push ALL changes (including deletions)?" "Y"; then
        ui_warn "Push cancelled."
        return 0
    fi

    ui_spinner_start "Pushing all changes..."
    # -A = stage ALL changes (new + modified + deleted)
    git -C "$repo_dir" add -A 2>/dev/null

    local output
    output=$(git -C "$repo_dir" commit -m "$commit_msg" 2>&1)
    local commit_exit=$?

    if [[ $commit_exit -ne 0 ]]; then
        ui_spinner_stop
        if echo "$output" | grep -q "nothing to commit"; then
            ui_info "Nothing to commit — working tree is clean."
            return 0
        fi
        ui_error "Commit failed: ${output}"
        return 1
    fi

    output=$(git -C "$repo_dir" push 2>&1)
    local push_exit=$?

    # --- AUTO-UPSTREAM: Handle "no upstream branch" ---
    if [[ $push_exit -ne 0 ]] && echo "$output" | grep -q "no upstream branch"; then
        ui_warn "No upstream branch set. Configuring automatically..."
        local branch_name
        branch_name=$(config_get_current_branch "$repo_dir")
        [[ -z "$branch_name" ]] && branch_name=$(config_detect_branch "$repo_dir")
        
        ui_spinner_start "Setting upstream and pushing..."
        output=$(git -C "$repo_dir" push --set-upstream origin "$branch_name" 2>&1)
        push_exit=$?
        ui_spinner_stop
        
        if [[ $push_exit -eq 0 ]]; then
            ui_spinner_stop
            ui_success "Upstream configured and changes pushed!"
            return 0
        fi
    fi

    ui_spinner_stop

    # --- AUTO-SYNC: Handle "rejected because remote is ahead" ---
    # Same logic as core_push_no_delete — see detailed comments there.
    # When the remote has commits we don't have, we pull --rebase to
    # integrate them cleanly, then retry the push.
    if [[ $push_exit -ne 0 ]] && echo "$output" | grep -qE 'rejected|fetch first|non-fast-forward'; then
        ui_warn "Remote has newer commits. Syncing automatically..."
        echo >&2

        local branch_name
        branch_name=$(config_get_current_branch "$repo_dir")
        [[ -z "$branch_name" ]] && branch_name=$(config_detect_branch "$repo_dir")

        ui_spinner_start "Pulling remote changes (rebase)..."
        local pull_output
        pull_output=$(git -C "$repo_dir" pull --rebase origin "$branch_name" 2>&1)
        local pull_exit=$?
        ui_spinner_stop

        if [[ $pull_exit -ne 0 ]]; then
            git -C "$repo_dir" rebase --abort 2>/dev/null
            ui_error "Auto-sync failed — there are conflicts between your changes and the remote."
            echo -e "  ${C_DIM}${pull_output}${C_RESET}" >&2
            echo >&2
            ui_warn "To fix this manually:"
            echo -e "  ${C_DIM}1. cd ${repo_dir}${C_RESET}" >&2
            echo -e "  ${C_DIM}2. git pull --rebase origin ${branch_name}${C_RESET}" >&2
            echo -e "  ${C_DIM}3. Resolve conflicts, then: git rebase --continue${C_RESET}" >&2
            echo -e "  ${C_DIM}4. git push${C_RESET}" >&2
            return 1
        fi

        ui_success "Remote changes integrated successfully!"
        echo >&2

        ui_spinner_start "Retrying push..."
        output=$(git -C "$repo_dir" push 2>&1)
        push_exit=$?
        ui_spinner_stop

        if [[ $push_exit -ne 0 ]]; then
            ui_error "Push still failed after sync:"
            echo -e "  ${C_DIM}${output}${C_RESET}" >&2
            return 1
        fi

    elif [[ $push_exit -ne 0 ]]; then
        ui_error "Push failed:"
        echo -e "  ${C_DIM}${output}${C_RESET}" >&2
        return 1
    fi

    ui_success "All changes pushed successfully! (including deletions)"
}


# ==============================================================================
# FEATURE 4: Hard Reset to Remote
# ==============================================================================

# --- core_ensure_credentials ---
# Verify that stored Git credentials work for the active repository.
# If authentication fails (e.g., expired PAT), prompt the user for a new username and token,
# configure the global credential store, and save the new token.
core_ensure_credentials() {
    # Ensure the credential helper is configured so stored credentials are used
    config_setup_credential_store
    local repo_dir
    repo_dir=$(_get_active_repo)
    if [[ -z "$repo_dir" ]]; then
        ui_warn "No active repository set — skipping credential verification."
        return 0
    fi

    local remote_url
    remote_url=$(config_get_remote_url "$repo_dir")
    if [[ -z "$remote_url" ]]; then
        ui_warn "Active repo has no remote URL — skipping credential verification."
        return 0
    fi

    # Test authentication by attempting a lightweight remote query.
    if git -C "$repo_dir" ls-remote "$remote_url" > /dev/null 2>&1; then
        ui_success "Stored Git credentials are valid."
        # Record that this host is validated to avoid future prompts
        local host=$(echo "$remote_url" | sed 's|https://||' | sed 's|/.*||')
        echo "$host" >> "${REPO_CONFIG_DIR}/cred_validated"
        return 0
    fi

    ui_warn "Git authentication failed (token may be expired)."
    # Prompt for new credentials.
    local username
    username=$(ui_input "GitHub username")
    local pat
    pat=$(ui_password "GitHub PAT token")
    if [[ -z "$username" || -z "$pat" ]]; then
        ui_error "Username or token missing — cannot update credentials."
        return 1
    fi

    # Ensure credential helper is configured.
    config_setup_credential_store

    # Extract host from remote URL (e.g., github.com)
    local host
    host=$(echo "$remote_url" | sed 's|https://||' | sed 's|/.*||')
    # Append new credentials to the credential file.
    local cred_line="https://${username}:${pat}@${host}"
    # Remove any existing line for this host to avoid duplicates.
    grep -vF "@${host}" "$HOME/.git-credentials" 2>/dev/null > "$HOME/.git-credentials.tmp"
    mv "$HOME/.git-credentials.tmp" "$HOME/.git-credentials"
    echo "$cred_line" >> "$HOME/.git-credentials"
    chmod 600 "$HOME/.git-credentials"
    ui_success "Git credentials updated and saved."
    # Record validation
    echo "$host" >> "${REPO_CONFIG_DIR}/cred_validated"
}

# Fetches the latest state from remote and FORCE-RESETS local to match it.
# This is the nuclear option: ALL local changes are permanently discarded.
#
# git fetch origin  → downloads remote state WITHOUT merging
# git reset --hard origin/main → forces local to match remote exactly
#
# WHY fetch + reset INSTEAD OF pull?
#   'git pull' = fetch + merge. If you have conflicting local changes,
#   merge will fail or create merge commits.
#   'git reset --hard' bypasses merge entirely — it just overwrites.
#   This is exactly what you want when "my local repo is messed up,
#   give me the clean remote version."
#
# DANGER: This DESTROYS all uncommitted AND unpushed local changes!
core_hard_reset() {
    ui_header "🔄 Hard Reset to Remote"
    echo -e "  ${C_RED}${C_BOLD}⚠️  DANGER: This will DESTROY all local changes!${C_RESET}" >&2
    echo -e "  ${C_DIM}Your local repo will become an exact copy of the remote.${C_RESET}" >&2
    echo -e "  ${C_DIM}Uncommitted work, unpushed commits — all gone permanently.${C_RESET}" >&2
    echo >&2

    # --- Get the active repo (set once via Manage Repos) ---
    local repo_dir
    repo_dir=$(_get_active_repo)
    [[ $? -ne 0 || -z "$repo_dir" ]] && return 1

    # --- Detect branch ---
    local branch
    branch=$(config_detect_branch "$repo_dir")
    ui_info "Repository: ${C_CYAN}${repo_dir}${C_RESET}"
    ui_info "Will reset to: ${C_CYAN}origin/${branch}${C_RESET}"
    echo >&2

    # Show what will be lost
    local changes
    changes=$(git -C "$repo_dir" status --short 2>/dev/null)
    if [[ -n "$changes" ]]; then
        echo -e "  ${C_RED}${C_BOLD}Files that will be LOST:${C_RESET}" >&2
        echo "$changes" | head -20 | while read -r line; do
            echo -e "    ${C_RED}${line}${C_RESET}" >&2
        done
        echo >&2
    fi

    # --- Double confirmation (because this is destructive) ---
    if ! ui_confirm "Are you SURE you want to destroy all local changes?" "N"; then
        ui_warn "Reset cancelled."
        return 0
    fi
    # Second confirmation for extra safety
    if ! ui_confirm "This cannot be undone. Proceed?" "N"; then
        ui_warn "Reset cancelled."
        return 0
    fi

    # --- Fetch from remote ---
    ui_spinner_start "Fetching latest from remote..."
    local output
    output=$(git -C "$repo_dir" fetch origin 2>&1)
    local fetch_exit=$?
    ui_spinner_stop

    if [[ $fetch_exit -ne 0 ]]; then
        ui_error "Fetch failed:"
        echo -e "  ${C_DIM}${output}${C_RESET}" >&2
        return 1
    fi

    # --- Hard reset ---
    # --hard means: reset EVERYTHING (staging area + working directory)
    # origin/$branch = the state of the remote's branch
    output=$(git -C "$repo_dir" reset --hard "origin/${branch}" 2>&1)
    local reset_exit=$?

    if [[ $reset_exit -ne 0 ]]; then
        ui_error "Reset failed:"
        echo -e "  ${C_DIM}${output}${C_RESET}" >&2
        return 1
    fi

    ui_success "Repository reset to origin/${branch} successfully!"
    ui_info "Your local repo is now an exact copy of the remote."
}


# ==============================================================================
# FEATURE 5: Copy Content from Another Repo
# ==============================================================================

# --- core_copy_from_repo ---
# One-time import: copies ALL files from another repo into a local directory.
# Uses a temporary remote that is cleaned up after the copy.
#
# THE FLOW:
#   1. Add the source repo as a temporary remote
#   2. Fetch its contents (downloads but doesn't merge)
#   3. Checkout its files into the working directory
#   4. Remove the temporary remote (cleanup)
#
# WHY temp remote + fetch + checkout INSTEAD OF clone?
#   We don't want a full clone with its own .git history.
#   We just want the FILES, dropped into an existing directory.
#   The checkout command copies files without their history.
#
# The temp remote name uses $RANDOM (bash built-in) and epoch seconds
# to guarantee uniqueness even if called multiple times rapidly.
core_copy_from_repo() {
    ui_header "📋 Copy Content from Another Repo"
    ui_info "This copies files from a remote repo into a local directory."
    ui_info "The source repo is used once and then removed — no permanent link."
    echo >&2

    # --- Step 1: Ask for source repo URL ---
    local source_url
    source_url=$(ui_input "Source repo URL (to copy FROM)")
    [[ $? -ne 0 || -z "$source_url" ]] && return 1

    # --- Step 2: Ask for branch ---
    local source_branch
    source_branch=$(ui_input "Branch to copy from" "main")
    [[ $? -ne 0 ]] && source_branch="main"

    # --- Step 3: Ask for destination directory ---
    local dest_dir
    dest_dir=$(ui_pick_dir "Destination directory (to copy INTO)")
    [[ $? -ne 0 || -z "$dest_dir" ]] && return 1

    # --- Step 4: Check if destination is a git repo ---
    # If it's not, we need to init it (checkout requires a git repo)
    local was_git_repo=true
    if ! config_check_git_repo "$dest_dir"; then
        ui_warn "Destination is not a git repo. Initializing temporarily..."
        git -C "$dest_dir" init 2>/dev/null
        was_git_repo=false
    fi

    # --- Step 5: Generate unique temporary remote name ---
    # $EPOCHSECONDS is a bash 5+ built-in. We fall back to 'date +%s' for bash 4.
    # $RANDOM is a bash built-in that returns a random number 0-32767.
    local timestamp
    timestamp=$(date +%s)
    local temp_remote="temp_copy_${timestamp}_${RANDOM}"
    ui_info "Temporary remote name: ${C_DIM}${temp_remote}${C_RESET}"

    # --- Step 6: Add temporary remote ---
    git -C "$dest_dir" remote add "$temp_remote" "$source_url" 2>/dev/null
    if [[ $? -ne 0 ]]; then
        ui_error "Failed to add remote. Check the URL."
        return 1
    fi

    # --- Step 7: Fetch from the source repo ---
    ui_spinner_start "Fetching from source repository..."
    local output
    output=$(git -C "$dest_dir" fetch "$temp_remote" 2>&1)
    local fetch_exit=$?
    ui_spinner_stop

    if [[ $fetch_exit -ne 0 ]]; then
        ui_error "Fetch failed:"
        echo -e "  ${C_DIM}${output}${C_RESET}" >&2
        # Cleanup: remove the failed remote
        git -C "$dest_dir" remote remove "$temp_remote" 2>/dev/null
        return 1
    fi

    # --- Step 8: Checkout files from the source ---
    # 'git checkout <remote>/<branch> -- .' copies ALL files from that
    # branch into the current working directory.
    # The '--' separates the branch reference from the path.
    # The '.' means "everything in the root of the repo".
    ui_info "Copying files..."
    output=$(git -C "$dest_dir" checkout "${temp_remote}/${source_branch}" -- . 2>&1)
    local checkout_exit=$?

    if [[ $checkout_exit -ne 0 ]]; then
        ui_error "Checkout failed:"
        echo -e "  ${C_DIM}${output}${C_RESET}" >&2
        # Cleanup even on failure
        git -C "$dest_dir" remote remove "$temp_remote" 2>/dev/null
        return 1
    fi

    # --- Step 9: Remove temporary remote (cleanup) ---
    # We don't want a permanent link to the source repo.
    # 'remote remove' deletes the remote AND its tracking branches.
    git -C "$dest_dir" remote remove "$temp_remote" 2>/dev/null
    ui_info "Temporary remote removed (cleanup complete)"

    # If destination wasn't a git repo before, offer to remove .git
    if [[ "$was_git_repo" == false ]]; then
        if ui_confirm "Remove git tracking from destination? (keep just the files)" "Y"; then
            rm -rf "${dest_dir}/.git"
            ui_info "Git tracking removed — destination is now a plain directory"
        fi
    fi

    # --- Step 10: Show summary ---
    ui_divider
    ui_success "Files copied successfully!"
    ui_info "Source: ${C_DIM}${source_url} (${source_branch})${C_RESET}"
    ui_info "Destination: ${C_CYAN}${dest_dir}${C_RESET}"

    local file_count
    file_count=$(find "$dest_dir" -not -path '*/.git/*' -type f | wc -l)
    ui_info "Total files in destination: ${C_CYAN}${file_count}${C_RESET}"
}
