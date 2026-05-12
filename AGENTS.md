
## Build, Lint, and Test Commands

- **Build:** There is no formal build process. The main script is
  `scripts/install/setup.sh`.
- **Lint:** There is no linter configured.
- **Test:** Run `bash tests/run_all_tests.sh` from the repo root.
  Individual tests can be run with `bash tests/<test_name>.sh`.
  Tests use a shared framework in `tests/test_helper.sh`.

## Directory Structure

- `scripts/install/` — One-time installation scripts (setup, docker,
  fonts, packages)
- `scripts/sync/` — Ongoing sync/maintenance (sync_env, sync_dotfiles,
  sync_encrypted, update_infrastructure)
- `scripts/tools/` — Personal utility scripts (camera, TTS, etc.)
- `bin/` — Binary executables
- `functions/` — Shared shell function libraries
- `config/` — Configuration files
- `tests/` — Test suite
- Backward-compat symlinks exist at old paths (e.g., `scripts/setup.sh`
  -> `install/setup.sh`)

## Code Style Guidelines

- **Language:** The primary language is shell (Bash).
- **Formatting:**
  - Use 2 spaces for indentation.
  - Keep lines under 80 characters.
- **Naming Conventions:**
  - Variables: `UPPER_CASE_WITH_UNDERSCORES`
  - Functions: `lower_case_with_underscores()`
- **Error Handling:**
  - Use `set -e` at the beginning of scripts to exit on error.
  - Check for the existence of commands and directories before using
    them.
- **Comments:**
  - Use comments to explain the purpose of complex commands or
    functions.
- **Shared Functions:**
  - Logging functions live in `functions/logging.sh`.
  - Common utilities (command_exists, prompts, GitHub auth) are in
    `functions/common_funcs`.
  - `scripts/install/setup.sh` is self-contained (runs via curl
    pre-clone) and maintains its own copies of these functions.
