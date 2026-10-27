#!/usr/bin/env python3
"""The keyboard-side readings the bar shows: Caps Lock's LED, the input
method, and whether the focused window's terminal is asking for a password.

One process for the three. They were a bash loop and two python helpers,
each with an interpreter of its own: twice the private memory of this one
(10 MB against 5, side by side on 2026-10-17, most of it sitting in swap),
twice the CPU with a terminal watched, and wakeups that never lined up.
Here the Caps Lock pass rides on the terminal watch's ticks while both run.

stdout, one reading per line, printed on change:
  caps 0 | caps 1 | caps -     Caps Lock: any keyboard's LED lit, or none;
                               `-` when no LED node can be read (a keyboard
                               mid-replug; not the same as off)
  ime STATE<TAB>NAME | ime -   fcitx5's state and engine, also printed for
                               every `ask`; `-` when fcitx5 or the session bus
                               does not answer
  echo secret | echo clear     the watched window's terminal reads with its
                               echo off, line by line: a password prompt.
                               Said once for every `pid`, then on change
stdin, one request per line:
  ask       an input-method reading now
  pid N     the window process whose terminals to watch; 0 stops the watch
`--pid N` on the command line starts with that watch, so a helper started
over says nothing of a pid it was not told. The end of stdin ends it.

A part that fails leaves the others running. The bus going away is
answered with `ime -` and a reconnection, 2 s doubling to a minute, in a
thread of its own: a call fcitx5 is slow to answer waits up to two seconds,
and the terminal watch, which a password's privacy depends on, must not
wait with it.

Standard library only, and only the modules these parts need: urllib.parse
for a D-Bus address's %XX escapes would have cost 1.4 MB, glob as much.
"""

import _thread
import os
import select
import socket
import struct
import sys
import termios
import time

# --------------------------------------------------------------------------
# Output, from the main thread and the input method's.
# --------------------------------------------------------------------------


class Out:
    """Whole lines, one writer at a time; a reader gone ends the helper."""

    def __init__(self, fd=1):
        self.fd = fd
        self.lock = _thread.allocate_lock()

    def say(self, line):
        data = (line + "\n").encode()
        with self.lock:
            try:
                while data:
                    data = data[os.write(self.fd, data):]
            except OSError:
                os._exit(0)


# --------------------------------------------------------------------------
# Caps Lock.
# --------------------------------------------------------------------------

LEDS = "/sys/class/leds"
CAPS_EVERY = 0.2


def caps_reading(leds=LEDS):
    """"1" when any keyboard's Caps Lock LED is lit, "0" when none is, "-"
    when no LED node can be read. Hyprland gives every keyboard the same LED
    state. The nodes are looked up again at every reading: a replugged
    keyboard's LED comes back under another name. The kernel announces no
    change of an LED's brightness, so this is a poll."""
    try:
        names = os.listdir(leds)
    except OSError:
        return "-"
    found = False
    for name in sorted(names):
        if not name.endswith("::capslock"):
            continue
        try:
            with open(os.path.join(leds, name, "brightness"), "rb") as fh:
                value = fh.read().strip()
        except OSError:
            continue
        if not value:
            continue
        found = True
        if value != b"0":
            return "1"
    return "0" if found else "-"


# --------------------------------------------------------------------------
# The input method, over the session bus.
# --------------------------------------------------------------------------
# fcitx5-hangul keeps the name "hangul" while toggling conversion, so the
# state (2 = converting) is what tells Hangul from latin. With no focused
# input context fcitx5 reports state 0 and an empty name; that is a valid
# reading. Only a call fcitx5 did not answer is a no-reading.
#
# fcitx5 announces no state change on D-Bus (its controller has no such
# signal), so this polls. The wire protocol is spoken directly, the subset
# two argumentless calls need: fcitx5-remote three times a second had cost
# 1.1% of a core with its forks. The key overlay asks at every letter it is
# about to draw: a poll can be a whole interval old, and the first letter
# typed after a switch to Hangul came out latin about half the time.

IME_EVERY = 0.3
BACKOFF_FIRST, BACKOFF_LAST = 2.0, 60.0

FCITX = ("org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1")
BUS = ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus")

METHOD_CALL, METHOD_RETURN, ERROR = 1, 2, 3
PATH, INTERFACE, MEMBER, REPLY_SERIAL, DESTINATION, SIGNATURE = 1, 2, 3, 5, 6, 8

# A reply this large is not one to these calls: the stream is out of step.
MAX_MESSAGE = 1 << 20

HEX = "0123456789abcdefABCDEF"


