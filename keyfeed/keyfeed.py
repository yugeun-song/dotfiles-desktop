#!/usr/bin/python3 -I
"""Emit one JSON line per key press, read straight from the evdev devices.

The key overlay's reader, and the only part of it that reads a keyboard. It
runs as root through pkexec, which asks for an administrator's password each
time the bar starts it (the polkit action next to this file): membership of
the input group, which it needed before, let every program of the user read
every keyboard, the lock screen, the greeter and the text consoles included,
overlay on or off. As root it opens the keyboards, then drops to nobody with
the input group alone (still able to open a keyboard plugged in later) and
can be traced or dumped by nobody but root.

What it reads goes nowhere but these lines on stdout, a pipe to the bar,
which keeps at most five chords, each for under a second. It opens no socket
and no file but the devices, the kernel's key header and sysfs, writes no
file and logs no key.

The bar steers it with lines on stdin. It starts paused and sends nothing
until `resume`; `pause` holds the keys back again (the bar pauses it while
the session is locked), so a password typed into the lock screen never
leaves this process, whose buffer is zeroed and whose memory nobody but
root can read. `stop`, or the end of stdin, ends
it: the bar cannot signal a process of root's, so that is the off switch.
With --vt N it also sends nothing while another console is in front: the
evdev devices carry the keys typed into a text console's login or another
session's greeter too.

A line protocol on purpose: anything that prints the same lines (a Rust
binary, later) can replace this without the overlay changing. Physical keys,
not composed characters: that is what a key overlay shows, and fcitx5
assembles a Hangul syllable from several keystrokes anyway. Names, not
symbols: how Escape is drawn is the overlay's question, so a replacement
reader carries no glyph table.
"""

import grp
import json
import os
import pwd
import re
import select
import signal
import struct
import sys
import time

# struct input_event on 64-bit Linux; size asserted so a mismatch fails loudly.
FORMAT = "llHHi"
EVENT_SIZE = struct.calcsize(FORMAT)
assert EVENT_SIZE == 24, EVENT_SIZE

EV_KEY = 0x01
KEY_A = 30

MODIFIERS = {
    29: "Ctrl", 97: "Ctrl",
    42: "Shift", 54: "Shift",
    56: "Alt", 100: "Alt",
    125: "Super", 126: "Super",
}

# Overrides; anything else is the KEY_ name without prefix, capitalised.
PRETTY = {
    "KEY_ESC": "Esc", "KEY_SPACE": "Space", "KEY_ENTER": "Enter",
    "KEY_BACKSPACE": "Backspace", "KEY_TAB": "Tab", "KEY_CAPSLOCK": "Caps",
    "KEY_DELETE": "Del", "KEY_INSERT": "Ins", "KEY_HOME": "Home",
    "KEY_END": "End", "KEY_PAGEUP": "PgUp", "KEY_PAGEDOWN": "PgDn",
    "KEY_UP": "Up", "KEY_DOWN": "Down", "KEY_LEFT": "Left", "KEY_RIGHT": "Right",
    "KEY_MINUS": "-", "KEY_EQUAL": "=", "KEY_LEFTBRACE": "[",
    "KEY_RIGHTBRACE": "]", "KEY_BACKSLASH": "\\", "KEY_SEMICOLON": ";",
    "KEY_APOSTROPHE": "'", "KEY_GRAVE": "`", "KEY_COMMA": ",",
    "KEY_DOT": ".", "KEY_SLASH": "/",
    # Korean 104-key: these sit where US boards have right Alt and right Ctrl.
    "KEY_HANGEUL": "한/영", "KEY_HANJA": "한자",
    "KEY_PRINT": "PrtSc", "KEY_SYSRQ": "PrtSc", "KEY_SCROLLLOCK": "ScrLk",
    "KEY_PAUSE": "Pause", "KEY_MENU": "Menu", "KEY_COMPOSE": "Menu",
}


