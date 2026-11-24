# Monitor-Switch Hotplug Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `monitor-switch` remembers the last profile it applied and re-applies it automatically when a display is disconnected/reconnected.

**Architecture:** `bin/monitor-switch` writes the last successfully applied profile (`profile1` | `profile2` | `custom:CONN...`) to a state file after every apply, and gains a `restore` subcommand that waits (poll) for the expected connectors, then re-applies the profile with whatever subset is available. A udev rule on DRM hotplug events starts a systemd user oneshot service that runs `monitor-switch restore`. Configs applied by the script use Mutter D-Bus method 1 (temporary) and are therefore not in GNOME's `monitors.xml`; the state file is the only persistence.

**Tech Stack:** bash, Mutter DisplayConfig D-Bus (via existing `monitor_switch_gnome.py` helper), systemd user units, udev rules. Tests: repo bash suite framework (`tests/test_helper.sh`).

---

### Task 1: Test suite (RED)

**Files:**
- Create: `tests/test_monitor_switch_restore.sh`
- Modify: `tests/run_all_tests.sh` (register suite: help line, arg-parse alternation L102, flag var, `all)` branch, per-name case, dispatch block)

- [ ] **Step 1: Write `tests/test_monitor_switch_restore.sh`**

```bash
#!/bin/bash

#########################################################################
# Tests for monitor-switch state persistence + restore subcommand
# Stubs the python helper and gsettings; no DBus/GNOME required.
#########################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

MS="$SCRIPT_DIR/../bin/monitor-switch"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export MONITOR_SWITCH_STATE="$TEST_DIR/state/last-profile"
export MONITOR_SWITCH_RESTORE_WAIT=0
export MONITOR_SWITCH_HELPER="$TEST_DIR/helper.sh"
export HELPER_LOG="$TEST_DIR/helper.log"

export HWP_CONN=DP-1
export DEL_CONN=DP-2
export LEN_CONN=DP-3
export ACTIVE_MONS=""
export AVAILABLE_MONS=""

mkdir -p "$TEST_DIR/state" "$TEST_DIR/bin"

# Stub python helper: canned resolve/get-active/get-available answers
# driven by env vars; every invocation logged to $HELPER_LOG.
cat > "$MONITOR_SWITCH_HELPER" <<'EOF'
#!/bin/bash
cmd="$1"; shift
echo "$cmd $*" >> "$HELPER_LOG"
case "$cmd" in
  resolve)
    echo "HWP $HWP_CONN 1920"
    echo "DEL $DEL_CONN 1920"
    echo "LEN $LEN_CONN 5120"
    ;;
  get-active) printf '%s\n' $ACTIVE_MONS ;;
  get-available) printf '%s\n' $AVAILABLE_MONS ;;
  *) exit 0 ;;
esac
exit 0
EOF
chmod +x "$MONITOR_SWITCH_HELPER"

# Stub gsettings (ensure_keybinding must not touch real dconf)
printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/bin/gsettings"
chmod +x "$TEST_DIR/bin/gsettings"
export PATH="$TEST_DIR/bin:$PATH"

run_ms() {
  bash "$MS" "$@"
}

helper_log() { cat "$HELPER_LOG" 2>/dev/null; }

reset_log() { : > "$HELPER_LOG"; }

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="${3:-String should not contain substring}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo -e "${GREEN}✓${NC} $message"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}✗${NC} $message"
    echo "  Found: $needle"
    echo "  In: $haystack"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
}

assert_no_profile_applied() {
  local message="${1:-No profile should be applied}"
  if grep -q '^profile' "$HELPER_LOG" 2>/dev/null; then
    echo -e "${RED}✗${NC} $message"
    echo "  Unexpected profile call: $(grep '^profile' "$HELPER_LOG")"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    echo -e "${GREEN}✓${NC} $message"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
}

# --- Test 1: toggle from profile1 applies profile2 and saves state ------
export ACTIVE_MONS="DP-1 DP-2"
export AVAILABLE_MONS="DP-1 DP-2 DP-3"
reset_log
out=$(run_ms toggle); rc=$?
assert_exit_code 0 "$rc" "toggle from profile1 exits 0"
assert_contains "$out" "Switching to Profile 2" "toggle switches to profile 2"
assert_equals "profile2" "$(cat "$MONITOR_SWITCH_STATE" 2>/dev/null)" \
  "toggle saves 'profile2' to state file"
assert_contains "$(helper_log)" \
  "profile --primary DP-3 --pos DP-3 0 DP-3" \
  "helper applies LEN-only profile"

# --- Test 2: toggle back from profile2 applies profile1 and saves state --
export ACTIVE_MONS="DP-3"
reset_log
out=$(run_ms toggle); rc=$?
assert_exit_code 0 "$rc" "toggle from profile2 exits 0"
assert_equals "profile1" "$(cat "$MONITOR_SWITCH_STATE" 2>/dev/null)" \
  "toggle saves 'profile1' to state file"
assert_contains "$(helper_log)" \
  "profile --primary DP-1 --pos DP-1 0 --pos DP-2 1920 DP-1 DP-2" \
  "helper applies HP+DEL profile"

# --- Test 3: restore re-applies saved profile1 when all monitors present -
printf 'profile1\n' > "$MONITOR_SWITCH_STATE"
export AVAILABLE_MONS="DP-1 DP-2 DP-3"
reset_log
out=$(run_ms restore); rc=$?
assert_exit_code 0 "$rc" "restore exits 0"
assert_contains "$(helper_log)" \
  "profile --primary DP-1 --pos DP-1 0 --pos DP-2 1920 DP-1 DP-2" \
  "restore re-applies saved profile1"
assert_equals "profile1" "$(cat "$MONITOR_SWITCH_STATE")" \
  "restore keeps state as profile1"

# --- Test 4: restore applies available subset when a monitor is missing --
printf 'profile1\n' > "$MONITOR_SWITCH_STATE"
export AVAILABLE_MONS="DP-1"
reset_log
out=$(run_ms restore); rc=$?
assert_exit_code 0 "$rc" "restore with missing monitor exits 0"
assert_contains "$(helper_log)" "profile --primary DP-1 --pos DP-1 0 DP-1" \
  "restore applies HP-only subset"

# --- Test 5: restore does nothing when profile monitors are absent -------
printf 'profile2\n' > "$MONITOR_SWITCH_STATE"
export AVAILABLE_MONS="DP-1 DP-2"
reset_log
out=$(run_ms restore); rc=$?
assert_exit_code 0 "$rc" "restore with no expected monitors exits 0"
assert_no_profile_applied "restore with LEN absent applies nothing"

# --- Test 6: restore without state file is a quiet no-op -----------------
rm -f "$MONITOR_SWITCH_STATE"
reset_log
out=$(run_ms restore); rc=$?
assert_exit_code 0 "$rc" "restore without state file exits 0"
assert_contains "$out" "No saved profile" "restore reports no saved profile"
assert_no_profile_applied "restore without state applies nothing"

# --- Test 7: custom enable saves and restores connector list -------------
export AVAILABLE_MONS="DP-1 DP-3"
reset_log
out=$(run_ms enable DP-1 DP-3); rc=$?
assert_exit_code 0 "$rc" "enable custom set exits 0"
assert_equals "custom:DP-1 DP-3" "$(cat "$MONITOR_SWITCH_STATE")" \
  "enable saves 'custom:DP-1 DP-3' to state file"
reset_log
out=$(run_ms restore); rc=$?
assert_exit_code 0 "$rc" "restore of custom set exits 0"
assert_contains "$(helper_log)" "profile DP-1 DP-3" \
  "restore re-applies custom set"

# --- Test 8: custom restore is all-or-nothing ----------------------------
export AVAILABLE_MONS="DP-1"
reset_log
out=$(run_ms restore); rc=$?
assert_exit_code 0 "$rc" "custom restore with missing monitor exits 0"
assert_no_profile_applied "custom restore applies nothing when incomplete"

# --- Test 9: restore skips keybinding registration -----------------------
printf 'profile1\n' > "$MONITOR_SWITCH_STATE"
export AVAILABLE_MONS="DP-1 DP-2"
reset_log
out=$(run_ms restore); rc=$?
assert_not_contains "$out" "Keybinding registered" \
  "restore does not touch gsettings keybinding"

print_test_summary
```