def unescape(value):
    """A D-Bus address value, whose bytes outside a safe set come as %XX; a
    malformed escape is kept as it is."""
    parts = value.split("%")
    out = bytearray(parts[0].encode())
    for part in parts[1:]:
        if len(part) >= 2 and part[0] in HEX and part[1] in HEX:
            out.append(int(part[:2], 16))
            out += part[2:].encode()
        else:
            out += b"%" + part.encode()
    return out.decode("utf-8", "replace")


def addresses():
    """The session bus's unix addresses, in the order given."""
    raw = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
    if not raw:
        runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        raw = f"unix:path={runtime}/bus"
    out = []
    for entry in raw.split(";"):
        kind, _, params = entry.partition(":")
        if kind != "unix":
            continue
        opts = dict(p.split("=", 1) for p in params.split(",") if "=" in p)
        if "path" in opts:
            out.append(unescape(opts["path"]))
        elif "abstract" in opts:
            out.append("\0" + unescape(opts["abstract"]))
    return out


def marshal_call(serial, destination, path, interface, member):
    """A method call with no arguments, little-endian."""
    msg = bytearray(struct.pack("<cBBBII", b"l", METHOD_CALL, 0, 1, 0, serial))
    msg += b"\0\0\0\0"

    def align(n):
        msg.extend(b"\0" * (-len(msg) % n))

    for code, sig, value in ((PATH, "o", path), (INTERFACE, "s", interface),
                             (MEMBER, "s", member), (DESTINATION, "s", destination)):
        align(8)
        msg.append(code)
        msg.extend(b"\x01" + sig.encode() + b"\0")
        data = value.encode()
        align(4)
        msg.extend(struct.pack("<I", len(data)) + data + b"\0")
    struct.pack_into("<I", msg, 12, len(msg) - 16)
    # The header ends on an 8-byte boundary, body or not.
    align(8)
    return bytes(msg)


def header_fields(data, fmt, length):
    fields = {}
    pos, end = 16, 16 + length
    while pos < end:
        pos += -pos % 8
        code = data[pos]
        size = data[pos + 1]
        sig = data[pos + 2:pos + 2 + size].decode()
        pos += 3 + size
        if sig in ("s", "o"):
            pos += -pos % 4
            (n,) = struct.unpack_from(fmt + "I", data, pos)
            value = data[pos + 4:pos + 4 + n].decode(errors="replace")
            pos += 5 + n
        elif sig == "u":
            pos += -pos % 4
            (value,) = struct.unpack_from(fmt + "I", data, pos)
            pos += 4
        elif sig == "g":
            n = data[pos]
            value = data[pos + 1:pos + 1 + n].decode()
            pos += 2 + n
        else:
            raise ValueError(f"a header field of type {sig!r}")
        fields[code] = value
    return fields


def decode(signature, body, fmt):
    """The single basic value these replies carry; None for anything else."""
    if signature == "i":
        return struct.unpack_from(fmt + "i", body)[0]
    if signature in ("s", "o"):
        (n,) = struct.unpack_from(fmt + "I", body)
        return body[4:4 + n].decode(errors="replace")
    return None


class Bus:
    def __init__(self, sock):
        self.sock = sock
        self.serial = 0
        self.pending = b""

    def fill(self, n):
        while len(self.pending) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("the bus closed the connection")
            self.pending += chunk

    def next_message(self):
        """One whole message, taken off the stream only once it is complete,
        so a timeout halfway leaves the stream where it was."""
        self.fill(16)
        if self.pending[0:1] not in (b"l", b"B"):
            raise ConnectionError("not a D-Bus message")
        fmt = "<" if self.pending[0:1] == b"l" else ">"
        body_len, _serial, fields_len = struct.unpack_from(fmt + "III", self.pending, 4)
        header_end = 16 + fields_len + (-(16 + fields_len) % 8)
        total = header_end + body_len
        if total > MAX_MESSAGE:
            raise ConnectionError("a message too large to be a reply here")
        self.fill(total)
        data, self.pending = self.pending[:total], self.pending[total:]
        fields = header_fields(data, fmt, fields_len)
        return data[1], fields.get(REPLY_SERIAL), fields.get(SIGNATURE, ""), data[header_end:], fmt

    def call(self, destination, path, interface, member):
        """The reply's value, or None for an error reply (no such service,
        a failed call). Signals and late replies to earlier calls are passed
        over."""
        self.serial += 1
        serial = self.serial
        self.sock.sendall(marshal_call(serial, destination, path, interface, member))
        while True:
            kind, reply_to, signature, body, fmt = self.next_message()
            if reply_to != serial:
                continue
            if kind == ERROR:
                return None
            if kind == METHOD_RETURN:
                return decode(signature, body, fmt)


