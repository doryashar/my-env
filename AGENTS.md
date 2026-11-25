
## Build, Lint, and Test Commands

- **Build:** There is no formal build process. The main script is
  `scripts/install/setup.sh`.
- **Lint:** There is no linter configured.
- **Test:** Run `bash tests/run_all_tests.sh --skip-docker` from the
  repo root (about a minute). The Docker suite (`--only docker`) needs
  Docker and network access and takes about three minutes. One suite:
  `--only <name>`. New suites are registered by hand in six places in
  `tests/run_all_tests.sh`; `tests/runner_wiring_test.sh` checks that
  wiring. Never run `setup.sh` or anything under `tests/docker/` outside
  the container: `setup.sh` installs packages, and `sudo` asks for no
  password on this machine.

## Directory Structure

- `scripts/install/` — One-time installation scripts (setup, docker,
  fonts, packages)
- `scripts/sync/` — Ongoing sync/maintenance (sync_env, sync_dotfiles,
  sync_encrypted, update_infrastructure)
- `scripts/tools/` — Personal utility scripts (camera, TTS, etc.)
- `bin/` — Not in git. Downloaded tools plus symlinks to the authored
  ones; `scripts/install/install_binaries.sh` fills it from
  `config/binaries.tsv`. Authored tools live in `scripts/tools/`.
- `var/` — Gitignored state: decrypted secrets (`private/`), the
  encrypted clone (`private_encrypted/`), change hashes. `tmp/` holds
  only caches, locks and alert markers.
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
- **Live Files:** Timers, services and the files every new shell
  sources are replaced atomically (write next to the target, then
  rename); they are never edited in place. Tests use temporary
  directories and stubs, never the real mounts, logs, vault or
  network.
- **Logging:** `info`, `log_debug`, `warning`, `error`, `title` live in
  `functions/logging.sh`. The debug logger is `log_debug`, not `debug`:
  `debug` is a builtin in bash 5.3 and in the shell omp runs commands
  with, and a function of that name is ignored there.