def key_names():
    """codes to KEY_ names, read from the kernel header rather than hardcoded.

    A table written out here would drift the first time a code is added. The
    header is the kernel's userspace API, installed by linux-api-headers; a code
    newer than it prints as #<code> (label).
    """
    path = "/usr/include/linux/input-event-codes.h"
    names = {}
    try:
        with open(path) as fh:
            for line in fh:
                m = re.match(r"#define\s+(KEY_\w+)\s+(0x[0-9a-fA-F]+|\d+)\b", line)
                if m:
                    names.setdefault(int(m.group(2), 0), m.group(1))
    except OSError:
        pass
    return names


NAMES = key_names()


def label(code):
    raw = NAMES.get(code)
    if raw is None:
        return f"#{code}"
    if raw in PRETTY:
        return PRETTY[raw]
    body = raw[4:]
    if len(body) == 1:
        return body
    if body.startswith("F") and body[1:].isdigit():
        return body
    return body.capitalize()


def is_keyboard(event_name):
    """True when the device reports the letter keys.

    Reading the capability bitmap in sysfs rather than issuing EVIOCGBIT keeps
    this to a file read. A device that carries KEY_A is a keyboard; a mouse with
    a few buttons or a lid switch is not, and both sit in the same directory.
    """
    path = f"/sys/class/input/{event_name}/device/capabilities/key"
    try:
        with open(path) as fh:
            words = fh.read().split()
    except OSError:
        return False
    # The bitmap prints as space-separated 64-bit words, most significant first.
    bits = 0
    for w in words:
        bits = (bits << 64) | int(w, 16)
    return bool(bits >> KEY_A & 1)


def open_keyboards(skip=frozenset()):
    """Open the keyboards not in skip (paths already open).

    The rescan used to open every keyboard again and close the copy it already
    had: a sysfs read, an open and a close per keyboard every five seconds.
    """
    found = {}
    try:
        entries = sorted(os.listdir("/dev/input"))
    except OSError:
        return found
    for name in entries:
        if not name.startswith("event"):
            continue
        path = f"/dev/input/{name}"
        if path in skip:
            continue
        if not is_keyboard(name):
            continue
        try:
            found[os.open(path, os.O_RDONLY | os.O_NONBLOCK)] = path
        except OSError:
            # Not fatal, and not worth logging on every rescan.
            continue
    return found


def decode(buf, n, held):
    """The key presses among the first n bytes of buf, as payloads. held is
    the set of modifier codes down, kept across calls. The bytes are zeroed
    once read."""
    out = []
    for offset in range(0, n - EVENT_SIZE + 1, EVENT_SIZE):
        _, _, etype, code, value = struct.unpack_from(FORMAT, buf, offset)
        if etype != EV_KEY:
            continue

        if code in MODIFIERS:
            if value == 1:
                held.add(code)
            elif value == 0:
                held.discard(code)
            continue

        # Skip auto-repeat (value 2).
        if value != 1:
            continue

        mods = []
        for name in ("Super", "Ctrl", "Alt", "Shift"):
            if any(MODIFIERS.get(c) == name for c in held):
                mods.append(name)
        out.append({"type": "key", "mods": mods, "key": label(code)})
    buf[:n] = bytes(n)
    return out


def emit(payload):
    """One line, written straight to the pipe: through sys.stdout it would
    also sit in the buffered writer's buffer, which outlives the write."""
    data = (json.dumps(payload, ensure_ascii=False) + "\n").encode()
    while data:
        data = data[os.write(1, data):]


def undumpable():
    """Keep this process's memory to itself.

    It holds raw key events, and freed memory is not cleared: a core dump
    would keep the last of them on disk (systemd-coredump stores the whole
    process). A process that is not dumpable leaves no core and cannot be
    traced by an unprivileged one. Asked again after the drop below, since a
    change of user resets it. Best effort: where prctl is missing the reader
    runs as before.
    """
    try:
        import ctypes
        PR_SET_DUMPABLE = 4
        ctypes.CDLL(None, use_errno=True).prctl(PR_SET_DUMPABLE, 0, 0, 0, 0)
    except (OSError, AttributeError):
        pass