def connect():
    for address in addresses():
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(2.0)
        try:
            sock.connect(address)
        except OSError:
            sock.close()
            continue
        # EXTERNAL: the server reads the uid off the socket; it is sent hex-encoded.
        sock.sendall(b"\0AUTH EXTERNAL " + str(os.getuid()).encode().hex().encode() + b"\r\n")
        reply = b""
        while not reply.endswith(b"\r\n"):
            chunk = sock.recv(512)
            if not chunk:
                break
            reply += chunk
        if not reply.startswith(b"OK "):
            sock.close()
            continue
        sock.sendall(b"BEGIN\r\n")
        bus = Bus(sock)
        bus.call(*BUS, "Hello")
        return bus
    return None


def ask(bus, member):
    try:
        return bus.call(*FCITX, member)
    except TimeoutError:
        return None


class Ime:
    """fcitx5's readings, from a thread of its own. Requests come through a
    pipe, so one is never lost to a reading already under way."""

    def __init__(self, out, interval=IME_EVERY, first=BACKOFF_FIRST):
        self.out = out
        self.interval = interval
        self.first = first
        self.last = None
        self.wake_r, self.wake_w = os.pipe()
        os.set_blocking(self.wake_w, False)

    def ask(self):
        try:
            os.write(self.wake_w, b"!")
        except BlockingIOError:
            pass

    def wait(self, timeout):
        """Sleep up to timeout; True as soon as a request comes."""
        if not select.select([self.wake_r], [], [], max(0.0, timeout))[0]:
            return False
        os.read(self.wake_r, 4096)
        return True

    def say(self, line, force=False):
        if line != self.last or force:
            self.out.say("ime " + line)
            self.last = line

    def start(self):
        _thread.start_new_thread(self.run, ())

    def run(self):
        delay = self.first
        while True:
            try:
                bus = connect()
            except Exception:
                bus = None
            if bus is not None:
                delay = self.first
                try:
                    self.poll(bus)
                except Exception:
                    pass
                finally:
                    try:
                        bus.sock.close()
                    except OSError:
                        pass
            self.say("-")
            # The wait before the next attempt still answers a request, with
            # the no-reading it is.
            until = time.monotonic() + delay
            while (left := until - time.monotonic()) > 0:
                if self.wait(left):
                    self.say("-", force=True)
            if bus is None:
                delay = min(delay * 2, BACKOFF_LAST)

    def poll(self, bus):
        """Readings until the connection fails."""
        last_state = None
        name = ""
        n = 0
        requested = False
        while True:
            state = ask(bus, "State")
            # The name is read again on a state change, on a request and every
            # tenth pass (about 3 s), so an engine switch with no state change
            # still shows, and a request is answered with both fresh.
            if requested or state != last_state or n % 10 == 0:
                fresh = ask(bus, "CurrentInputMethod")
                # The last non-empty name stays: the engine cannot change while
                # no input context is focused.
                if fresh:
                    name = fresh
            last_state = state
            n += 1
            self.say("-" if state is None else f"{state}\t{name}", force=requested)
            requested = self.wait(self.interval)


# --------------------------------------------------------------------------
# The terminal watch: the key overlay's guard (KeyFeed.qml) for prompts that
# are no window of their own: sudo, su, ssh, passwd, `read -s`.
# --------------------------------------------------------------------------
# A program reading a password turns the terminal's echo off and keeps it
# line-buffered (ICANON on); a full-screen program (an editor, a pager, the
# shell's own line editor) turns both off. Those two flags are all that is
# read, never what is typed, so this learns nothing a program of the user's
# could not see the same way. The terminals are the ones the window's
# process and its descendants hold as stdin, stdout or stderr: looked up
# again every second, their flags read every 25 ms. A terminal is opened
# only to read its flags and closed at once, so none is held open past its
# shell. A window with no terminal is not ticked at all.

FLAGS_EVERY = 0.025
TREE_EVERY = 1.0


def children_map():
    """Parent pid to child pids, from every process in /proc: the way when
    the kernel keeps no children lists (CONFIG_PROC_CHILDREN)."""
    kids = {}
    try:
        names = os.listdir("/proc")
    except OSError:
        return kids
    for name in names:
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/stat", "rb") as fh:
                stat = fh.read()
        except OSError:
            continue
        # The command name sits in parentheses and may hold spaces.
        rest = stat[stat.rfind(b")") + 2:].split()
        if len(rest) > 1 and rest[1].isdigit():
            kids.setdefault(int(rest[1]), []).append(int(name))
    return kids


