#!/usr/bin/env python3
"""Holds the key overlay's reader for the bar (services/KeyFeed.qml) so that
it outlives the bar's reloads and restarts: its password is asked only when
Super+Y turns the overlay on (the user, 2026-10-26), where the bar used to
start the reader anew at every reload, restart, install and login.

    keyfeed-hold.py SOCKET BAR_DIR --needs READER -- COMMAND [ARG...]

Runs COMMAND (pkexec and root's reader, READER) on pipes and hands it over
the UNIX socket SOCKET to one bar at a time: the reader's lines go out as
they come, and only resume, pause and stop come back. With no bar the
reader is paused and stray keys are dropped, so nothing is read while
nothing shows it. A line is looked at only for its type (the last "ready"
or "error" waits for a later bar) and zeroed once passed on. When the
reader ends, the bar is told how and this ends too.

Only the bar may connect: this user's process (SO_PEERCRED) running
quickshell on BAR_DIR (KEYFEED_HOLD_CLIENTS names other programs, for the
tests). SOCKET's directory is made 0700 and must be this user's alone; a
lock there, not the socket, tells a live holder, and hold.pid names it.
KeyFeed starts this in a systemd-run unit of its own, so a restart of
bar.service leaves it; the session's end ends it, and the reader with it at
the end of its stdin (root's past pkexec, it cannot be signalled from here).
"""

import fcntl
import json
import os
import selectors
import signal
import socket
import stat
import struct
import subprocess
import sys
import time

USAGE = "usage: keyfeed-hold.py SOCKET BAR_DIR --needs READER -- COMMAND [ARG...]"
STATUS = (b'{"type": "ready"', b'{"type": "error"')
CONTROL = (b"resume", b"pause", b"stop")
# Longer than any line the reader writes; one longer is dropped whole.
LINE_MAX = 4096
# How long a stopped reader has to go before this goes without it.
STOP_GRACE = 3.0
# EX_UNAVAILABLE: what KeyFeed reads as a reader not installed.
NOT_INSTALLED = 69

STOPPING = []


def say(text):
    print(f"keyfeed-hold: {text}", file=sys.stderr, flush=True)


def private_dir(path):
    """The socket's directory, made if missing; None unless it is this
    user's alone."""
    try:
        os.mkdir(path, 0o700)
    except FileExistsError:
        pass
    except OSError:
        return None
    try:
        info = os.lstat(path)
    except OSError:
        return None
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        return None
    return path


def claim(directory):
    """The lock that says a holder lives here; None when another holds it."""
    try:
        fd = os.open(os.path.join(directory, "lock"),
                     os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    except OSError:
        return None
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        os.close(fd)
        return None
    return fd


def clients():
    names = os.environ.get("KEYFEED_HOLD_CLIENTS")
    return set(names.split(",")) if names else {"qs", "quickshell"}


def is_bar(conn, bar_dir):
    """The process at the other end: this user's, the bar's program, on the
    bar's configuration (`-p DIR`, `--path DIR` or `--path=DIR`)."""
    try:
        pid, uid, _ = struct.unpack("3i", conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED,
                                                          struct.calcsize("3i")))
        if uid != os.getuid() or pid <= 0:
            return False
        exe = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            argv = [a.decode(errors="replace") for a in fh.read().split(b"\0")]
    except OSError:
        return False
    if exe not in clients() and os.path.basename(argv[0]) not in clients():
        return False
    want = os.path.realpath(bar_dir)
    given = []
    for i, arg in enumerate(argv):
        if arg in ("-p", "--path") and i + 1 < len(argv):
            given.append(argv[i + 1])
        elif arg.startswith("--path="):
            given.append(arg[len("--path="):])
    for path in given:
        real = os.path.realpath(path)
        if real == want or (os.path.isfile(real) and os.path.dirname(real) == want):
            return True
    return False