def drop_privileges():
    """From root to nobody with the input group alone, once the keyboards
    are open. The group, not root, is what a keyboard plugged in later
    takes; nothing else here needs privilege. Without an input group the
    keyboards already open are all there will be. A no-op when not root
    (a test, or a hand run by a user in the input group)."""
    if os.geteuid() != 0:
        return
    try:
        gid = grp.getgrnam("input").gr_gid
    except KeyError:
        gid = None
    try:
        nobody = pwd.getpwnam("nobody")
        uid = nobody.pw_uid
        gid = nobody.pw_gid if gid is None else gid
    except KeyError:
        uid = 65534
        gid = 65534 if gid is None else gid
    os.setgroups([])
    os.setgid(gid)
    os.setuid(uid)
    undumpable()


def foreground_vt():
    """The console in front, as "tty3", or None where sysfs cannot say."""
    try:
        with open("/sys/class/tty/tty0/active") as fh:
            return fh.read().strip() or None
    except OSError:
        return None


class Control:
    """The bar's lines on stdin: resume, pause, stop. Unknown lines are
    ignored, so a newer bar can say more."""

    def __init__(self, fd):
        self.fd = fd
        self.pending = b""
        self.open = False

    def read(self):
        """False once the bar is done: stop, or the end of its input."""
        try:
            data = os.read(self.fd, 4096)
        except OSError:
            return False
        if not data:
            return False
        self.pending += data
        while b"\n" in self.pending:
            line, self.pending = self.pending.split(b"\n", 1)
            word = line.strip()
            if word == b"stop":
                return False
            if word == b"resume":
                self.open = True
            elif word == b"pause":
                self.open = False
        return True


def parse_args(argv):
    """--vt N: the console the session is on (the bar's XDG_VTNR)."""
    vt = None
    if len(argv) == 2 and argv[0] == "--vt" and argv[1].isdigit():
        vt = "tty" + argv[1]
    elif argv:
        raise SystemExit("usage: keyfeed [--vt N]")
    return vt


def main(argv=()):
    session_vt = parse_args(list(argv))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    # A bar that went away mid-line: the next write fails, and that ends it.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    undumpable()

    devices = open_keyboards()
    drop_privileges()
    control = Control(sys.stdin.fileno())
    # Kept running without a keyboard rather than exiting: each start costs
    # the user a password, and one can still come (Bluetooth, a dock).
    missing = not devices
    if missing:
        emit({"type": "error", "reason": "no keyboard to read yet"})
    else:
        emit({"type": "ready", "devices": len(devices)})

    held = set()
    # Periodic rescan picks up reconnected (e.g. Bluetooth) keyboards.
    next_scan = time.monotonic() + 5
    # Raw events are read into this one buffer, which decode() zeroes: a
    # fresh bytes object per read would leave each batch in freed memory,
    # which Python does not clear.
    buf = bytearray(EVENT_SIZE * 64)

    while True:
        readable, _, _ = select.select([control.fd] + list(devices), [], [], 1.0)

        for fd in readable:
            if fd == control.fd:
                if not control.read():
                    return 0
                continue
            try:
                n = os.readv(fd, [buf])
            except BlockingIOError:
                continue
            except OSError:
                os.close(fd)
                devices.pop(fd, None)
                next_scan = 0
                continue

            # Decoded even when nothing is sent, so the modifiers held stay
            # right and the buffer is zeroed all the same.
            presses = decode(buf, n, held)
            if control.open and (session_vt is None or foreground_vt() in (None, session_vt)):
                for payload in presses:
                    emit(payload)

        now = time.monotonic()
        if now >= next_scan:
            next_scan = now + 5
            devices.update(open_keyboards(frozenset(devices.values())))
            if devices and missing:
                missing = False
                emit({"type": "ready", "devices": len(devices)})
            elif not devices and not missing:
                missing = True
                emit({"type": "error", "reason": "every keyboard went away"})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
