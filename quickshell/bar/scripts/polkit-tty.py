#!/usr/bin/env python3
"""Runs a command so that its pkexec asks for the password in the terminal
the command was started from, else by polkit's own dialog, as the user asked
(2026-10-26). With no terminal this simply becomes the command. The camera
keys' script (hypr/scripts/camera.sh) runs its helper through this.

    polkit-tty.py COMMAND [ARG...]

COMMAND is what runs pkexec (a shell, camera-switch), never pkexec itself:
pkexec asks for its parent, and polkit asks the agent registered for that
very process (pid and start time) before the session's. So pkttyagent is
registered on the terminal for this process, which then execs COMMAND and
so keeps its pid and start time. The password goes from the terminal to
polkit's helper, never through here.

A terminal counts when someone reads it with this process in its
foreground: a pseudo-terminal, or a console in text mode. A key's command
inherits the compositor's console, in graphics mode: COMMAND then gets
/dev/null for stdin, so that nothing under it asks there. The agent goes
once pkexec has come and gone, when the process ends, or when nobody
answers. stdout is COMMAND's alone, and so is the exit status.
"""

import ctypes
import fcntl
import os
import select
import shutil
import signal
import struct
import subprocess
import sys
import time

# pkttyagent registers in milliseconds (about 7 measured); the tests wait
# less.
REGISTER_TIMEOUT = float(os.environ.get("POLKIT_TTY_TIMEOUT") or 5.0)
POLL = 0.05
# How long something other than pkexec runs under the process, with no
# pkexec seen, before pkexec is taken as passed: longer than the moment a
# shell's forked child takes to become pkexec.
PASSED_AFTER = 1.0
# A prompt left unanswered this long is given up, so that an agent never
# waits on a terminal left alone.
ASK_CAP = 300.0
# linux/kd.h: a console's mode, text or graphics.
KDGETMODE = 0x4B3B
KD_TEXT = 0
# prctl(2): an agent whose watcher was killed goes with it.
PR_SET_PDEATHSIG = 1

USAGE = "usage: polkit-tty.py COMMAND [ARG...]"


def say(text):
    print(f"polkit-tty: {text}", file=sys.stderr, flush=True)


def at_terminal(fd=0):
    """Whether someone reads the terminal on fd, with this process in its
    foreground. Another session's terminal fails tcgetpgrp."""
    try:
        if not os.isatty(fd) or os.tcgetpgrp(fd) != os.getpgrp():
            return False
        if os.ttyname(fd).startswith("/dev/pts/"):
            return True
        mode = fcntl.ioctl(fd, KDGETMODE, b"\0\0\0\0")
    except OSError:
        return False
    return struct.unpack("i", mode)[0] == KD_TEXT


def started(pid):
    """The process's start time, which with its pid names it to polkit; None
    once it has ended (a zombie included)."""
    try:
        with open(f"/proc/{pid}/stat", "rb") as f:
            # The command name is in parentheses and may hold any character.
            fields = f.read().rsplit(b")", 1)[1].split()
        if fields[0] in (b"Z", b"X"):
            return None
        return int(fields[19])
    except (OSError, IndexError, ValueError):
        return None


def descendants(pid):
    """Every process under pid, from the kernel's per-thread children lists."""
    found, stack = [], [pid]
    while stack:
        parent = stack.pop()
        try:
            tids = os.listdir(f"/proc/{parent}/task")
        except OSError:
            continue
        for tid in tids:
            try:
                with open(f"/proc/{parent}/task/{tid}/children") as f:
                    kids = [int(k) for k in f.read().split()]
            except (OSError, ValueError):
                continue
            found.extend(kids)
            stack.extend(kids)
    return found


def is_pkexec(pid):
    """By argv[0]: pkexec is root's, so its /proc/<pid>/exe is not ours to
    read, and its cmdline changes to the program's once it has run it."""
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            argv0 = f.read().split(b"\0", 1)[0]
    except OSError:
        return False
    return os.path.basename(argv0) == b"pkexec"


