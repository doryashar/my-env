#!/usr/bin/env bash
# Tests for scripts/tools/sysboard.sh
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TEST_DIR/test_helper.sh"

SYSBOARD="$TEST_DIR/../scripts/tools/sysboard.sh"
FIXTURES="$TEST_DIR/fixtures/sysboard"

test_script_exists_and_sources() {
  assert_file_exists "$SYSBOARD" "sysboard.sh should exist"
  assert_source_succeeds "$SYSBOARD" "sysboard.sh should source cleanly"
}

test_usage_help() {
  local out
  out=$(bash "$SYSBOARD" --help 2>&1)
  assert_contains "$out" "sysboard" "--help should mention sysboard"
  assert_contains "$out" "--report" "--help should mention --report"
}

test_parse_args_defaults() {
  reset_globals
  sb_parse_args
  assert_equals "tui" "$MODE" "default mode is tui"
  assert_equals "1" "$AUTO_REFRESH" "auto refresh on by default"
  assert_equals "5" "$REFRESH_INTERVAL" "default interval 5"
}

test_parse_args_flags() {
  reset_globals
  sb_parse_args --report
  assert_equals "report" "$MODE" "--report sets report mode"

  reset_globals
  sb_parse_args --section docker
  assert_equals "docker" "$SECTION_FILTER" "--section docker sets filter"
  assert_equals "4" "$START_SECTION" "--section docker maps to tab 4"

  reset_globals
  sb_parse_args --no-auto
  assert_equals "0" "$AUTO_REFRESH" "--no-auto disables refresh"

  reset_globals
  sb_parse_args --refresh 10
  assert_equals "10" "$REFRESH_INTERVAL" "--refresh 10 sets interval"
}

test_parse_args_rejects_bad_input() {
  reset_globals
  sb_parse_args --refresh abc 2>/dev/null
  assert_exit_code 1 $? "--refresh abc should return 1"

  reset_globals
  sb_parse_args --section bogus 2>/dev/null
  assert_exit_code 1 $? "--section bogus should return 1"

  reset_globals
  sb_parse_args --wat 2>/dev/null
  assert_exit_code 1 $? "unknown flag should return 1"
}

# reset globals between parse tests (values mirror script defaults)
reset_globals() {
  MODE="tui"
  SECTION_FILTER=""
  AUTO_REFRESH=1
  REFRESH_INTERVAL=5
  START_SECTION=1
}

# ---- collect_systemd tests ----

mock_systemctl_services() {
  systemctl() {
    local scope=0
    [[ "${1:-}" == "--user" ]] && { scope=1; shift; }
    case "$1" in
      list-unit-files)
        if [[ $scope -eq 1 ]]; then
          printf 'tagger-serve-8000.service enabled\nwa-face-bot.service enabled\n'
        else
          printf 'docker.service enabled\nollama.service enabled\nbroken.service masked\n'
        fi
        ;;
      list-units)
        if [[ $scope -eq 1 ]]; then
          printf 'tagger-serve-8000.service loaded active running tagger server\nwa-face-bot.service loaded failed failed face bot\n'
        else
          printf 'docker.service loaded active running docker engine\nollama.service loaded inactive dead llama server\nbroken.service loaded inactive dead broken\n'
        fi
        ;;
    esac
  }
}

test_collect_systemd() {
  mock_systemctl_services
  local out
  out=$(collect_systemd)
  assert_contains "$out" "$(printf 'active\trunning\tdocker.service\tenabled')" \
    "system rows: active docker.service enabled"
  assert_contains "$out" "$(printf 'inactive\tdead\tbroken.service\tmasked')" \
    "system rows: masked state joined from list-unit-files"
  local n
  n=$(collect_systemd | wc -l)
  assert_equals "3" "$n" "3 system services mocked"

  out=$(collect_systemd user)
  assert_contains "$out" "$(printf 'failed\tfailed\twa-face-bot.service\tenabled')" \
    "user rows: failed service listed"
}

test_collect_systemd_missing_unit_file_entry() {
  mock_systemctl_services
  systemctl() {
    [[ "${1:-}" == "--user" ]] && shift
    case "$1" in
      list-unit-files) : ;;
      list-units) printf 'dynamic.service loaded active running dyn\n' ;;
    esac
  }
  local out
  out=$(collect_systemd)
  assert_contains "$out" "$(printf 'active\trunning\tdynamic.service\tstatic')" \
    "unit missing from list-unit-files defaults to static"
}