def children_of(pid):
    """pid's children, from its threads' children lists: a window's tree is
    a few processes, where reading every process in /proc took 0.7% of a
    core at one look a second."""
    try:
        tasks = os.listdir(f"/proc/{pid}/task")
    except OSError:
        return []
    kids = []
    for tid in tasks:
        try:
            with open(f"/proc/{pid}/task/{tid}/children", "rb") as fh:
                kids.extend(int(x) for x in fh.read().split() if x.isdigit())
        except OSError:
            continue
    return kids


HAS_CHILDREN = os.path.exists(f"/proc/self/task/{os.getpid()}/children")


def terminals(pid, has_children=None):
    """The pseudo-terminals pid and its descendants have on fds 0 to 2."""
    if has_children is None:
        has_children = HAS_CHILDREN
    kids = None if has_children else children_map()
    found = set()
    todo = [pid]
    seen = set()
    while todo:
        p = todo.pop()
        if p in seen:
            continue
        seen.add(p)
        todo.extend(children_of(p) if kids is None else kids.get(p, ()))
        for fd in (0, 1, 2):
            try:
                target = os.readlink(f"/proc/{p}/fd/{fd}")
            except OSError:
                continue
            if target.startswith("/dev/pts/"):
                found.add(target)
    return found


def asking(path):
    """True while the terminal at path reads with echo off, line by line."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK | os.O_CLOEXEC)
    except OSError:
        return False
    try:
        lflag = termios.tcgetattr(fd)[3]
    except termios.error:
        return False
    finally:
        os.close(fd)
    return not lflag & termios.ECHO and bool(lflag & termios.ICANON)


class Watch:
    def __init__(self, out):
        self.out = out
        self.pid = 0
        self.ttys = set()
        self.said = None
        self.next_tree = 0.0
        self.next_flags = 0.0

    def target(self, pid):
        self.pid = pid
        self.ttys = set()
        self.said = None
        self.next_tree = 0.0

    def deadlines(self):
        if not self.pid:
            return [] if self.said == "clear" else [0.0]
        if self.ttys:
            return [self.next_tree, self.next_flags]
        return [self.next_tree]

    def tick(self, now, slack):
        if not self.pid:
            self.say("clear")
            return
        if now >= self.next_tree - slack:
            self.ttys = terminals(self.pid)
            self.next_tree = now + TREE_EVERY
            self.next_flags = 0.0
        if not self.ttys:
            self.say("clear")
            return
        if now >= self.next_flags - slack:
            self.say("secret" if any(asking(t) for t in self.ttys) else "clear")
            self.next_flags = now + FLAGS_EVERY

    def say(self, word):
        if word != self.said:
            self.out.say("echo " + word)
            self.said = word


# --------------------------------------------------------------------------
# Each part on its own: a fault in one is that part's no-reading, and its
# next turn tries again. The watch's is "secret", which pauses the key
# reader rather than let a password through.


def caps_turn(out, leds, said):
    try:
        reading = caps_reading(leds)
    except Exception:
        reading = "-"
    if reading != said:
        out.say("caps " + reading)
    return reading


def watch_turn(watch, now, slack):
    try:
        watch.tick(now, slack)
    except Exception:
        watch.say("secret")
        watch.next_flags = now + FLAGS_EVERY
        watch.next_tree = now + TREE_EVERY


def main():
    out = Out()
    caps_every = float(os.environ.get("INPUTSTATE_CAPS_INTERVAL", CAPS_EVERY))
    leds = os.environ.get("INPUTSTATE_LEDS", LEDS)
    ime = Ime(out, float(os.environ.get("INPUTSTATE_IME_INTERVAL", IME_EVERY)),
              float(os.environ.get("INPUTSTATE_IME_RETRY", BACKOFF_FIRST)))
    ime.start()
    watch = Watch(out)
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--pid" and args[1].isdigit():
        watch.target(int(args[1]))
    # A reading falls due early by up to one terminal tick rather than wake
    # the process on its own: Caps Lock rides on the watch's ticks.
    slack = FLAGS_EVERY
    control = 0
    pending = b""
    caps_said = None
    next_caps = 0.0
    while True:
        now = time.monotonic()
        timeout = max(0.0, min([next_caps] + watch.deadlines()) - now)
        if select.select([control], [], [], timeout)[0]:
            data = os.read(control, 4096)
            if not data:
                os._exit(0)
            pending += data
            while b"\n" in pending:
                line, pending = pending.split(b"\n", 1)
                words = line.split()
                if words == [b"ask"]:
                    ime.ask()
                elif len(words) == 2 and words[0] == b"pid" and words[1].isdigit():
                    watch.target(int(words[1]))
        now = time.monotonic()
        if now >= next_caps - slack:
            caps_said = caps_turn(out, leds, caps_said)
            next_caps = now + caps_every
        watch_turn(watch, now, slack)


if __name__ == "__main__":
    sys.exit(main())
