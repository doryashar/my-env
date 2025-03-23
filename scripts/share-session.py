#!/bin/env python3

import socket
import threading
import argparse
import os
import time

# Configuration
LOCAL_SOCKET = "/tmp/local_socket"
NFS_FILE = "/mnt/nfs/shared_data.txt"
TCP_HOST = "192.168.1.100"  # Change this to the other machine's IP
TCP_PORT = 5000


def setup_unix_socket():
    """Attempts to connect to an existing Unix socket or create a new one."""
    if os.path.exists(LOCAL_SOCKET):
        print(f"Local socket {LOCAL_SOCKET} exists. Attempting to connect as a client...")
        try:
            client_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client_sock.connect(LOCAL_SOCKET)
            return client_sock, "client"
        except socket.error:
            print(f"Failed to connect to existing socket. Replacing it.")
            os.remove(LOCAL_SOCKET)

    # Create a new Unix socket and listen
    print(f"Creating new local Unix socket at {LOCAL_SOCKET}")
    server_sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server_sock.bind(LOCAL_SOCKET)
    server_sock.listen(1)
    return server_sock, "server"


def forward_unix_to_tcp(unix_sock, tcp_sock):
    """Forwards data from Unix socket to TCP."""
    while True:
        conn, _ = unix_sock.accept()
        with conn:
            while True:
                data = conn.recv(1024)
                if not data:
                    break
                tcp_sock.sendall(data)


def forward_tcp_to_unix(tcp_sock):
    """Forwards data from TCP socket to Unix socket."""
    while True:
        data = tcp_sock.recv(1024)
        if not data:
            break
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as unix_client:
            unix_client.connect(LOCAL_SOCKET)
            unix_client.sendall(data)


def forward_unix_to_nfs(unix_sock):
    """Forwards data from Unix socket to an NFS file."""
    while True:
        conn, _ = unix_sock.accept()
        with conn, open(NFS_FILE, "a") as f:
            while True:
                data = conn.recv(1024)
                if not data:
                    break
                f.write(data.decode() + "\n")


def forward_nfs_to_unix():
    """Reads from an NFS file and writes to the Unix socket."""
    last_position = 0
    while True:
        time.sleep(1)
        with open(NFS_FILE, "r") as f:
            f.seek(last_position)
            lines = f.readlines()
            last_position = f.tell()
        
        if lines:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as unix_client:
                unix_client.connect(LOCAL_SOCKET)
                unix_client.sendall("".join(lines).encode())


def run_relay(mode):
    """Runs the relay script in the selected mode (TCP or NFS)."""
    unix_sock, sock_type = setup_unix_socket()

    if mode == "tcp":
        tcp_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        tcp_sock.connect((TCP_HOST, TCP_PORT))

        if sock_type == "server":
            threading.Thread(target=forward_unix_to_tcp, args=(unix_sock, tcp_sock), daemon=True).start()
        threading.Thread(target=forward_tcp_to_unix, args=(tcp_sock,), daemon=True).start()

    elif mode == "nfs":
        if sock_type == "server":
            threading.Thread(target=forward_unix_to_nfs, args=(unix_sock,), daemon=True).start()
        threading.Thread(target=forward_nfs_to_unix, daemon=True).start()

    print(f"Relay running in {mode} mode as a {sock_type}.")
    while True:
        time.sleep(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Relay script between Unix sockets and TCP/NFS.")
    parser.add_argument("mode", choices=["tcp", "nfs"], help="Choose relay mode: 'tcp' or 'nfs'")
    args = parser.parse_args()
    run_relay(args.mode)
"""
move
copy: y, paste: p
delete : dd(line) de(word)
undo: u, redo: C-r
where am i: C-g, End: G, start: gg
goto line 
search with / or ?, forward with n backward with N, go back to where you came from C-o, C-i forward
% to match the parentesis
"""
