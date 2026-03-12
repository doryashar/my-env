#!/bin/bash

USE_REAL_BITWARDEN=${USE_REAL_BITWARDEN:-false}
USE_REAL_GITHUB=${USE_REAL_GITHUB:-false}
USE_REAL_SSH=${USE_REAL_SSH:-false}
USE_REAL_AGE=${USE_REAL_AGE:-false}

MOCK_BW_DIR=""
MOCK_GH_DIR=""
MOCK_AGE_DIR=""

setup_mocks() {
  MOCK_BW_DIR=$(mktemp -d)
  MOCK_GH_DIR=$(mktemp -d)
  MOCK_AGE_DIR=$(mktemp -d)
  
  mkdir -p "$MOCK_BW_DIR"/{items,folders}
  mkdir -p "$MOCK_GH_DIR"/repos
  mkdir -p "$MOCK_AGE_DIR"/{keys,encrypted}
  
  if [[ "$USE_REAL_BITWARDEN" != "true" ]]; then
    _create_mock_bw
    export PATH="$MOCK_BW_DIR:$PATH"
  fi
  
  if [[ "$USE_REAL_GITHUB" != "true" ]]; then
    _create_mock_gh
    export PATH="$MOCK_GH_DIR:$PATH"
  fi
  
  if [[ "$USE_REAL_AGE" != "true" ]]; then
    _create_mock_age
    export PATH="$MOCK_AGE_DIR:$PATH"
  fi
}

teardown_mocks() {
  rm -rf "$MOCK_BW_DIR" "$MOCK_GH_DIR" "$MOCK_AGE_DIR"
}

_create_mock_bw() {
  cat > "$MOCK_BW_DIR/bw" << 'MOCK_BW'
#!/bin/bash

BW_DATA_DIR="${MOCK_BW_DIR:-/tmp/mock-bw}"
BW_SESSION="${BW_SESSION:-mock-session}"
BW_STATUS="${BW_STATUS:-unlocked}"

case "$1" in
  status)
    echo "{\"status\":\"$BW_STATUS\"}"
    ;;
  login)
    if [[ "$2" == "--apikey" ]]; then
      echo "mock-session-token"
      exit 0
    fi
    echo "Logged in"
    ;;
  logout)
    echo "Logged out"
    ;;
  unlock)
    echo "$BW_SESSION"
    ;;
  lock)
    echo "Locked"
    ;;
  get)
    shift
    local item="$1"
    case "$item" in
      item|password)
        local name="$2"
        if [[ -f "$BW_DATA_DIR/items/$name" ]]; then
          cat "$BW_DATA_DIR/items/$name"
        else
          echo "{\"name\":\"$name\",\"login\":{\"password\":\"mock_password_$name\"},\"notes\":\"mock_notes\"}"
        fi
        ;;
      totp)
        echo "123456"
        ;;
      *)
        echo "Mock item data for $item"
        ;;
    esac
    ;;
  create)
    shift
    local type="$1"
    shift
    echo "Created mock $type"
    ;;
  delete)
    echo "Deleted"
    ;;
  list)
    echo "[]"
    ;;
  encode)
    cat
    ;;
  *)
    echo "Mock bw: $@" >&2
    ;;
esac
exit 0
MOCK_BW
  chmod +x "$MOCK_BW_DIR/bw"
  
  echo '{"name":"AGE_SECRET","login":{"password":"AGE_SECRET_KEY_MOCK_12345"}}' > "$MOCK_BW_DIR/items/AGE_SECRET"
  echo '{"name":"GITHUB_API_KEY","login":{"password":"ghp_mock_token_12345"}}' > "$MOCK_BW_DIR/items/GITHUB_API_KEY"
}

_create_mock_gh() {
  cat > "$MOCK_GH_DIR/gh" << 'MOCK_GH'
#!/bin/bash

case "$1" in
  auth)
    case "$2" in
      status)
        echo "Logged in to github.com"
        ;;
      login)
        echo "Logged in"
        ;;
      logout)
        echo "Logged out"
        ;;
    esac
    ;;
  repo)
    case "$2" in
      create)
        local repo_name="$3"
        echo "Created repository $repo_name"
        echo "{\"name\":\"$repo_name\",\"clone_url\":\"https://github.com/mock/$repo_name.git\"}"
        ;;
      view)
        echo "{\"name\":\"mock-repo\",\"private\":true}"
        ;;
      list)
        echo "[]"
        ;;
    esac
    ;;
  api)
    shift
    local endpoint="$1"
    echo "{\"message\":\"Mock API response for $endpoint\"}"
    ;;
  *)
    echo "Mock gh: $@" >&2
    ;;
esac
exit 0
MOCK_GH
  chmod +x "$MOCK_GH_DIR/gh"
}

_create_mock_age() {
  cat > "$MOCK_AGE_DIR/age" << 'MOCK_AGE'
#!/bin/bash

AGE_KEY="${AGE_SECRET:-AGE_SECRET_KEY_MOCK}"

encrypt_mode=false
decrypt_mode=false
recipient_file=""
output_file=""
input_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -R|--recipients-file)
      recipient_file="$2"
      shift 2
      ;;
    -d|--decrypt)
      decrypt_mode=true
      shift
      ;;
    -e|--encrypt)
      encrypt_mode=true
      shift
      ;;
    -o|--output)
      output_file="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      if [[ -z "$input_file" ]]; then
        input_file="$1"
      fi
      shift
      ;;
  esac
done

if $decrypt_mode; then
  if [[ -n "$input_file" && -f "$input_file" ]]; then
    if head -1 "$input_file" | grep -q "age-encryption"; then
      if [[ -n "$output_file" ]]; then
        tail -n +2 "$input_file" > "$output_file"
      else
        tail -n +2 "$input_file"
      fi
    else
      if [[ -n "$output_file" ]]; then
        cat "$input_file" > "$output_file"
      else
        cat "$input_file"
      fi
    fi
  else
    cat
  fi
else
  if [[ -n "$input_file" && -f "$input_file" ]]; then
    if [[ -n "$output_file" ]]; then
      echo "age-encryption.org/v1" > "$output_file"
      cat "$input_file" >> "$output_file"
    else
      echo "age-encryption.org/v1"
      cat "$input_file"
    fi
  else
    echo "age-encryption.org/v1"
    cat
  fi
fi
exit 0
MOCK_AGE
  chmod +x "$MOCK_AGE_DIR/age"
  
  echo "AGE_SECRET_KEY_MOCK_12345" > "$MOCK_AGE_DIR/keys/key.txt"
}

mock_bw_set_status() {
  local status="$1"
  export BW_STATUS="$status"
}

mock_bw_set_item() {
  local name="$1"
  local password="$2"
  echo "{\"name\":\"$name\",\"login\":{\"password\":\"$password\"}}" > "$MOCK_BW_DIR/items/$name"
}

mock_git_remote_exists() {
  local exists="$1"
  export MOCK_GIT_REMOTE_EXISTS="$exists"
}

mock_network_down() {
  export MOCK_NETWORK_DOWN="true"
}

mock_network_up() {
  export MOCK_NETWORK_DOWN="false"
}
