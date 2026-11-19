"""Throwaway SSH server for testing what rootshell reconnects to after a
session was attached from its session picker.

Every channel runs a real process on this Mac: a shell request starts an
interactive /bin/sh on a pty, an exec request runs the command under /bin/sh
(on a pty when the client asked for one). With a real zmx on PATH and a zmx
session already running, rootshell's session discovery finds that session and
the picker offers it.

Connection 1: once the shell receives a `zmx attach` (typed by the picker),
the server waits for zmx to attach, then drops the TCP connection without an
exit status, which rootshell treats as a lost connection and reconnects.
Connection 2: the server logs what the client asked for on the channel that
holds the terminal (the one with a pty). PASS when that is an exec of
`zmx attach` for the picked session and zmx then counts a client on it again;
FAIL when it is a shell. Any username and password work.

Usage: zmx_reconnect_sshd.py <port> <log file> <session> <environment file>
The environment file holds NAME=VALUE lines for every process the server runs
(PATH with zmx on it, ZMX_DIR, HOME, SHELL).
"""
import fcntl
import os
import pty
import select
import signal
import socket
import struct
import subprocess
import sys
import termios
import threading
import time

import paramiko

PORT = int(sys.argv[1])
LOG = sys.argv[2]
SESSION = sys.argv[3]
SESSION_ROW = f"name={SESSION}\t"
ENV = {}
with open(sys.argv[4]) as f:
    for line in f:
        line = line.rstrip("\n")
        if "=" in line:
            k, v = line.split("=", 1)
            ENV[k] = v
host_key = paramiko.RSAKey.generate(2048)
count = 0
lock = threading.Lock()


def log(msg):
    line = f"{time.strftime('%H:%M:%S')} {msg}"
    print(line, flush=True)
    with open(LOG, "a") as f:
        f.write(line + "\n")


def zmx_clients(session):
    """Client count zmx reports for `session`, or None when it is not listed."""
    out = subprocess.run(["zmx", "list"], env=ENV, capture_output=True, text=True, timeout=10).stdout
    for row in out.splitlines():
        # Rows look like `name=dev\tpid=123\tclients=1\t...`, the first field
        # prefixed by "→ " or two spaces when zmx marks the current session.
        fields = {}
        for f in row.split("\t"):
            if "=" in f:
                k, v = f.split("=", 1)
                fields[k.strip().lstrip("→").strip()] = v
        if fields.get("name") == session:
            try:
                return int(fields.get("clients", "-1"))
            except ValueError:
                return None
    return None


class Conn:
    """One SSH connection and the processes its channels started."""

    def __init__(self, n):
        self.n = n
        self.procs = []
        self.terminal_request = threading.Event()
        self.terminal_kind = None      # "shell" or "exec"
        self.terminal_command = None
        self.attach_typed = threading.Event()


class Server(paramiko.ServerInterface):
    def __init__(self, conn):
        self.conn = conn
        self.ptys = {}                 # chanid -> (cols, rows)

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

    def check_channel_pty_request(self, channel, term, width, height, pw, ph, modes):
        self.ptys[channel.get_id()] = (width, height)
        return True

    def check_channel_env_request(self, *args):
        return True

    def check_channel_window_change_request(self, channel, width, height, pw, ph):
        p = getattr(channel, "_rs_master", None)
        if p is not None:
            set_winsize(p, width, height)
        return True

    def check_channel_shell_request(self, channel):
        self._start(channel, None)
        return True

    def check_channel_exec_request(self, channel, command):
        self._start(channel, command.decode("utf-8", "replace"))
        return True

    def _start(self, channel, command):
        has_pty = channel.get_id() in self.ptys
        kind = "exec" if command is not None else "shell"
        shown = (command[:160] + "...") if command and len(command) > 160 else command
        log(f"conn {self.conn.n}: {kind} pty={has_pty} {shown!r}")
        if has_pty and not self.conn.terminal_request.is_set():
            self.conn.terminal_kind = kind
            self.conn.terminal_command = command
            self.conn.terminal_request.set()
        argv = ["/bin/sh", "-i"] if command is None else ["/bin/sh", "-c", command]
        threading.Thread(target=run_channel, args=(self.conn, channel, argv, has_pty,
                                                   self.ptys.get(channel.get_id())), daemon=True).start()