class Hold:
    def __init__(self, server, reader, bar_dir):
        self.server = server
        self.reader = reader
        self.bar_dir = bar_dir
        self.sel = selectors.DefaultSelector()
        self.client = None
        self.control = bytearray()
        self.line = bytearray()
        self.status = None
        self.complaint = b""
        self.err_line = bytearray()
        # Read into, never read: a bytes object the reader's lines arrived in
        # could not be zeroed after.
        self.buf = bytearray(4096)
        self.stop_at = None
        self.seen_bar = False
        self.sel.register(server, selectors.EVENT_READ, self.accept)
        self.sel.register(reader.stdout, selectors.EVENT_READ, self.from_reader)
        self.sel.register(reader.stderr, selectors.EVENT_READ, self.from_reader_err)

    # -- the reader ------------------------------------------------------

    def tell_reader(self, word):
        try:
            self.reader.stdin.write(word + b"\n")
            self.reader.stdin.flush()
        except (OSError, ValueError):
            pass

    def stop_reader(self):
        """The reader's stop: the word, then the end of its stdin, which is
        its signal to go. Still pkexec asking, before the reader's first
        line (the user's own process then, the dialog up), it is signalled
        too, which takes the dialog away."""
        if self.stop_at is not None:
            return
        self.tell_reader(b"stop")
        try:
            self.reader.stdin.close()
        except OSError:
            pass
        if self.status is None:
            try:
                os.kill(self.reader.pid, signal.SIGTERM)
            except OSError:
                pass
        self.stop_at = time.monotonic()

    def from_reader(self, stream):
        try:
            n = stream.readinto(self.buf)
        except OSError:
            n = 0
        if not n:
            return False
        view = memoryview(self.buf)
        start = 0
        while start < n:
            end = self.buf.find(b"\n", start, n)
            if end < 0:
                self.line += view[start:n]
                if len(self.line) > LINE_MAX:
                    self.scrub(self.line)
                break
            self.line += view[start:end + 1]
            self.pass_on(self.line)
            self.scrub(self.line)
            start = end + 1
        view.release()
        self.buf[:n] = bytes(n)
        return True

    def pass_on(self, line):
        if line.startswith(STATUS):
            self.status = bytes(line)
        if self.client is None:
            return
        try:
            self.client.sendall(line)
        except OSError:
            self.drop_client()

    def from_reader_err(self, stream):
        try:
            chunk = stream.read(4096)
        except OSError:
            chunk = b""
        if not chunk:
            self.sel.unregister(stream)
            return True
        # pkexec's or the reader's complaint: its last line, for the bar.
        self.err_line += chunk
        lines = [line for line in bytes(self.err_line).split(b"\n") if line.strip()]
        if lines:
            self.complaint = lines[-1][-300:]
        del self.err_line[:max(0, len(self.err_line) - 600)]
        return True

    @staticmethod
    def scrub(buf):
        buf[:] = bytes(len(buf))
        del buf[:]

    # -- the bar ---------------------------------------------------------

    def accept(self, server):
        try:
            conn, _ = server.accept()
        except OSError:
            return True
        if not is_bar(conn, self.bar_dir):
            conn.close()
            return True
        # Paused until this bar says otherwise, whatever the last one said.
        self.drop_client()
        conn.settimeout(2)
        self.client = conn
        self.seen_bar = True
        self.sel.register(conn, selectors.EVENT_READ, self.from_bar)
        try:
            conn.sendall(self.status if self.status else b'{"type": "hold"}\n')
        except OSError:
            self.drop_client()
        return True

    def drop_client(self):
        """The bar gone, or replaced: the reader paused until a bar says
        otherwise."""
        if self.client is None:
            return
        try:
            self.sel.unregister(self.client)
        except (KeyError, ValueError):
            pass
        self.client.close()
        self.client = None
        del self.control[:]
        self.tell_reader(b"pause")

    def from_bar(self, conn):
        try:
            data = conn.recv(256)
        except OSError:
            data = b""
        if not data:
            self.drop_client()
            return True
        self.control += data
        while True:
            end = self.control.find(b"\n")
            if end < 0:
                if len(self.control) > 64:
                    del self.control[:]
                break
            word = bytes(self.control[:end]).strip()
            del self.control[:end + 1]
            if word == b"stop":
                self.stop_reader()
            elif word in CONTROL:
                self.tell_reader(word)
        return True

    # -- the loop --------------------------------------------------------

    def run(self):
        while True:
            if STOPPING:
                self.stop_reader()
            timeout = 0.5
            if self.stop_at is not None:
                left = STOP_GRACE - (time.monotonic() - self.stop_at)
                if left <= 0:
                    break
                timeout = min(timeout, left)
            for key, _ in self.sel.select(timeout):
                if not key.data(key.fileobj):
                    return self.end()
        return self.end()

    def end(self):
        try:
            code = self.reader.wait(timeout=STOP_GRACE)
        except subprocess.TimeoutExpired:
            code = None
        if code is not None and code < 0:
            code = 128 - code
        # A reader that ended before the bar came (pkexec finding no agent
        # answers at once) is still said to the bar that comes for it.
        if self.client is None and not self.seen_bar:
            self.server.settimeout(5)
            try:
                while self.client is None:
                    conn, _ = self.server.accept()
                    if is_bar(conn, self.bar_dir):
                        self.client = conn
                    else:
                        conn.close()
            except OSError:
                pass
        if self.client is not None:
            message = {"type": "exit", "code": code if code is not None else -1,
                       "complaint": self.complaint.decode(errors="replace").strip()}
            try:
                self.client.sendall(json.dumps(message).encode() + b"\n")
            except OSError:
                pass
        return 0


def main(argv):
    args = argv[1:]
    if len(args) < 6 or args[2] != "--needs" or args[4] != "--":
        print(USAGE, file=sys.stderr)
        return 2
    sock_path, bar_dir, reader_path, command = args[0], args[1], args[3], args[5:]
    directory = private_dir(os.path.dirname(sock_path))
    if directory is None:
        say(f"{os.path.dirname(sock_path)} is not this user's alone")
        return 2
    lock = claim(directory)
    if lock is None:
        say("another holds the reader")
        return 0

    def stop(signum, _frame):
        STOPPING.append(signum)

    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop)
    pid_file = os.path.join(directory, "hold.pid")
    server = None
    try:
        try:
            os.unlink(sock_path)
        except FileNotFoundError:
            pass
        old = os.umask(0o177)
        try:
            server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            server.bind(sock_path)
        finally:
            os.umask(old)
        server.listen(4)
        with open(pid_file, "w") as fh:
            fh.write(f"{os.getpid()}\n")
        if not os.access(reader_path, os.X_OK):
            return not_installed(server)
        try:
            reader = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, bufsize=0)
        except OSError as e:
            say(f"{command[0]}: {e.strerror or e}")
            return not_installed(server, code=127)
        return Hold(server, reader, bar_dir).run()
    finally:
        if server is not None:
            server.close()
        for path in (sock_path, pid_file):
            try:
                os.unlink(path)
            except OSError:
                pass
        os.close(lock)


def not_installed(server, code=NOT_INSTALLED):
    """No reader to hold: said to the bar that comes for it, briefly."""
    server.settimeout(5)
    try:
        conn, _ = server.accept()
    except OSError:
        return code
    with conn:
        try:
            conn.sendall(json.dumps({"type": "exit", "code": code, "complaint": ""}).encode() + b"\n")
        except OSError:
            pass
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
