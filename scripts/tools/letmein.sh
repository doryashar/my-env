#!/bin/bash
#
# WARNING — TLS trust model:
#   This script uses socat OPENSSL with verify=0 (certificate verification
#   disabled) and an ephemeral self-signed cert. This is MITM-able by anyone
#   on the network. Only run this on a fully-trusted LAN, or replace the
#   ephemeral cert with a pinned CA (pass cafile= to socat).
#
set -e

CREATE_CERT=1
DEFAULT_PORT=2222

listen_for_incoming_connections() {
  local port="${1:-$DEFAULT_PORT}"
  local host="${2:-0.0.0.0}"
  local cert="$(mktemp)"
  local dhparam="$HOME/.dhparam"
  if [[ "$CREATE_CERT" == "1" ]]; then
    echo "[+] Preparing the certificate..."
    openssl req -x509 -new -nodes -subj '/' \
      -keyout "$cert" -out "$cert"
    [[ ! -r "$dhparam" ]] && openssl dhparam -out "$dhparam" 2048
  fi
  echo "[+] Listening on $host:$port..."
  local cmd="zellij attach --create my-cool-session"
  socat "openssl-listen:$port,cert=$cert,keepalive=1,verify=0,fork" \
    "EXEC:'$cmd',pty,raw,setsid,ctty,stderr"
  echo "[+] Cleaning up..."
  rm -f "$cert"
}

connect_to_host() {
  local host="${1:-localhost}"
  local port="${2:-$DEFAULT_PORT}"
  echo "[+] Connecting to $host:$port. Press Ctrl+C to exit..."
  socat STDIO,raw,echo=0 OPENSSL:$host:$port,verify=0
}

wait_for_invite() {
  local port="${1:-$DEFAULT_PORT}"
  local host="${2:-0.0.0.0}"
  local cert="$(mktemp)"
  local dhparam="$HOME/.dhparam"
  echo "[+] Preparing the certificate..."
  openssl req -x509 -new -nodes -subj '/' \
    -keyout "$cert" -out "$cert"
  [[ ! -r "$dhparam" ]] && openssl dhparam -out "$dhparam" 2048
  echo "[+] Listening on $host:$port..."
  socat openssl-listen:$port,verify=0,keepalive=1,cert=$cert \
    stdio,raw,echo=0
  echo "[+] Cleaning up..."
  rm -f "$cert"
}

invite_host() {
  local host="${1:-localhost}"
  local port="${2:-$DEFAULT_PORT}"
  echo "[+] Connecting to $host:$port. Press Ctrl+C to exit..."
  socat SYSTEM:"tmux attach",pty,stderr \
    OPENSSL:$host:$port,verify=0
}

resize() {
  local old
  old=$(stty -g)
  stty raw -echo min 0 time 5
  printf '\0337\033[r\033[999;999H\033[6n\0338' > /dev/tty
  IFS='[;R' read -r _ rows cols _ < /dev/tty
  stty "$old"
  stty cols "$cols" rows "$rows"
}

"$@"