def set_winsize(fd, cols, rows):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def run_channel(conn, chan, argv, has_pty, size):
    env = dict(ENV)
    env["TERM"] = "xterm-256color"
    if has_pty:
        master, slave = pty.openpty()
        set_winsize(master, *(size or (80, 24)))
        chan._rs_master = master
        proc = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave, env=env,
                                cwd=env.get("HOME"), start_new_session=True)
        os.close(slave)
        conn.procs.append(proc)
        typed = b""
        while True:
            r, _, _ = select.select([master, chan], [], [], 0.2)
            if master in r:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    data = b""
                if not data:
                    break
                try:
                    chan.sendall(data)
                except Exception:
                    break
            if chan in r:
                data = chan.recv(65536)
                if not data:
                    break
                typed = (typed + data)[-4096:]
                if b"zmx attach" in typed and not conn.attach_typed.is_set():
                    log(f"conn {conn.n}: picker typed {typed.decode('utf-8', 'replace').strip()[-160:]!r}")
                    conn.attach_typed.set()
                os.write(master, data)
            if proc.poll() is not None and not select.select([master], [], [], 0)[0]:
                break
        try:
            os.close(master)
        except OSError:
            pass
    else:
        proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, env=env, cwd=env.get("HOME"),
                                start_new_session=True)
        conn.procs.append(proc)
        out, _ = proc.communicate()
        try:
            chan.sendall(out)
        except Exception:
            pass
        if "::ZMX_START_" in argv[-1]:
            found = SESSION_ROW in out.decode("utf-8", "replace")
            log(f"conn {conn.n}: session discovery done, session {'listed' if found else 'NOT listed'}")
    code = proc.wait()
    try:
        chan.send_exit_status(code)
        chan.close()
    except Exception:
        pass


def kill_all(conn):
    for p in conn.procs:
        try:
            os.killpg(p.pid, signal.SIGHUP)
        except (ProcessLookupError, PermissionError):
            pass


def handle(sock, n):
    conn = Conn(n)
    t = paramiko.Transport(sock)
    t.add_server_key(host_key)
    t.start_server(server=Server(conn))
    while t.is_active():
        chan = t.accept(1)
        if chan is None and not conn.terminal_request.is_set() and not t.is_active():
            break
        if conn.terminal_request.is_set():
            break
    if not conn.terminal_request.wait(30):
        log(f"conn {n}: no terminal channel")
        t.close()
        return
    # Keep accepting channels (session discovery opens exec channels).
    threading.Thread(target=lambda: [t.accept(1) for _ in iter(t.is_active, False)], daemon=True).start()

    if n == 1:
        if not conn.attach_typed.wait(90):
            log("conn 1: no zmx attach arrived from the picker")
            log("conn 1 RESULT: NO VERDICT")
            return
        time.sleep(4)
        log(f"conn 1: zmx reports {zmx_clients(SESSION)} client(s) on {SESSION!r}")
        log("conn 1: dropping TCP without exit status")
        t.close()
        sock.close()
        kill_all(conn)
        return

    log(f"conn {n}: terminal channel is {conn.terminal_kind}")
    cmd = conn.terminal_command or ""
    if conn.terminal_kind == "exec" and "zmx attach" in cmd and SESSION in cmd:
        time.sleep(4)
        clients = zmx_clients(SESSION)
        log(f"conn {n}: zmx reports {clients} client(s) on {SESSION!r}")
        verdict = "PASS reattached" if clients and clients > 0 else "FAIL exec ran but zmx counts no client"
    elif conn.terminal_kind == "shell":
        verdict = "FAIL reconnected to a shell"
    else:
        verdict = f"FAIL unexpected terminal channel {conn.terminal_kind} {cmd[:80]!r}"
    log(f"conn {n} RESULT: {verdict}")
    # Keep the connection up so a screenshot can show what the pane holds.
    end = time.time() + 120
    while time.time() < end and t.is_active():
        time.sleep(1)
    kill_all(conn)


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
