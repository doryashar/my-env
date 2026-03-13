# Lessons Learned

## Session: 2026-03-13 - Infrastructure Separation

### Pattern: BASH_SOURCE with set -u
**Problem:** `${BASH_SOURCE[0]}` fails with `set -u` when script is piped via curl.

**Solution:** Use `${BASH_SOURCE[0]:-}` with default value:
```bash
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    # Running from file
else
    # Running via curl (piped)
fi
```

**Rule:** Always use `${BASH_SOURCE[0]:-}` instead of `${BASH_SOURCE[0]}` when `set -u` is enabled.

---

### Pattern: Arithmetic with set -e
**Problem:** `((VAR++))` fails with `set -e` when variable is 0 because exit code is 1.

**Solution:** Use `$((VAR + 1))`:
```bash
# Wrong - exits script when COUNT is 0
((COUNT++))

# Correct
COUNT=$((COUNT + 1))
```

**Rule:** Never use `((VAR++))` or `((++VAR))` with `set -e`. Always use `VAR=$((VAR + 1))`.

---

### Pattern: local keyword scope
**Problem:** Using `local` at top-level silently fails or causes issues.

**Solution:** Only use `local` inside functions:
```bash
# Wrong - local outside function
local MY_VAR="value"

# Correct - either in function or without local
MY_VAR="value"
# Or in function:
my_func() {
    local MY_VAR="value"
}
```

**Rule:** `local` keyword only works inside functions. Never use at top-level.

---

### Pattern: Race conditions with background processes
**Problem:** When spawning background process to update file, main shell checking immediately may fail.

**Solution:** Add small delay or check for file existence before reading:
```bash
# Spawn background update
(update_file "$TARGET" &)

# Don't check immediately - either:
sleep 0.1  # Add small delay
# Or check existence first:
[[ -f "$TARGET" ]] && cat "$TARGET"
```

**Rule:** When using background processes to write files, don't read immediately in foreground.

---

### Pattern: Repository URL naming
**Problem:** Inconsistent naming between `my_env` (underscore) and `my-env` (hyphen).

**Solution:** Always use consistent naming. GitHub repo is `my-env` (hyphen).

**Rule:** Use `my-env` consistently. Update any `my_env` references.