- [ ] **Step 2: Register in `tests/run_all_tests.sh`** — help line after `monitor_switch`, add `monitor_switch_restore` to: arg-parse alternation (L102), `run_monitor_switch_restore=0` flag, `all)` branch, per-name case, dispatch block after monitor_switch:

```bash
if [[ $run_monitor_switch_restore -eq 1 ]]; then
    suite_counter=$((suite_counter + 1))
    run_test_suite "Monitor Switch Restore" "$SCRIPT_DIR/test_monitor_switch_restore.sh" "$suite_counter"
fi
```

- [ ] **Step 3: Run and verify RED**

Run: `bash tests/test_monitor_switch_restore.sh`
Expected: FAILURES — toggle does not write state file; `restore` prints "Unknown command: restore".

### Task 2: Implement state + restore (GREEN)

**Files:**
- Modify: `bin/monitor-switch`

- [ ] **Step 1: Make helper/state paths overridable + add state vars** (top of file, after L6)

```bash
PYTHON_HELPER="${MONITOR_SWITCH_HELPER:-$HOME/.local/bin/monitor-switch-gnome.py}"

# Last-applied profile (profile1|profile2|custom:CONN...), persisted so
# `restore` can re-assert it after display hotplug events.
STATE_FILE="${MONITOR_SWITCH_STATE:-$HOME/.local/state/monitor-switch/last-profile}"
# Seconds to wait for expected monitors to (re)appear before restoring
# with whatever subset is available. 0 = apply immediately.
RESTORE_WAIT="${MONITOR_SWITCH_RESTORE_WAIT:-5}"
```

- [ ] **Step 2: Add state + wait helpers** (before `toggle_profiles`)