def become(args, stdin_null=False):
    """Execs COMMAND in place of this process; returns only on failure."""
    if stdin_null:
        null = os.open(os.devnull, os.O_RDONLY)
        os.dup2(null, 0)
        os.close(null)
    # Python ignores these; the command expects them as usual.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    signal.signal(signal.SIGXFSZ, signal.SIG_DFL)
    try:
        os.execvp(args[0], args)
    except OSError as e:
        say(f"{args[0]}: {e.strerror or e}")
    return 127


class Agent:
    """pkttyagent registered for (pid, start), prompting on this process's
    terminal, which it opens itself: its stdio is /dev/null."""

    def __init__(self, program, pid, start):
        self.proc = None
        parent = os.getpid()

        def bind():
            try:
                ctypes.CDLL(None).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
            except (OSError, AttributeError):
                pass
            if os.getppid() != parent:
                os._exit(0)

        r, w = os.pipe()
        try:
            self.proc = subprocess.Popen(
                [program, "--process", f"{pid},{start}", "--notify-fd", str(w)],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                pass_fds=(w,), preexec_fn=bind)
        except OSError:
            pass
        os.close(w)
        try:
            self.registered = self.proc is not None and self._wait(r)
        finally:
            os.close(r)
        if not self.registered:
            self.stop()

    def _wait(self, fd):
        """pkttyagent closes the notify fd once polkit has it as the agent.
        One that failed closes it too, by ending: so it is still up a moment
        after."""
        poller = select.poll()
        poller.register(fd, select.POLLIN | select.POLLHUP)
        deadline = time.monotonic() + REGISTER_TIMEOUT
        while time.monotonic() < deadline:
            if poller.poll(50):
                time.sleep(0.05)
                return self.proc.poll() is None
            if self.proc.poll() is not None:
                return False
        return False

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def stop(self):
        if self.proc is None:
            return
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        self.proc = None


def watch(pid, start, agent):
    """Keeps the agent until pkexec has come and gone under the process, the
    process has ended, or nobody has answered. A pkexec that needs no
    password becomes its program at once and can come and go between two
    looks: something under the process that is not pkexec, for a while with
    no pkexec seen, means the same."""
    asked = False
    other_since = None
    deadline = time.monotonic() + ASK_CAP
    try:
        while agent.alive() and time.monotonic() < deadline and started(pid) == start:
            under = descendants(pid)
            if any(is_pkexec(k) for k in under):
                asked = True
            elif asked:
                break
            elif under:
                other_since = other_since or time.monotonic()
                if time.monotonic() - other_since >= PASSED_AFTER:
                    break
            else:
                other_since = None
            time.sleep(POLL)
    finally:
        agent.stop()


def keep_watch(program, pid, start, ack):
    """The watcher of a run at a terminal, a grandchild of the process that
    becomes COMMAND: COMMAND is never left a child of ours to reap. Its
    stdio is /dev/null, or a caller reading COMMAND's output (camera.sh's
    $(...)) would wait for it too; the terminal stays its controlling one,
    which is all pkttyagent needs."""
    try:
        null = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 1, 2):
            os.dup2(null, fd)
        os.closerange(3, ack)
        os.closerange(ack + 1, os.sysconf("SC_OPEN_MAX"))
        agent = Agent(program, pid, start)
        os.close(ack)
        if agent.registered:
            watch(pid, start, agent)
    finally:
        os._exit(0)


def ask_here(args):
    """At a terminal: an agent on it for this process, then COMMAND."""
    program = shutil.which("pkttyagent")
    me = os.getpid()
    start = started(me)
    if program is None or start is None:
        return become(args)
    r, w = os.pipe()
    first = os.fork()
    if first == 0:
        os.close(r)
        try:
            if os.fork() == 0:
                keep_watch(program, me, start, w)
        finally:
            os._exit(0)
    os.close(w)
    os.waitpid(first, 0)
    # Closed by the watcher once the agent is up, or given up on.
    select.select([r], [], [], REGISTER_TIMEOUT + 1)
    os.close(r)
    return become(args)


def main(argv):
    args = argv[1:]
    if args[:1] == ["--"]:
        args = args[1:]
    if not args or os.path.basename(args[0]) == "pkexec":
        print(USAGE, file=sys.stderr)
        return 2
    if at_terminal():
        return ask_here(args)
    if os.isatty(0):
        return become(args, stdin_null=True)
    return become(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
