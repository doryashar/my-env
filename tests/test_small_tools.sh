#!/usr/bin/env bash
# Behavioural tests for the small tools fixes (task 16).
#
# Covers:
#   N1 new_claude.sh: syntax + ENV_DIR resolution (the two
#      SCRIPT_DIR=/ENV_DIR= lines are eval'd with $0 = the script)
#   A1 install_appman.sh: bash shebang + syntax
#   G1 generate_image.sh: a prompt containing " \ and $ survives the
#      curl --config round trip (stub curl; body delivered via file)
#   G2 the script's request-body temp file is removed on exit
#   I1 .gitignore: opencode backup files ignored, opencode.json not

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helper.sh"

REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export T

echo "========================================"
echo "Small Tools Tests"
echo "========================================"
echo ""

# --- N1: new_claude.sh --------------------------------------------------------
echo "=== N1: new_claude.sh ==="
bash -n "$REPO/scripts/tools/new_claude.sh"
assert_exit_code 0 $? "N1: bash -n new_claude.sh passes"
n1_env="$(bash -c '
    SCRIPT_DIR="$(cd "$2/../scripts/tools" && pwd)"
    eval "$(grep -E "^(SCRIPT_DIR=|ENV_DIR=)" "$0")"
    printf "%s" "$ENV_DIR"
' "$REPO/scripts/tools/new_claude.sh" _ "$SCRIPT_DIR")"
assert_file_exists "$n1_env/functions/virtualenv.sh" \
    "N1: \$ENV_DIR/functions/virtualenv.sh exists"
n1_ends=0
[[ "$n1_env" == */env ]] && n1_ends=1
assert_equals 1 "$n1_ends" "N1: ENV_DIR ends with /env"

# --- A1: install_appman.sh ------------------------------------------------------
echo "=== A1: install_appman.sh ==="
a1_first="$(head -1 "$REPO/scripts/install/install_appman.sh")"
assert_equals '#!/bin/bash' "$a1_first" \
    "A1: first line is exactly #!/bin/bash"
bash -n "$REPO/scripts/install/install_appman.sh"
assert_exit_code 0 $? "A1: bash -n install_appman.sh passes"

# --- G1: generate_image.sh keeps the prompt intact --------------------------------
echo "=== G1: generate_image.sh keeps the prompt intact ==="
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'STUB'
#!/bin/bash
# Stub curl: request via --config (body from a file), download via file://.
has_config=0
for a in "$@"; do
    [ "$a" = "--config" ] && has_config=1
done
if [ "$has_config" -eq 1 ]; then
    cat > "$T/curl.stdin"
    data_line="$(grep '^data = "@' "$T/curl.stdin" | head -1)"
    body="${data_line#data = \"@}"
    body="${body%\"}"
    cp "$body" "$T/body.json"
    printf '{"created":1,"data":[{"url":"file://%s/img.png"}]}\n' "$T"
    exit 0
fi
# download: curl -s -L -o OUT URL
cp "${5#file://}" "$4"
exit 0
STUB
chmod +x "$T/bin/curl"

printf 'img-bytes\n' > "$T/img.png"
PROMPT='say "hi" then C:\dir then $HOME
second line'
mkdir -p "$T/tmp"
g1_out="$(PATH="$T/bin:$PATH" GLM_API_KEY=k TMPDIR="$T/tmp" \
    bash "$REPO/scripts/tools/generate_image.sh" -o "$T/out.png" "$PROMPT")"
g1_rc=$?
assert_exit_code 0 "$g1_rc" "G1: generate_image.sh exits 0"
jq -e . "$T/body.json" >/dev/null
assert_exit_code 0 $? "G1: request body is valid JSON"
assert_equals "$PROMPT" "$(jq -r .prompt "$T/body.json")" \
    "G1: prompt survives the curl round trip intact"
assert_equals "cogView-4-250304" "$(jq -r .model "$T/body.json")" \
    "G1: model is cogView-4-250304"
assert_equals "1024x1024" "$(jq -r .size "$T/body.json")" \
    "G1: size is 1024x1024"
assert_file_exists "$T/out.png" "G1: output file exists"

# --- G2: no temp file left behind --------------------------------------------------
echo "=== G2: no temp file left behind ==="
assert_equals "" "$(ls -A "$T/tmp")" \
    "G2: the script's request-body temp file is removed on exit"
# The empty-prompt run exits before the body file exists, so this only
# proves that nothing is left behind on that path either.
g2b_out="$(PATH="$T/bin:$PATH" GLM_API_KEY=k TMPDIR="$T/tmp" \
    bash "$REPO/scripts/tools/generate_image.sh")"
g2b_rc=$?
assert_exit_code 1 "$g2b_rc" "G2: empty-prompt run exits 1"
assert_equals "" "$(ls -A "$T/tmp")" \
    "G2: empty-prompt run leaves nothing in its temp dir (it exits before the body file exists)"

# --- I1: .gitignore -----------------------------------------------------------------
echo "=== I1: .gitignore ==="
git -C "$REPO" check-ignore -q config/opencode/opencode.json.bak-ninfer-swap
assert_exit_code 0 $? "I1: opencode backup file is git-ignored"
git -C "$REPO" check-ignore -q config/opencode/opencode.json
assert_exit_code 1 $? "I1: opencode.json itself is not ignored"

# --- results ------------------------------------------------------------------------
if print_test_summary; then
    exit 0
fi
exit 1
