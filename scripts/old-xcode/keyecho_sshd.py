"""Throwaway SSH server that shows what the terminal sends.

Any username and password work. The shell echoes each read from the client
in visible form (ESC as ^[, other controls as ^X) on its own line, and logs
it, so a key press on the toolbar can be checked against the sequence it
should send.

usage: keyecho_sshd.py [<port>] [<log file>]
"""
import socket
import sys
import threading
import time

import paramiko

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 2223
LOG = sys.argv[2] if len(sys.argv) > 2 else "keyecho.log"
host_key = paramiko.RSAKey.generate(2048)


def visible(data):
    out = []
    for b in data:
        if b == 0x1B:
            out.append("^[")
        elif b < 0x20:
            out.append("^" + chr(b + 0x40))
        elif b == 0x7F:
            out.append("^?")
        else:
            out.append(chr(b))
    return "".join(out)


def log(msg):
    line = f"{time.strftime('%H:%M:%S')} {msg}"
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")


class Server(paramiko.ServerInterface):
    def check_channel_request(self, kind, chanid):
        return paramiko.OPEN_SUCCEEDED if kind == "session" else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

    def get_allowed_auths(self, username):
        return "password,none"

    def check_auth_none(self, username):
        return paramiko.AUTH_SUCCESSFUL

    def check_auth_password(self, username, password):
        return paramiko.AUTH_SUCCESSFUL

    def check_channel_pty_request(self, *args):
        return True

    def check_channel_env_request(self, *args):
        return True

    def check_channel_window_change_request(self, *args):
        return True

    def check_channel_shell_request(self, channel):
        return True


def serve(sock):
    transport = paramiko.Transport(sock)
    transport.add_server_key(host_key)
    transport.start_server(server=Server())
    channel = transport.accept(30)
    if channel is None:
        return
    log("session opened")
    channel.send(b"key echo ready\r\n")
    while True:
        data = channel.recv(1024)
        if not data:
            break
        shown = visible(data)
        log(f"received {shown!r}")
        channel.send(f"[{shown}]\r\n".encode())
    log("session closed")


def main():
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", PORT))
    listener.listen(5)
    log(f"listening on {PORT}")
    while True:
        sock, _ = listener.accept()
        threading.Thread(target=serve, args=(sock,), daemon=True).start()


main()
