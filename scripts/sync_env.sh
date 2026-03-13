#!/bin/bash
set -euo pipefail

#########################################################################
# ENV Synchronization Script
#
# Orchestrates all syncing operations for the environment.
#
# Features:
# - Git push/pull for main repo
# - Dotfiles synchronization
# - Encrypted files synchronization
# - Timestamp tracking for last check/sync
# - Silent mode for background checks
# - Configurable conflict resolution
#########################################################################

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ENV_DIR=$(dirname "$SCRIPT_DIR")
REPO_CONFIG_FILE="$ENV_DIR/config/repo.conf"
DOTFILES_CONFIG_FILE="$ENV_DIR/config/dotfiles.conf"

source "$ENV_DIR/functions/common_funcs"

ENV_DIR=$(expand_path "$ENV_DIR")
DEBUG="${ENV_DEBUG:-}"

source "$REPO_CONFIG_FILE" 2>/dev/null || true

# Default conflict strategy if not set in config
DEFAULT_CONFLICT_STRATEGY="${DEFAULT_CONFLICT_STRATEGY:-ask}"

#########################################################################
# Status Codes
#########################################################################
STATUS_NO_UPDATES=0
STATUS_REMOTE_UPDATES=1
STATUS_LOCAL_CHANGES=2
STATUS_BOTH_CHANGES=3

#########################################################################
# Timestamp Management
#########################################################################

update_last_check() {
    mkdir -p "$ENV_DIR/tmp"
    touch "$ENV_DIR/tmp/last_check"
    debug "Updated last_check timestamp"
}

update_last_sync() {
    mkdir -p "$ENV_DIR/tmp"
    touch "$ENV_DIR/tmp/last_sync"
    debug "Updated last_sync timestamp"
}

#########################################################################
# Git Functions
#########################################################################

git_has_uncommitted_changes() {
    cd "$ENV_DIR" || return 1
    [[ -n "$(git status --porcelain)" ]]
}

git_has_remote_updates() {
    cd "$ENV_DIR" || return 1
    
    if [[ -z "${REMOTE_URL:-}" ]]; then
        return 1
    fi
    
    git remote | grep -q origin || git remote add origin "$REMOTE_URL"
    
    if ! git fetch --quiet 2>/dev/null; then
        return 1
    fi
    
    local local_rev
    local remote_rev
    local_rev=$(git rev-parse HEAD 2>/dev/null || echo "none")
    remote_rev=$(git rev-parse @{upstream} 2>/dev/null || echo "none")
    
    [[ "$local_rev" != "$remote_rev" ]] && [[ "$remote_rev" != "none" ]]
}

git_commit_changes() {
    cd "$ENV_DIR" || return 1
    
    if [[ -n "$(git status --porcelain)" ]]; then
        info "Committing local changes..."
        git submodule foreach 'git add . && git commit -m "Auto-sync submodule $(date "+%Y-%m-%d %H:%M:%S")"' 2>/dev/null || true
        git add .
        git commit -m "Auto-sync dotfiles $(date '+%Y-%m-%d %H:%M:%S')"
    fi
}

git_pull() {
    cd "$ENV_DIR" || return 1
    
    if [[ -z "${REMOTE_URL:-}" ]]; then
        debug "No remote URL configured, skipping pull"
        return 0
    fi
    
    git remote | grep -q origin || git remote add origin "$REMOTE_URL"
    
    if ! git fetch --quiet 2>/dev/null; then
        warning "Failed to fetch from remote"
        return 1
    fi
    
    if git status | grep -q "behind"; then
        case "$DEFAULT_CONFLICT_STRATEGY" in
            "remote")
                debug "Auto-pulling (strategy: remote)"
                if ! git pull --ff-only origin master 2>/dev/null; then
                    info "Fast-forward failed, trying merge..."
                    if ! git pull origin master; then
                        warning "Merge conflict detected"
                        resolve_merge_conflict
                    fi
                fi
                ;;
            "local")
                debug "Skipping pull (strategy: local)"
                ;;
            "ask")
                if prompt_yn "Remote updates available. Pull? (y/n) "; then
                    if ! git pull --ff-only origin master 2>/dev/null; then
                        warning "Could not fast-forward merge. Trying auto-merge..."
                        if ! git pull origin master; then
                            error "Merge conflict detected."
                            resolve_merge_conflict
                        fi
                    fi
                fi
                ;;
            "rename")
                debug "Backing up and pulling (strategy: rename)"
                local backup_branch="backup-$(date +%Y%m%d%H%M%S)"
                git branch "$backup_branch"
                info "Created backup branch: $backup_branch"
                git pull --ff-only origin master 2>/dev/null || git reset --hard origin/master
                ;;
            "ignore")
                debug "Ignoring remote updates (strategy: ignore)"
                ;;
            *)
                debug "Unknown strategy: $DEFAULT_CONFLICT_STRATEGY, asking..."
                prompt_yn "Remote updates available. Pull? (y/n) " && git pull origin master
                ;;
        esac
    fi
}

