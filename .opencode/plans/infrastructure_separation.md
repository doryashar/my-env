# Infrastructure vs User Content Separation Plan

## Problem Statement

Currently, the env repository mixes:
1. **Infrastructure code** - Setup scripts, sync scripts, helper functions (should be updated from upstream)
2. **User configuration** - Personal configs, dotfiles, aliases (should be in user's fork)

This makes it difficult for users to:
- Fork the repo and customize it without conflicts
- Update infrastructure scripts without losing their changes
- Keep their personal data separate from the framework

---

## Current Structure

```
env/
├── config/              # User configuration (repo.conf, dotfiles.conf)
├── dotfiles/            # User dotfiles (.zshrc, .env.zsh, etc.)
├── functions/           # Mixed - some infrastructure, some user-specific
├── scripts/             # Infrastructure (setup.sh, sync_*.sh)
├── private/             # User private data (secrets, encrypted)
├── aliases              # User aliases
├── env_vars             # User environment variables
└── .env_installed       # Marker file
```

---

## Proposed Structure

```
env/
├── .upstream/                    # Infrastructure (git subtree from upstream)
│   ├── scripts/
│   │   ├── setup.sh
│   │   ├── sync_env.sh
│   │   ├── sync_dotfiles.sh
│   │   ├── sync_encrypted.sh
│   │   ├── install_docker.sh
│   │   └── install_fonts.sh
│   └── functions/
│       ├── common_funcs
│       └── helpers
│
├── config/                       # User configuration
│   ├── repo.conf                 # User's fork URL, private repo URL
│   ├── dotfiles.conf
│   └── crontab
│
├── dotfiles/                     # User dotfiles
├── functions/                    # User-specific functions (custom)
├── private/                      # User private data
├── aliases                       # User aliases
├── env_vars                      # User environment variables
│
├── scripts/                      # Symlinks to .upstream/scripts/*
│   └── update.sh                 # Pulls latest from upstream
│
└── README.md                     # User's readme (not from upstream)
```

---

## Implementation Plan

### Phase 1: Remove Hardcoded URLs (Immediate)

**Files to modify:**
1. `scripts/setup.sh`
   - Use `DEFAULT_REPO_URL` variable at top
   - Support `ENV_URL` environment variable for custom forks
   - Auto-detect from `git remote get-url origin` when in repo

2. `config/repo.conf`
   - Add `UPSTREAM_URL` for infrastructure updates
   - Add `REPO_URL` (auto-detected, user's fork)
   - Keep `PRIVATE_URL` for encrypted repo

**New curl command:**
```bash
# Default (your repo)
curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/setup.sh | bash

# Custom fork
curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/setup.sh | ENV_URL=https://github.com/user/my-env bash
```

### Phase 2: Create update_infrastructure.sh

**New script:** `scripts/update_infrastructure.sh`

```bash
#!/bin/bash
# Updates infrastructure scripts from upstream repository

UPSTREAM_URL="${UPSTREAM_URL:-git@github.com:doryashar/my-env.git}"
INFRA_FILES=(
    "scripts/setup.sh"
    "scripts/sync_env.sh"
    "scripts/sync_dotfiles.sh"
    "scripts/sync_encrypted.sh"
    "scripts/install_docker.sh"
    "scripts/install_fonts.sh"
    "functions/common_funcs"
    "functions/helpers"
)

# Fetch latest from upstream without merging
git fetch "$UPSTREAM_URL" master:upstream-master

# Copy specific files
for file in "${INFRA_FILES[@]}"; do
    git show "upstream-master:$file" > "$file"
done

echo "Infrastructure updated from upstream"
```

### Phase 3: Documentation

**Update README.md:**

1. **Installation section:**
   - Default: `curl ... | bash` (uses your repo)
   - Fork: `curl ... | ENV_URL=... bash`

2. **Customization section:**
   - Fork the repo
   - Update `config/repo.conf` with your settings
   - Modify `dotfiles/`, `aliases`, `env_vars`
   - Keep `UPSTREAM_URL` pointing to original for updates

3. **Updates section:**
   - Run `scripts/update_infrastructure.sh` to get latest scripts
   - User configs are never overwritten

---

## Classification of Files

### Infrastructure (update from upstream)
- `scripts/setup.sh`
- `scripts/sync_env.sh`
- `scripts/sync_dotfiles.sh`
- `scripts/sync_encrypted.sh`
- `scripts/install_docker.sh`
- `scripts/install_fonts.sh`
- `scripts/update_infrastructure.sh`
- `functions/common_funcs`
- `functions/helpers`

### User Configuration (never overwritten)
- `config/repo.conf`
- `config/dotfiles.conf`
- `config/crontab`
- `dotfiles/*`
- `aliases`
- `env_vars`
- `private/*`
- `functions/bw_funcs` (user-specific)
- `functions/monitors` (user-specific)
- `functions/pingme` (user-specific)
- `functions/compression_funcs` (user-specific)
- `functions/file_chat_funcs` (user-specific)
- `functions/git_funcs` (user-specific)
- `functions/virtualenv.sh` (user-specific)

---

## Alternative: Template Repository

Instead of upstream/fork model, use GitHub's "Template Repository" feature:

1. Mark `doryashar/my-env` as a template
2. Users click "Use this template" to create their own repo
3. Their repo is 100% independent
4. They manually copy updated scripts when needed

**Pros:**
- Simpler model
- No merge conflicts
- User has full control

**Cons:**
- No automatic infrastructure updates
- Manual effort to get new features

---

## Decision Points

1. **Which model?**
   - [ ] Upstream/Fork (with `update_infrastructure.sh`)
   - [ ] Template Repository (fully independent)

2. **Should `update_infrastructure.sh` be automatic?**
   - [ ] Yes, prompt during `sync_env.sh --sync` when updates available
   - [ ] No, manual only via `scripts/update_infrastructure.sh`

3. **Default curl URL?**
   - [ ] Point to `doryashar/my-env` (easy onboarding)
   - [ ] Require `ENV_URL` always (explicit)

4. **How to handle `functions/` directory?**
   - [ ] Split into `functions/infrastructure/` and `functions/user/`
   - [ ] Keep flat, only update `common_funcs` and `helpers`

---

## Immediate Actions

1. [x] Fix `BASH_SOURCE[0]` error when running via curl
2. [x] Remove all hardcoded URLs from scripts
3. [x] Add `UPSTREAM_URL` and `REPO_URL` to config
4. [x] Create `scripts/update_infrastructure.sh`
5. [x] Update README.md with installation options
6. [ ] Test fork workflow (needs user verification)

---

## Completed (2026-03-13)

**Commits:**
- `8cb488f` - Fix curl install and add configurable repo URL
- `b21526b` - Add update_infrastructure.sh for fork users
- `7689ed8` - Update README with curl install and fork instructions

**Changes Made:**
- `scripts/setup.sh`: Fixed `${BASH_SOURCE[0]:-}` for curl compatibility, added `ENV_URL` support
- `scripts/update_infrastructure.sh`: New script for pulling upstream updates
- `config/repo.conf`: Added `UPSTREAM_URL`
- `README.md`: Added one-liner install, fork instructions, removed `prerun.sh` references

**Installation now works via:**
```bash
curl -fsSL https://raw.githubusercontent.com/doryashar/my-env/master/scripts/setup.sh | bash
```