```bash
save_state() {
  mkdir -p "$(dirname "$STATE_FILE")"
  printf '%s\n' "$1" > "$STATE_FILE"
}

read_state() {
  [ -r "$STATE_FILE" ] || return 1
  cat "$STATE_FILE"
}

# Wait up to RESTORE_WAIT seconds for all expected connectors to become
# available. Returns 0 if all appeared, 1 on timeout.
wait_for_connectors() {
  local expected=("$@")
  local deadline=$((SECONDS + RESTORE_WAIT))
  while [ "$SECONDS" -lt "$deadline" ]; do
    local available=($(get_available_monitors))
    local all_present=true
    local conn
    for conn in "${expected[@]}"; do
      if [[ " ${available[*]} " != *" $conn "* ]]; then
        all_present=false
        break
      fi
    done
    [ "$all_present" = true ] && return 0
    sleep 0.5
  done
  return 1
}

# Re-apply the last saved profile (invoked on display hotplug).
# Profiles restore with their available subset; custom sets are
# all-or-nothing.
restore_profile() {
  local state
  if ! state=$(read_state); then
    echo "No saved profile to restore"
    return 0
  fi

  local expected=()
  if [ "$state" = "profile1" ] || [ "$state" = "profile2" ]; then
    local vendors=()
    if [ "$state" = "profile1" ]; then
      vendors=("${PROFILE1_VENDORS[@]}")
    else
      vendors=("${PROFILE2_VENDORS[@]}")
    fi
    local vid conn
    for vid in "${vendors[@]}"; do
      conn=$(resolve_connector "$vid")
      [ -n "$conn" ] && [ "$conn" != "-" ] && expected+=("$conn")
    done
  elif [[ "$state" == custom:* ]]; then
    read -ra expected <<< "${state#custom:}"
  else
    echo "Unknown saved state: $state"
    return 0
  fi

  wait_for_connectors "${expected[@]}"

  local available=($(get_available_monitors))
  local candidates=()
  local conn
  for conn in "${expected[@]}"; do
    [[ " ${available[*]} " == *" $conn "* ]] && candidates+=("$conn")
  done
  if [ ${#candidates[@]} -eq 0 ]; then
    echo "Restore: no expected monitors available, nothing to do"
    return 0
  fi
  if [[ "$state" == custom:* ]] && [ ${#candidates[@]} -ne ${#expected[@]} ]; then
    echo "Restore: not all custom monitors available, nothing to do"
    return 0
  fi

  echo "Restoring: $state (${candidates[*]})"
  if [ "$state" = "profile1" ] || [ "$state" = "profile2" ]; then
    enable_profile "${state#profile}"
  else
    enable_monitors "${expected[@]}"
  fi
}
```

- [ ] **Step 3: Persist state at all 5 apply sites** — wrap helper call in `if ...; then save_state "<state>"; fi`:
  - toggle profile2 branch → `save_state "profile2"`
  - toggle profile1 branch → `save_state "profile1"`
  - enable_profile 1 → `save_state "profile1"`; enable_profile 2 → `save_state "profile2"`
  - enable_monitors → `save_state "custom:${monitors[*]}"`

- [ ] **Step 4: Wire `restore` into main** — add to skip-keybinding condition (L302) and case statement:

```bash
    restore)
        restore_profile
        ;;
```

- [ ] **Step 5: Run suite → GREEN**, then `bash tests/run_all_tests.sh --skip-docker` (all suites still pass)

### Task 3: Hotplug wiring (systemd + udev)

**Files:**
- Create: `config/systemd-user/monitor-switch-restore.service` (precedent: storagebox units)
- Create: `config/udev/99-monitor-switch-restore.rules`

- [ ] **Step 1: Unit**

```ini
[Unit]
Description=Re-apply last monitor-switch profile after display hotplug

[Service]
Type=oneshot
ExecStart=%h/env/bin/monitor-switch restore
```

- [ ] **Step 2: udev rule** (verify `systemctl --user -M yashar@` works as root first)

```
ACTION=="change|add", SUBSYSTEM=="drm", RUN+="/usr/bin/systemctl --user -M yashar@ start monitor-switch-restore.service"
```

- [ ] **Step 3: Install + verify live**

```bash
cp config/systemd-user/monitor-switch-restore.service ~/.config/systemd/user/
systemctl --user daemon-reload
sudo cp config/udev/99-monitor-switch-restore.rules /etc/udev/rules.d/
sudo udevadm control --reload
systemctl --user start monitor-switch-restore.service   # expect "No saved profile" in journal
monitor-switch toggle && monitor-switch restore          # expect same layout re-asserted
monitor-switch toggle                                    # back to original
sudo udevadm trigger -c change -s drm                    # expect restore fires via udev
```

### Task 4: Docs + bookkeeping

- Create: `docs/2026-10-15-monitor-switch-restore.md` (design + ops, style of the EDID-fallback doc)
- Update: `docs/TESTING.md` suite list; `tasks/todo.md` entry + review; script `help`/`list` text mentions `restore` + state file.

**Self-review:** spec coverage — remember last mode (Task 2 state file), restore on reconnect (Tasks 2–3), disconnect case = subset restore (Task 2/test 4). Placeholders: none. Names consistent (`save_state`/`read_state`/`wait_for_connectors`/`restore_profile`).