# ---- collect_timers tests ----

mock_systemctl_timers() {
  systemctl() {
    local scope=0
    [[ "${1:-}" == "--user" ]] && { scope=1; shift; }
    case "$1" in
      list-units)
        if [[ $scope -eq 1 ]]; then
          printf 'photo-scan.timer loaded active waiting\n'
        else
          printf 'logrotate.timer loaded active waiting\nman-db.timer loaded inactive dead\n'
        fi
        ;;
      show)
        # args: show UNIT --property=P --value
        # Unset properties emit NOTHING (real systemctl --value
        # prints an empty line), so the n/a in output must come
        # from collect_timers' ${x:-n/a} fallback, not mock data.
        local unit="$2" prop="$3"
        prop="${prop#--property=}"
        if [[ "$prop" == "NextElapseUSecRealtime" ]]; then
          if [[ "$unit" == "photo-scan.timer" ]]; then
            printf 'Mon 2026-09-28 08:00:00 IDT'
          elif [[ "$unit" == "man-db.timer" ]]; then
            printf ''
          else
            printf 'Sun 2026-09-27 06:30:00 IDT'
          fi
        elif [[ "$prop" == "LastTriggerUSec" ]]; then
          if [[ "$unit" == "photo-scan.timer" ]]; then
            printf ''
          else
            printf 'Sat 2026-09-26 06:30:00 IDT'
          fi
        fi
        ;;
    esac
  }
}

test_collect_timers() {
  mock_systemctl_timers
  local out
  out=$(collect_timers)
  assert_contains "$out" \
    "$(printf 'Sun 2026-09-27 06:30:00 IDT\tSat 2026-09-26 06:30:00 IDT\tlogrotate.timer')" \
    "system timer row: next, last, unit"
  assert_contains "$out" \
    "$(printf 'n/a\tSat 2026-09-26 06:30:00 IDT\tman-db.timer')" \
    "system timer row: empty next falls back to n/a"
  assert_equals "2" "$(collect_timers | wc -l)" "2 system timers mocked"

  out=$(collect_timers user)
  assert_contains "$out" \
    "$(printf 'Mon 2026-09-28 08:00:00 IDT\tn/a\tphoto-scan.timer')" \
    "user timer with n/a last trigger"
}

# ---- collect_docker tests ----

mock_docker() {
  # Rows mimic: docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
  # (single tabs; consecutive IFS-whitespace tabs collapse in `read`, and real
  # docker never emits empty double-tab fields). Rows 1/3 have empty ports.
  docker() {
    printf 'rclone-mount\trclone/rclone:1.66\tUp 3 days\t\n'
    printf 'env-nginx\tnginx:latest\tExited (0) 2 days ago\t0.0.0.0:80->80/tcp\n'
    printf 'fresh\talpine:3.20\tCreated\t\n'
  }
}

test_docker_state_from_status() {
  assert_equals "running" "$(docker_state_from_status 'Up 3 days (healthy)')" "Up -> running"
  assert_equals "exited" "$(docker_state_from_status 'Exited (0) 2 days ago')" "Exited -> exited"
  assert_equals "created" "$(docker_state_from_status 'Created')" "Created -> created"
  assert_equals "restarting" "$(docker_state_from_status 'Restarting (1) 5s ago')" "Restarting -> restarting"
  assert_equals "other" "$(docker_state_from_status 'Dead')" "unknown -> other"
  assert_equals "paused" "$(docker_state_from_status 'Up 2 hours (Paused)')" "Up (Paused) -> paused"
  assert_equals "paused" "$(docker_state_from_status 'Paused')" "bare Paused -> paused"
  assert_equals "running" "$(docker_state_from_status 'Up 2 minutes (unhealthy)')" "health suffix ignored -> running"
}

test_collect_docker() {
  mock_docker
  local out
  out=$(collect_docker)
  assert_contains "$out" \
    "$(printf 'running\trclone-mount\trclone/rclone:1.66\tUp 3 days\t')" \
    "running container row"
  assert_contains "$out" \
    "$(printf 'exited\tenv-nginx\tnginx:latest\tExited (0) 2 days ago\t0.0.0.0:80->80/tcp')" \
    "exited container row with ports"
  assert_equals "3" "$(collect_docker | wc -l)" "3 containers mocked"
}

test_collect_docker_missing_binary() {
  mock_docker
  docker() { return 127; }   # simulate missing/broken docker
  local out
  out=$(collect_docker)
  assert_equals "" "$out" "broken docker yields no rows"
}

