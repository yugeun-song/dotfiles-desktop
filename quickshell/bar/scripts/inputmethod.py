#!/usr/bin/env python3
"""Print the input method's state on change: <state>TAB<im name>, or `-` when
fcitx5 does not answer.

fcitx5-hangul keeps the name "hangul" while toggling conversion, so the state
(2 = converting) is what tells Hangul from latin. With no focused input
context fcitx5 reports state 0 and an empty name; that is a valid reading.
Only a call fcitx5 did not answer is a no-reading.

fcitx5 announces no state change on D-Bus (its controller has no such
signal), so this polls, as the shell script before it did by running
fcitx5-remote three times a second: a fork and an exec each, a steady 1.1% of
a core with its children. This keeps one connection to the session bus and
asks over it, which costs about a tenth of that. The D-Bus wire protocol is
spoken here directly, in the small subset two argumentless calls need, so
nothing beyond the standard library is required (python3 already runs the
key overlay's reader).

Exits when the bus cannot be reached or drops the connection; the bar's
supervisor (services/Ime.qml) starts it again with a backoff.
"""

import os
import socket
import struct
import sys
import time
import urllib.parse

FCITX = ("org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1")
BUS = ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus")

METHOD_CALL, METHOD_RETURN, ERROR = 1, 2, 3
PATH, INTERFACE, MEMBER, REPLY_SERIAL, DESTINATION, SIGNATURE = 1, 2, 3, 5, 6, 8

# A reply this large is not one to these calls: the stream is out of step.
MAX_MESSAGE = 1 << 20


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
            out.append(urllib.parse.unquote(opts["path"]))
        elif "abstract" in opts:
            out.append("\0" + urllib.parse.unquote(opts["abstract"]))
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


def main():
    interval = float(os.environ.get("INPUTMETHOD_POLL_INTERVAL", "0.3"))
    try:
        bus = connect()
    except OSError:
        bus = None
    if bus is None:
        return 1

    last = None
    last_state = None
    name = ""
    n = 0
    while True:
        state = ask(bus, "State")
        # The name is read again on a state change and every tenth pass
        # (about 3 s), so an engine switch with no state change still shows.
        if state != last_state or n % 10 == 0:
            fresh = ask(bus, "CurrentInputMethod")
            # The last non-empty name stays: the engine cannot change while
            # no input context is focused.
            if fresh:
                name = fresh
        last_state = state
        n += 1

        line = "-" if state is None else f"{state}\t{name}"
        if line != last:
            print(line, flush=True)
            last = line
        time.sleep(interval)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ConnectionError, OSError, ValueError, struct.error):
        sys.exit(1)
