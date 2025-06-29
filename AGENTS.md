
## Build, Lint, and Test Commands

- **Build:** There is no formal build process. The main script is `setup.sh`.
- **Lint:** There is no linter configured.
- **Test:** There is no testing framework. To test changes, run the modified scripts in a controlled environment.

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
  - Check for the existence of commands and directories before using them.
- **Comments:**
  - Use comments to explain the purpose of complex commands or functions.