git_push() {
    cd "$ENV_DIR" || return 1
    
    if [[ -z "${REMOTE_URL:-}" ]]; then
        debug "No remote URL configured, skipping push"
        return 0
    fi
    
    git remote | grep -q origin || git remote add origin "$REMOTE_URL"
    
    if [[ -n "$(git cherry -v 2>/dev/null)" ]]; then
        case "$DEFAULT_CONFLICT_STRATEGY" in
            "remote"|"local")
                debug "Auto-pushing (strategy: $DEFAULT_CONFLICT_STRATEGY)"
                git push origin master 2>/dev/null || warning "Failed to push changes"
                ;;
            "ask")
                if prompt_yn "Local changes detected. Push? (y/n) "; then
                    debug "Pushing changes to git"
                    git push origin master 2>/dev/null || warning "Failed to push changes"
                fi
                ;;
            *)
                prompt_yn "Local changes detected. Push? (y/n) " && git push origin master 2>/dev/null
                ;;
        esac
    fi
}

resolve_merge_conflict() {
    case "$DEFAULT_CONFLICT_STRATEGY" in
        "ask")
            warning "Git conflicts detected. Choose resolution:"
            echo "1) Manual resolution"
            echo "2) Keep local changes"
            echo "3) Use remote changes"
            echo "4) Abort merge"
            prompt "Enter choice [1-4]: " choice
            case "$choice" in
                1) git mergetool ;;
                2) git reset --hard HEAD ;;
                3) git reset --hard origin/master ;;
                4) git merge --abort ;;
                *) git merge --abort ;;
            esac
            ;;
        "local")
            git reset --hard HEAD
            ;;
        "remote")
            git reset --hard origin/master
            ;;
        "rename")
            git merge --abort
            local backup_branch="backup-$(date +%Y%m%d%H%M%S)"
            git branch "$backup_branch"
            info "Created backup branch: $backup_branch"
            git reset --hard origin/master
            ;;
        "ignore")
            git merge --abort
            ;;
        *)
            git merge --abort
            ;;
    esac
}

#########################################################################
# Check Functions
#########################################################################

check_updates() {
    local has_local=0
    local has_remote=0
    
    cd "$ENV_DIR" || return $STATUS_BOTH_CHANGES
    
    if git_has_uncommitted_changes; then
        has_local=1
    fi
    
    if git_has_remote_updates; then
        has_remote=1
    fi
    
    if [[ $has_local -eq 1 ]] && [[ $has_remote -eq 1 ]]; then
        return $STATUS_BOTH_CHANGES
    elif [[ $has_local -eq 1 ]]; then
        return $STATUS_LOCAL_CHANGES
    elif [[ $has_remote -eq 1 ]]; then
        return $STATUS_REMOTE_UPDATES
    else
        return $STATUS_NO_UPDATES
    fi
}

#########################################################################
# Help
#########################################################################

show_help() {
    cat <<EOF
Usage: $0 [options]

Options:
  -c, --check-only    Check for updates silently, return status code
  -s, --sync          Full sync (pull + push + dotfiles + encrypted)
  -f, --force         Force sync even if recently synced
  -d, --dotfiles      Sync dotfiles only
  -e, --encrypted     Sync encrypted files only
  -p, --push          Push to remote
  -l, --pull          Pull from remote
  -h, --help          Show this help message

Status Codes (for --check-only):
  0 = No updates
  1 = Remote updates available
  2 = Uncommitted local changes
  3 = Both remote and local changes
EOF
}

#########################################################################
# Main
#########################################################################

main() {
    local perform_check_only=0
    local perform_sync=0
    local perform_force=0
    local perform_dotfiles=0
    local perform_encrypted=0
    local perform_push=0
    local perform_pull=0
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--check-only|-u|--check-updates)
                perform_check_only=1
                shift
                ;;
            -s|--sync)
                perform_sync=1
                shift
                ;;
            -f|--force)
                perform_force=1
                shift
                ;;
            -d|--dotfiles|--dotfiles_sync)
                perform_dotfiles=1
                shift
                ;;
            -e|--encrypted|--encrypted_sync)
                perform_encrypted=1
                shift
                ;;
            -p|--push)
                perform_push=1
                shift
                ;;
            -l|--pull)
                perform_pull=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -i|--init)
                warning "Init option deprecated, use setup.sh instead"
                shift
                ;;
            -r|--repo)
                shift 2
                ;;
            --config)
                shift 2
                ;;
            *)
                warning "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    if [[ $perform_check_only -eq 1 ]]; then
        local status=0
        check_updates || status=$?
        update_last_check
        exit $status
    fi
    
    if [[ $perform_sync -eq 1 ]]; then
        perform_pull=1
        perform_push=1
        perform_dotfiles=1
        perform_encrypted=1
    fi
    
    if [[ $perform_pull -eq 1 ]]; then
        git_commit_changes
        git_pull
    fi
    
    if [[ $perform_dotfiles -eq 1 ]]; then
        if [[ -f "$ENV_DIR/scripts/sync_dotfiles.sh" ]]; then
            bash "$ENV_DIR/scripts/sync_dotfiles.sh" "$DOTFILES_CONFIG_FILE"
        else
            warning "sync_dotfiles.sh not found"
        fi
    fi
    
    if [[ $perform_encrypted -eq 1 ]]; then
        if [[ -f "$ENV_DIR/scripts/sync_encrypted.sh" ]]; then
            bash "$ENV_DIR/scripts/sync_encrypted.sh"
        else
            warning "sync_encrypted.sh not found"
        fi
    fi
    
    if [[ $perform_push -eq 1 ]]; then
        git_commit_changes
        git_push
    fi
    
    if [[ $perform_sync -eq 1 ]] || [[ $perform_pull -eq 1 ]] || [[ $perform_push -eq 1 ]]; then
        update_last_sync
    fi
    
    debug "Finished!"
}

main "$@"