# ---- collect_cron tests ----

setup_cron_fixtures() {
  rm -rf "$FIXTURES"
  mkdir -p "$FIXTURES/cron.d"
  cat > "$FIXTURES/crontab" <<'EOF'
# daily brief
0 8 * * * /home/yashar/financial_status/daily_brief.py
*/30 * * * * /home/yashar/bin/whatsapp-send.sh disk-low
@reboot /usr/bin/some-daemon --foreground
MAILTO=admin@example.com
SHELL=/bin/bash
EOF
  cat > "$FIXTURES/cron.d/custom-job" <<'EOF'
5 4 * * * root /usr/local/bin/backup.sh daily
# comment line
15 14 * * 0 yashar /usr/local/bin/weekly.sh
EOF
}

test_cron_parse_line_user() {
  local entry
  entry=$(cron_parse_line "0 8 * * * /home/me/run.py arg" user)
  assert_equals "$(printf '0 8 * * *\t%s\t/home/me/run.py arg' "$USER")" "$entry" \
    "user line: 5-field schedule, USER, rest is command"

  entry=$(cron_parse_line "@reboot /usr/bin/daemon" user)
  assert_equals "$(printf '@reboot\t%s\t/usr/bin/daemon' "$USER")" "$entry" \
    "user @-schedule"
}

test_cron_parse_line_system() {
  local entry
  entry=$(cron_parse_line "5 4 * * * root /usr/local/bin/backup.sh daily" system)
  assert_equals "$(printf '5 4 * * *\troot\t/usr/local/bin/backup.sh daily')" "$entry" \
    "cron.d line: schedule, user field, command"

  entry=$(cron_parse_line "@daily yashar /usr/local/bin/cleanup.sh" system)
  assert_equals "$(printf '@daily\tyashar\t/usr/local/bin/cleanup.sh')" "$entry" \
    "cron.d @-schedule with user"
}

test_cron_parse_line_skips() {
  cron_parse_line "# just a comment" user
  assert_exit_code 1 $? "comments skipped"
  cron_parse_line "MAILTO=foo@bar" user
  assert_exit_code 1 $? "env assignments skipped"
  cron_parse_line "" user
  assert_exit_code 1 $? "empty lines skipped"
}

test_collect_cron() {
  setup_cron_fixtures
  crontab() { [[ "${1:-}" == "-l" ]] && cat "$FIXTURES/crontab"; }
  local out
  out=$(collect_cron "$FIXTURES/cron.d")
  assert_equals "5" "$(printf '%s' "$out" | grep -c .)" "3 user + 2 cron.d entries"
  assert_contains "$out" "$(printf 'user\t0 8 * * *\t%s\t/home/yashar/financial_status/daily_brief.py' "$USER")" \
    "user daily brief row"
  assert_contains "$out" "$(printf '%s/custom-job\t5 4 * * *\troot\t/usr/local/bin/backup.sh daily' "$FIXTURES/cron.d")" \
    "cron.d row labeled with file path"
  assert_contains "$out" "$(printf 'user\t@reboot\t%s\t/usr/bin/some-daemon --foreground' "$USER")" \
    "@reboot row"
  ! printf '%s' "$out" | grep -q MAILTO
  assert_equals "0" $? "MAILTO env line not present"
}

# ---- collect_autostart tests ----

setup_autostart_fixtures() {
  rm -rf "$FIXTURES"
  mkdir -p "$FIXTURES/user-autostart" "$FIXTURES/system-autostart"
  cat > "$FIXTURES/user-autostart/nimbus.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Nimbus Clipper
Exec=/usr/local/bin/nimbus --clip
X-GNOME-Autostart-enabled=true
EOF
  cat > "$FIXTURES/user-autostart/paused-app.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Paused App
Exec=/usr/bin/paused-app
X-GNOME-Autostart-enabled=false
EOF
  cat > "$FIXTURES/user-autostart/hidden-app.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Hidden App
Exec=/usr/bin/hidden-app
Hidden=true
EOF
  cat > "$FIXTURES/system-autostart/org-gnome-Settings.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=GNOME Settings Daemon
Exec=/usr/libexec/gsd-settings
EOF
}

