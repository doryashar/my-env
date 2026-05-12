import socket
import threading

HOST = "0.0.0.0"  # Listen on all interfaces
PORT = 6667
clients = []

def handle_client(conn, addr):
    print(f"New connection from {addr}")
    conn.send(b":server 001 user :Welcome to Mini IRC Server!\r\n")

    while True:
        try:
            data = conn.recv(1024)
            if not data:
                break

            msg = data.decode().strip()
            print(f"{addr} says: {msg}")

            # Echo the message to all clients
            for client in clients:
                if client != conn:
                    client.sendall(data)
        except:
            break

    print(f"Connection closed: {addr}")
    clients.remove(conn)
    conn.close()

def start_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.bind((HOST, PORT))
    server.listen(5)
    print(f"IRC Server running on {HOST}:{PORT}")

    while True:
        conn, addr = server.accept()
        clients.append(conn)
        threading.Thread(target=handle_client, args=(conn, addr)).start()

if __name__ == "__main__":
    start_server()
