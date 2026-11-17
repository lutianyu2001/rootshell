"""Throwaway SSH server for testing rootshell's reconnect.

Connection 1 turns on the modes a TUI would (mouse, focus, bracketed paste,
alternate screen), confirms with DECRQM that the terminal took them, then
drops the TCP connection without an exit status, which rootshell treats as a
lost connection and reconnects. Connection 2 asks with DECRQM which of those
modes are still set and logs the answers. Any username and password work.
"""
import re
import socket
import sys
import threading
import time

import paramiko

# Usage: fake_sshd.py [<port>] [<log file>] [<paramiko debug log>]
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 2222
LOG = sys.argv[2] if len(sys.argv) > 2 else "fake_sshd.log"
MODES = [1000, 1002, 1003, 1006, 1004, 2004, 1049]
if len(sys.argv) > 3:
    paramiko.util.log_to_file(sys.argv[3])
host_key = paramiko.RSAKey.generate(2048)
count = 0
lock = threading.Lock()


def log(msg):
    line = f"{time.strftime('%H:%M:%S')} {msg}"
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")


class Server(paramiko.ServerInterface):
    def __init__(self):
        self.shell = threading.Event()

    def check_channel_request(self, kind, chanid):
        return paramiko.OPEN_SUCCEEDED if kind == "session" else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

    def get_allowed_auths(self, username):
        return "password,none"

    def check_auth_none(self, username):
        return paramiko.AUTH_SUCCESSFUL

    def check_auth_password(self, username, password):
        return paramiko.AUTH_SUCCESSFUL

    def check_auth_publickey(self, username, key):
        return paramiko.AUTH_FAILED

    def check_channel_pty_request(self, *args):
        return True

    def check_channel_env_request(self, *args):
        return True

    def check_channel_window_change_request(self, *args):
        return True

    def check_channel_shell_request(self, channel):
        self.shell.set()
        return True

    def check_channel_exec_request(self, channel, command):
        return False


def query(chan, modes, timeout=5.0):
    """Send DECRQM for each mode and collect the replies (1 set, 2 reset)."""
    chan.send("".join(f"\x1b[?{m}$p" for m in modes))
    buf, end, answers = "", time.time() + timeout, {}
    chan.settimeout(0.3)
    while time.time() < end and len(answers) < len(modes):
        try:
            data = chan.recv(4096)
            if not data:
                break
            buf += data.decode("latin-1")
        except socket.timeout:
            pass
        for m, v in re.findall(r"\x1b\[\?(\d+);(\d)\$y", buf):
            answers[int(m)] = int(v)
    return answers, buf


def handle(sock, n):
    t = paramiko.Transport(sock)
    t.add_server_key(host_key)
    server = Server()
    t.start_server(server=server)
    chan = t.accept(30)
    if chan is None or not server.shell.wait(30):
        log(f"conn {n}: no shell")
        t.close()
        return
    time.sleep(1.0)
    if n == 1:
        chan.send("\x1b[?1049h\x1b[?1000h\x1b[?1002h\x1b[?1006h\x1b[?1004h\x1b[?2004h")
        chan.send("\x1b[2J\x1b[HFAKE TUI on the alternate screen, mouse reporting on\r\n")
        answers, _ = query(chan, MODES)
        log(f"conn 1 modes before drop: {answers}")
        time.sleep(2.0)
        log("conn 1: dropping TCP without exit status")
        t.close()
        sock.close()
    else:
        chan.send("fresh shell after reconnect\r\n")
        answers, raw = query(chan, MODES)
        log(f"conn {n} modes after reconnect: {answers}")
        still_on = [m for m, v in answers.items() if v == 1]
        log(f"conn {n} RESULT: {'FAIL still on ' + str(still_on) if still_on else 'PASS all reset'}")
        chan.send(f"modes still on: {still_on}\r\n")
        # Keep the session open; log whatever input arrives (mouse reports would show here).
        chan.settimeout(1.0)
        end = time.time() + 600
        while time.time() < end and t.is_active():
            try:
                data = chan.recv(4096)
                if not data:
                    break
                log(f"conn {n} input: {data!r}")
            except socket.timeout:
                pass


def main():
    global count
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen(5)
    log(f"listening on {PORT}")
    while True:
        sock, _ = srv.accept()
        with lock:
            count += 1
            n = count
        log(f"conn {n} accepted")
        threading.Thread(target=handle, args=(sock, n), daemon=True).start()


if __name__ == "__main__":
    main()