test_collect_autostart() {
  setup_autostart_fixtures
  local out
  out=$(collect_autostart "$FIXTURES/user-autostart" "$FIXTURES/system-autostart")
  assert_equals "4" "$(printf '%s' "$out" | grep -c .)" "3 user + 1 system entries"
  assert_contains "$out" \
    "$(printf 'enabled\tNimbus Clipper\t/usr/local/bin/nimbus --clip\tuser\t%s/user-autostart/nimbus.desktop' "$FIXTURES")" \
    "enabled user entry"
  assert_contains "$out" "$(printf 'disabled\tPaused App\t/usr/bin/paused-app')" \
    "X-GNOME-Autostart-enabled=false -> disabled"
  assert_contains "$out" "$(printf 'hidden\tHidden App\t/usr/bin/hidden-app')" \
    "Hidden=true -> hidden"
  assert_contains "$out" \
    "$(printf 'enabled\tGNOME Settings Daemon\t/usr/libexec/gsd-settings\tsystem\t%s/system-autostart/org-gnome-Settings.desktop' "$FIXTURES")" \
    "system entry (no enable key defaults enabled, scope=system)"
}

# ---- report rendering tests ----

mock_all_collectors_for_report() {
  systemctl() {
    local scope=0
    [[ "${1:-}" == "--user" ]] && { scope=1; shift; }
    case "$1" in
      list-unit-files) [[ $scope -eq 1 ]] && printf 'wa-face-bot.service enabled\n' || printf 'docker.service enabled\n' ;;
      list-units)
        if [[ "$2" == "timer" ]]; then
          [[ $scope -eq 1 ]] && printf 'photo-scan.timer loaded active waiting\n' || printf 'logrotate.timer loaded active waiting\n'
        else
          [[ $scope -eq 1 ]] && printf 'wa-face-bot.service loaded failed failed bot\n' || printf 'docker.service loaded active running docker\n'
        fi
        ;;
      show)
        local prop="$3"; prop="${prop#--property=}"
        [[ "$prop" == "NextElapseUSecRealtime" ]] && printf 'Mon 2026-09-28 08:00:00 IDT' || printf 'n/a'
        ;;
    esac
  }
  docker() { printf 'env-nginx\tnginx:latest\tExited (0) 2 days ago\t\n'; }
  crontab() { [[ "${1:-}" == "-l" ]] && printf '0 8 * * * /home/me/brief.py\n'; }
  setup_cron_fixtures
  setup_autostart_fixtures
}

test_state_color_mapping() {
  assert_equals "$GREEN" "$(sb_state_color active)" "active -> green"
  assert_equals "$GREEN" "$(sb_state_color running)" "running -> green"
  assert_equals "$YELLOW" "$(sb_state_color activating)" "activating -> yellow"
  assert_equals "$RED" "$(sb_state_color failed)" "failed -> red"
  assert_equals "$GRAY" "$(sb_state_color inactive)" "inactive -> gray"
  assert_equals "$GRAY" "$(sb_state_color exited)" "exited -> gray"
}

test_render_report_contains_all_sections() {
  mock_all_collectors_for_report
  local out
  out=$(SYSBOARD_CRON_D="$FIXTURES/cron.d" \
        SYSBOARD_USER_AUTOSTART="$FIXTURES/user-autostart" \
        SYSBOARD_SYSTEM_AUTOSTART="$FIXTURES/system-autostart" \
        sb_render_report)
  assert_contains "$out" "System Services" "report has system services header"
  assert_contains "$out" "User Services" "report has user services header"
  assert_contains "$out" "Timers" "report has timers header"
  assert_contains "$out" "Docker" "report has docker header"
  assert_contains "$out" "Cron" "report has cron header"
  assert_contains "$out" "Autostart" "report has autostart header"
  assert_contains "$out" "docker.service" "report lists docker.service"
  assert_contains "$out" "env-nginx" "report lists docker container"
  assert_contains "$out" "/home/me/brief.py" "report lists cron command"
}

test_render_report_section_filter() {
  mock_all_collectors_for_report
  SECTION_FILTER="docker"
  local out
  out=$(sb_render_report)
  assert_contains "$out" "Docker" "filtered report has docker header"
  ! printf '%s' "$out" | grep -q "System Services"
  assert_equals "0" $? "filtered report omits system services"
  SECTION_FILTER=""
}

test_render_report_empty_section_says_none() {
  systemctl() { :; }
  docker() { :; }
  crontab() { return 1; }
  local out
  out=$(SYSBOARD_CRON_D=/nonexistent sb_render_report)
  assert_contains "$out" "(none)" "empty sections show (none)"
}

