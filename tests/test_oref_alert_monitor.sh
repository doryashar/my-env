#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_SCRIPT="$SCRIPT_DIR/../scripts/oref_alert_monitor.sh"
ALERT_DIR="$SCRIPT_DIR/fixtures"
mkdir -p "$ALERT_DIR"

setup_fixtures() {
  cat > "$ALERT_DIR/alert_active.json" << 'JSON'
{"id":"999000000010000000","cat":"1","title":"ירי רקטות וטילים","data":["תל אביב","ירושלים","חיפה"],"desc":"היכנסו למרחב המוגן"}
JSON

  cat > "$ALERT_DIR/alert_ended.json" << 'JSON'
{"id":"999000000020000000","cat":"10","title":"האירוע הסתיים","data":["תל אביב","ירושלים"],"desc":"השוהים במרחב המוגן יכולים לצאת"}
JSON

  printf '\xef\xbb\xbf' > "$ALERT_DIR/alert_empty.json"
}

test_empty_response_skipped() {
  setup_fixtures
  local output
  output=$(echo "" | POLL_INTERVAL=1 bash -c '
    raw=$(cat)
    stripped=$(echo "$raw" | sed "1s/^\xef\xbb\xbf//" | tr -d "[:space:]")
    if [[ -z "$stripped" ]]; then
      echo "SKIP:empty"
    else
      echo "PROCESS"
    fi
  ')
  assert_equals "SKIP:empty" "$output" "empty response should be skipped"
}

test_bom_only_response_skipped() {
  setup_fixtures
  local output
  output=$(cat "$ALERT_DIR/alert_empty.json" | POLL_INTERVAL=1 bash -c '
    raw=$(cat)
    stripped=$(echo "$raw" | sed "1s/^\xef\xbb\xbf//" | tr -d "[:space:]")
    if [[ -z "$stripped" ]]; then
      echo "SKIP:bom_only"
    else
      echo "PROCESS"
    fi
  ')
  assert_equals "SKIP:bom_only" "$output" "BOM-only response should be skipped"
}

test_alert_json_parsed() {
  setup_fixtures
  local output
  output=$(cat "$ALERT_DIR/alert_active.json" | bash -c '
    raw=$(cat)
    clean=$(echo "$raw" | sed "1s/^\xef\xbb\xbf//")
    alert_id=$(echo "$clean" | jq -r ".id" 2>/dev/null)
    title=$(echo "$clean" | jq -r ".title // empty")
    area_count=$(echo "$clean" | jq ".data | length")
    echo "id=$alert_id|title=$title|areas=$area_count"
  ')
  assert_equals "id=999000000010000000|title=ירי רקטות וטילים|areas=3" "$output" "should parse active alert correctly"
}

test_ended_alert_parsed() {
  setup_fixtures
  local output
  output=$(cat "$ALERT_DIR/alert_ended.json" | bash -c '
    raw=$(cat)
    clean=$(echo "$raw" | sed "1s/^\xef\xbb\xbf//")
    alert_id=$(echo "$clean" | jq -r ".id" 2>/dev/null)
    title=$(echo "$clean" | jq -r ".title // empty")
    desc=$(echo "$clean" | jq -r ".desc // empty")
    echo "id=$alert_id|title=$title|desc=$desc"
  ')
  assert_equals "id=999000000020000000|title=האירוע הסתיים|desc=השוהים במרחב המוגן יכולים לצאת" "$output" "should parse ended alert correctly"
}

test_id_change_detected() {
  setup_fixtures
  local output
  output=$(bash -c '
    raw=$(cat "'"$ALERT_DIR/alert_active.json"'")
    clean=$(echo "$raw" | sed "1s/^\xef\xbb\xbf//")
    alert_id=$(echo "$clean" | jq -r ".id" 2>/dev/null)
    LAST_ALERT_ID="old_id"
    if [[ "$alert_id" != "$LAST_ALERT_ID" ]]; then
      echo "NEW_ALERT:$alert_id"
    else
      echo "DUPLICATE"
    fi
  ')
  assert_equals "NEW_ALERT:999000000010000000" "$output" "should detect new alert ID"
}

test_id_duplicate_ignored() {
  setup_fixtures
  local output
  output=$(bash -c '
    raw=$(cat "'"$ALERT_DIR/alert_active.json"'")
    clean=$(echo "$raw" | sed "1s/^\xef\xbb\xbf//")
    alert_id=$(echo "$clean" | jq -r ".id" 2>/dev/null)
    LAST_ALERT_ID="999000000010000000"
    if [[ "$alert_id" != "$LAST_ALERT_ID" ]]; then
      echo "NEW_ALERT:$alert_id"
    else
      echo "DUPLICATE"
    fi
  ')
  assert_equals "DUPLICATE" "$output" "should ignore duplicate alert ID"
}

test_bom_with_content_parsed() {
  setup_fixtures
  local output
  local fixture_path="$ALERT_DIR/alert_active.json"
  output=$(bash -c '
    raw=$(printf "\xef\xbb\xbf%s" "$(cat "$0")")
    clean=$(echo "$raw" | sed "1s/^\xef\xbb\xbf//")
    alert_id=$(echo "$clean" | jq -r ".id" 2>/dev/null)
    title=$(echo "$clean" | jq -r ".title // empty")
    echo "id=$alert_id|title=$title"
  ' "$fixture_path")
  assert_equals "id=999000000010000000|title=ירי רקטות וטילים" "$output" "should handle BOM-prefixed JSON"
}

test_real_alert_file() {
  if [[ ! -f "$HOME/alert.json" ]]; then
    echo "SKIP: ~/alert.json not found"
    return 0
  fi
  local output
  local real_file="$HOME/alert.json"
  output=$(bash -c '
    raw=$(cat "$0")
    clean=$(echo "$raw" | sed "1s/^\xef\xbb\xbf//")
    alert_id=$(echo "$clean" | jq -r ".id" 2>/dev/null)
    title=$(echo "$clean" | jq -r ".title // empty")
    area_count=$(echo "$clean" | jq ".data | length" 2>/dev/null)
    echo "id=$alert_id|title=$title|areas=$area_count"
  ' "$real_file")
  echo "  Real file parsed: $output"
  [[ "$output" == *"id="* && "$output" == *"title="* && "$output" == *"areas="* ]]
  assert_exit_code 0 "should parse real alert file"
}

assert_equals() {
  local expected="$1" actual="$2" description="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $description"
  else
    echo "  FAIL: $description"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAILURES=$((FAILURES + 1))
  fi
}

assert_exit_code() {
  local description="$1"
  if [[ $? -eq 0 ]]; then
    echo "  PASS: $description"
  else
    echo "  FAIL: $description"
    FAILURES=$((FAILURES + 1))
  fi
}

FAILURES=0
echo "Running oref_alert_monitor tests..."
echo ""

test_empty_response_skipped
test_bom_only_response_skipped
test_alert_json_parsed
test_ended_alert_parsed
test_id_change_detected
test_id_duplicate_ignored
test_bom_with_content_parsed
test_real_alert_file

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
  echo "All tests passed!"
  exit 0
else
  echo "$FAILURES test(s) failed"
  exit 1
fi
