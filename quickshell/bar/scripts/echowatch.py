#!/usr/bin/python3 -I
"""Say whether the focused window's terminal is asking for a password.

The key overlay's guard (KeyFeed.qml) for prompts that are no window of
their own: sudo, su, ssh, passwd, `read -s`. A program reading a password
turns the terminal's echo off and keeps it line-buffered (ICANON on); a
full-screen program (an editor, a pager, the shell's own line editor) turns
both off. Those two flags are all that is read, never what is typed, so
this learns nothing a program of the user's could not see the same way.

stdin: "pid N", the focused window's process (0: none). stdout: "secret" or
"clear", once at the start of each pid and at every change. The terminals
are the ones the window's process and its descendants hold as stdin,
stdout or stderr: looked up again every second, their flags read every
25 ms. A terminal is opened only to read its flags and closed at once, so
none is held open past its shell. Ends with its stdin.
"""

import os
import select
import sys
import termios
import time

FLAGS_EVERY = 0.025
TREE_EVERY = 1.0


def children_map():
    """Parent pid to child pids, from /proc."""
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
        if len(rest) > 1:
            kids.setdefault(int(rest[1]), []).append(int(name))
    return kids


def terminals(pid):
    """The pseudo-terminals pid and its descendants have on fds 0 to 2."""
    found = set()
    kids = children_map()
    todo = [pid]
    seen = set()
    while todo:
        p = todo.pop()
        if p in seen:
            continue
        seen.add(p)
        todo.extend(kids.get(p, ()))
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


def say(word):
    data = (word + "\n").encode()
    while data:
        data = data[os.write(1, data):]


def main():
    control = sys.stdin.fileno()
    pending = b""
    pid = 0
    ttys = set()
    said = None
    next_tree = 0.0
    while True:
        timeout = FLAGS_EVERY if pid else None
        readable, _, _ = select.select([control], [], [], timeout)
        if readable:
            data = os.read(control, 4096)
            if not data:
                return 0
            pending += data
            while b"\n" in pending:
                line, pending = pending.split(b"\n", 1)
                words = line.split()
                if len(words) == 2 and words[0] == b"pid" and words[1].isdigit():
                    pid = int(words[1])
                    said = None
                    next_tree = 0.0
        if not pid:
            ttys = set()
            if said != "clear":
                say("clear")
                said = "clear"
            continue
        now = time.monotonic()
        if now >= next_tree:
            ttys = terminals(pid)
            next_tree = now + TREE_EVERY
        word = "secret" if any(asking(t) for t in ttys) else "clear"
        if word != said:
            say(word)
            said = word


if __name__ == "__main__":
    sys.exit(main())