test_non_tty_falls_back_to_report() {
  local out rc
  out=$(bash "$SYSBOARD" </dev/null 2>&1); rc=$?
  assert_exit_code 0 $rc "non-TTY invocation exits 0"
  assert_contains "$out" "falling back to report mode" "notices fallback"
}

# ---- TUI tests ----
# TUI tests run under `setsid -w` so /dev/tty has no controlling terminal
# and sb_input falls back to the piped stdin keys (works from any shell).

test_tui_quits_on_q() {
  local out rc
  out=$(printf 'q' | SYSBOARD_FORCE_TUI=1 TERM=xterm setsid -w bash "$SYSBOARD" --no-auto 2>&1); rc=$?
  assert_exit_code 0 $rc "TUI exits 0 on q"
  assert_contains "$out" "sysboard" "TUI renders header"
}

test_tui_navigates_and_switches_tabs() {
  local out rc
  out=$(printf 'jj2kk4q' | SYSBOARD_FORCE_TUI=1 TERM=xterm setsid -w bash "$SYSBOARD" --no-auto 2>&1); rc=$?
  assert_exit_code 0 $rc "TUI handles j/k/2/4 then quits"
}

# ---- TUI action tests ----

test_sb_unit_scope_probes_user_bus() {
  systemctl() {
    [[ "${1:-}" == "--user" && "$3" == "photo-scan.timer" ]] && return 0
    return 1
  }
  assert_equals "--user" "$(sb_unit_scope photo-scan.timer)" "user timer -> --user"
  assert_equals "" "$(sb_unit_scope logrotate.timer)" "system timer -> empty scope"
}

test_sb_handle_action_readonly_sections() {
  SB_SECTION=5   # cron
  SB_ROWS=("user"$'\t'"0 8 * * *"$'\t'"$USER"$'\t'/bin/true)
  SB_SEL=0
  SB_MSG=""
  sb_handle_action s
  assert_contains "$SB_MSG" "read-only" "cron section rejects stop action"
  SB_SECTION=6   # autostart
  sb_handle_action r
  assert_contains "$SB_MSG" "read-only" "autostart section rejects restart"
}

test_sb_selected_unit() {
  SB_SECTION=1
  SB_ROWS=("active"$'\t'"running"$'\t'"docker.service"$'\t'"enabled")
  SB_SEL=0
  assert_equals "docker.service" "$(sb_selected_unit)" "systemd unit extracted"
  SB_SECTION=4
  SB_ROWS=("running"$'\t'"env-nginx"$'\t'"nginx:latest"$'\t'"Up"$'\t'"")
  assert_equals "env-nginx" "$(sb_selected_unit)" "docker name extracted"
  SB_SECTION=3
  SB_ROWS=("next"$'\t'"last"$'\t'"photo-scan.timer")
  assert_equals "photo-scan.timer" "$(sb_selected_unit)" "timer unit extracted"
}

test_sb_toggle_enable_direction() {
  SB_SECTION=1
  SB_ROWS=("inactive"$'\t'"dead"$'\t'"ollama.service"$'\t'"disabled")
  SB_SEL=0
  systemctl() {
    [[ "$1" == "is-enabled" ]] && echo "disabled" && return 0
    return 1
  }
  sb_systemd_action() { SB_MSG="would ${1:-} ${2:-}"; }
  sb_toggle_enable
  assert_contains "$SB_MSG" "would enable" "disabled unit toggles toward enable"
}

# --- run tests ---
test_script_exists_and_sources
test_usage_help
test_parse_args_defaults
test_parse_args_flags
test_parse_args_rejects_bad_input
test_collect_systemd
test_collect_systemd_missing_unit_file_entry
test_collect_timers
test_docker_state_from_status
test_collect_docker
test_collect_docker_missing_binary
test_cron_parse_line_user
test_cron_parse_line_system
test_cron_parse_line_skips
test_collect_cron
test_collect_autostart
test_state_color_mapping
test_render_report_contains_all_sections
test_render_report_section_filter
test_render_report_empty_section_says_none
test_non_tty_falls_back_to_report
test_tui_quits_on_q
test_tui_navigates_and_switches_tabs
test_sb_unit_scope_probes_user_bus
test_sb_handle_action_readonly_sections
test_sb_selected_unit
test_sb_toggle_enable_direction

print_test_summary
[[ $TESTS_FAILED -eq 0 ]] || exit 1
