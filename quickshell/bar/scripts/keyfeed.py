#!/usr/bin/env python3
"""Emit one JSON line per key press, read straight from the evdev devices.

This is the only part of the key visualiser that needs a permission, and the
permission is membership of the input group rather than root or a polkit agent.
Everything above it is ordinary QML.

The output is a line protocol on purpose. It is the seam that lets this be
replaced by a Rust binary later without the overlay changing at all: anything
that prints the same lines will do.

Physical keys are reported, not composed characters. That is what a key
visualiser is for, and it is also the only honest answer here: Hangul syllables
are assembled by fcitx5 from several keystrokes and never appear as one.

Names, not symbols. Whether Escape is drawn as a word or as U+238B is a question
about the overlay, and keeping it there means a reader that prints these same
lines can be swapped in without carrying a table of glyphs with it.
"""

import json
import os
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

    A table written out here would be a copy that drifts the first time a code
    is added. The header is installed by linux-api-headers and is the same file
    the kernel was built from.
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


def emit(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    devices = open_keyboards()
    if not devices:
        emit({"type": "error", "reason": "no readable keyboard; is this user in the input group?"})
        return 1
    emit({"type": "ready", "devices": len(devices)})

    held = set()
    # Periodic rescan picks up reconnected (e.g. Bluetooth) keyboards.
    next_scan = time.monotonic() + 5

    while True:
        readable, _, _ = select.select(list(devices), [], [], 1.0)

        for fd in readable:
            try:
                data = os.read(fd, EVENT_SIZE * 64)
            except BlockingIOError:
                continue
            except OSError:
                os.close(fd)
                devices.pop(fd, None)
                next_scan = 0
                continue

            for offset in range(0, len(data) - EVENT_SIZE + 1, EVENT_SIZE):
                _, _, etype, code, value = struct.unpack(
                    FORMAT, data[offset:offset + EVENT_SIZE])
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
                emit({"type": "key", "mods": mods, "key": label(code)})

        now = time.monotonic()
        if now >= next_scan:
            next_scan = now + 5
            devices.update(open_keyboards(frozenset(devices.values())))
            if not devices:
                emit({"type": "error", "reason": "every keyboard went away"})


if __name__ == "__main__":
    sys.exit(main())
