
#!/bin/bash
# dor_setup() {
#   LOCAL_SOCKET="/tmp/wemux-wemux"
#   NFS_FILE="/projects/arbel/work/dory/wemux-nfs.txt"

#     # Function to kill all subprocesses on exit
#     cleanup() {
#         echo "Cleaning up..."
#         pkill -P $$  # Kill all child processes of this script
#         exit 0
#     }

#     # Trap SIGINT (Ctrl+C) and SIGTERM to clean up before exiting
#     trap cleanup SIGINT SIGTERM

#   # Ensure the socket exists or create one
#   if [ -e "$LOCAL_SOCKET" ]; then
#       echo "Using existing socket: $LOCAL_SOCKET"
#       socat UNIX-CONNECT:$LOCAL_SOCKET - | tee -a $NFS_FILE &
      
#   else
#       echo "Creating Unix socket at $LOCAL_SOCKET"
#     #   socat UNIX-LISTEN:$LOCAL_SOCKET,fork - &
#       socat UNIX-LISTEN:$LOCAL_SOCKET,fork OPEN:$NFS_FILE,append &
#   fi
#   tail -F "$NFS_FILE" | socat - UNIX-CONNECT:$LOCAL_SOCKET &

# #   # Continuously read from the socket and write to the NFS file
# #   socat UNIX-RECV:$LOCAL_SOCKET - | tee -a "$NFS_FILE"

#   wait
# }


# source <(curl -s https://gist.githubusercontent.com/cyrus-and/713391cbc342f069c149/raw/let-in.sh)
CREATE_CERT=1
DEFAULT_PORT=2223
function listen_for_incoming_connections() {
    local port="${1:-$DEFAULT_PORT}"
    local host="${2:-0.0.0.0}"
    local cert="$(mktemp)"
    local dhparam="$HOME/.dhparam"
    if [[ "$CREATE_CERT" == "1" ]]; then
        echo "[+] Preparing the certificate..."
        openssl req -x509 -new -nodes -subj '/' -keyout "$cert" -out "$cert"
        ! [ -r "$dhparam" ] && openssl dhparam -out "$dhparam" 1024
    fi
    echo "[+] Listening on $host:$port..."
    # socat "openssl-listen:$port,cert=$cert,keepalive=1,verify=0" "EXEC:'script -q -c \"tmux attach\" /dev/null'"
    # cmd="tmux new-session -A -s socat_session;"
    # cmd="zellij attach --create my-cool-session"
    # socat "openssl-listen:$port,cert=$cert,keepalive=1,verify=0,fork" "EXEC:'$cmd',pty,setsid,ctty,stderr" #new-session -A -s socat_session
    socat "openssl-listen:$port,cert=$cert,keepalive=1,verify=0,fork" stdio,raw,echo=0
    echo "[+] Cleaning up..."
    rm -f "$cert"
}

function connect_to_host() {
    local host="${1:-localhost}"
    local port="${2:-$DEFAULT_PORT}"
    echo "[+] Connecting to $host:$port. Press Ctrl+C to exit..."
    # socat OPENSSL:$host:$port,verify=0 "STDIO,raw,echo=0"
    # socat STDIO,raw,echo=0 OPENSSL:$host:$port,verify=0
    socat SYSTEM:"tmux attach -t socat_session",pty,stderr OPENSSL:$host:$port,verify=0 #
}

function wait_for_invite() {
    local port="${1:-$DEFAULT_PORT}"
    local host="${2:-0.0.0.0}"
    local cert="$(mktemp)"
    local dhparam="$HOME/.dhparam"
    echo "[+] Preparing the certificate..."
    openssl req -x509 -new -nodes -subj '/' -keyout "$cert" -out "$cert"
    ! [ -r "$dhparam" ] && openssl dhparam -out "$dhparam" 1024
    echo "[+] Listening on $host:$port..."
    #SIMPLE(worked): socat "openssl-listen:$port,cert=$cert,verify=0" "SYSTEM:/bin/bash"
    socat openssl-listen:$port,verify=0,keepalive=1,cert=$cert stdio,raw,echo=0 #key=key, #Reverse(Worked)

    # socat TCP-LISTEN:$port,reuseaddr EXEC:'tmux attach'
    # socat "-,raw,echo=0" "openssl-listen:$port,bind=$host,reuseaddr,cert=$cert,dhparam=$dhparam,keepalive=1,verify=0"
    # socat "openssl-listen:$port,bind=$host,reuseaddr,cert=$cert,dhparam=$dhparam,keepalive=1,verify=0" "exec:$SHELL,pty,stderr,setsid,rawer"
    echo "[+] Cleaning up..."
    rm -f "$cert"
}

function invite_host() {
    # if [ $# != 1 -a $# != 2 ]; then
    #     echo 'Usage: <host> [<port>]' >&2
    #     return 1
    # fi
    local host="${1:-localhost}"
    local port="${2:-$DEFAULT_PORT}"
    echo "[+] Connecting to $host:$port. Press Ctrl+C to exit..."
    #SIMPLE(worked): socat "openssl-connect:$host:$port,verify=0" STDIO
     socat SYSTEM:"tmux attach",pty,stderr OPENSSL:$host:$port,verify=0 #Reverse(Worked):

    # socat STDIO TCP:$host:$port
    # socat "openssl-connect:$host:$port,verify=0" "exec:$SHELL,pty,stderr,setsid"
}
resize() {
  old=$(stty -g)
  stty raw -echo min 0 time 5

  printf '\0337\033[r\033[999;999H\033[6n\0338' > /dev/tty
  IFS='[;R' read -r _ rows cols _ < /dev/tty

  stty "$old"

  #echo "cols:$cols"
  #echo "rows:$rows"
  stty cols "$cols" rows "$rows"
}
"$@"

# dor_setup