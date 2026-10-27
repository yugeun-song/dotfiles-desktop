"""Tests for quickshell/bar/scripts/keyfeed-hold.py, run whole: root's reader
is a stand-in that logs its control words and sends a key per resume, and
each bar is a python3 run with `-p BAR_DIR` as the bar's quickshell is, let
in by KEYFEED_HOLD_CLIENTS. Nothing here runs pkexec or reads a keyboard.
"""

import json
import os
import pathlib
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest

REPO = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = REPO / "quickshell/bar/scripts/keyfeed-hold.py"

# The reader: ready at once, a key for each resume, every word logged; it
# ends at stop or the end of its input, or at once with READER_EXIT.
READER = r"""#!/usr/bin/env python3
import json, os, sys
log = os.environ["HOLD_LOG"]
def emit(obj):
    os.write(1, (json.dumps(obj) + "\n").encode())
if os.environ.get("READER_EXIT"):
    print("Error executing command as another user: Not authorized", file=sys.stderr, flush=True)
    sys.exit(int(os.environ["READER_EXIT"]))
emit({"type": "ready", "devices": 1})
for line in sys.stdin:
    word = line.strip()
    with open(log, "a") as fh:
        fh.write(word + "\n")
    if word == "stop":
        break
    if word == "resume":
        emit({"type": "key", "mods": ["Ctrl"], "key": "K"})
with open(log, "a") as fh:
    fh.write("ended\n")
"""

# A bar: connects, sends what it is given in argv after --say, and prints
# every line it gets until the socket closes or it is killed.
BAR = r"""
import socket, sys, time
path = sys.argv[sys.argv.index("--socket") + 1]
say = sys.argv[sys.argv.index("--say") + 1:] if "--say" in sys.argv else []
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
for _ in range(50):
    try:
        s.connect(path)
        break
    except OSError:
        time.sleep(0.05)
got = b""
for word in say:
    if word.startswith("sleep:"):
        time.sleep(float(word[6:]))
    elif word == "await:ready":
        # As the bar does: steered once the reader has said it is up.
        s.settimeout(5)
        while b'"ready"' not in got:
            data = s.recv(4096)
            if not data:
                break
            got += data
        sys.stdout.buffer.write(got)
        sys.stdout.flush()
    else:
        s.sendall(word.encode() + b"\n")
s.settimeout(float(sys.argv[sys.argv.index("--for") + 1]) if "--for" in sys.argv else 3)
try:
    while True:
        data = s.recv(4096)
        if not data:
            break
        sys.stdout.buffer.write(data)
        sys.stdout.flush()
except OSError:
    pass
"""


class HoldTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.tmp.name)
        self.bar_dir = self.dir / "bar"
        self.bar_dir.mkdir()
        self.run_dir = self.dir / "run"
        self.run_dir.mkdir(mode=0o700)
        self.sock = self.run_dir / "keyfeed" / "socket"
        self.reader = self.dir / "reader"
        self.reader.write_text(READER)
        self.reader.chmod(0o755)
        self.log = self.dir / "control.log"
        self.env = dict(os.environ, HOLD_LOG=str(self.log), KEYFEED_HOLD_CLIENTS="python3")
        self.procs = []

    def tearDown(self):
        for proc in self.procs:
            if proc.poll() is None:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except OSError:
                    pass
                proc.wait()
        self.tmp.cleanup()

    def hold(self, env=None, needs=None):
        proc = subprocess.Popen(
            [sys.executable, "-I", "-S", str(SCRIPT), str(self.sock), str(self.bar_dir),
             "--needs", str(needs or self.reader), "--", str(self.reader)],
            env={**self.env, **(env or {})}, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, start_new_session=True)
        self.procs.append(proc)
        deadline = time.monotonic() + 5
        while not self.sock.is_socket() and time.monotonic() < deadline and proc.poll() is None:
            time.sleep(0.02)
        return proc

    def bar(self, *say, bar_dir=None, seconds=1.5):
        args = ["python3", "-c", BAR, "-p", str(bar_dir or self.bar_dir), "--socket", str(self.sock),
                "--for", str(seconds)]
        if say:
            args += ["--say", *say]
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, text=True, start_new_session=True)
        self.procs.append(proc)
        return proc

    # The reader's lines as a bar gets them; "hold" says only that it is not
    # up yet, which depends on who came first.
    def lines(self, proc, timeout=10):
        out, _ = proc.communicate(timeout=timeout)
        got = [json.loads(line) for line in out.splitlines() if line.strip()]
        return [m for m in got if m.get("type") != "hold"]

    def control(self):
        try:
            return self.log.read_text().split()
        except OSError:
            return []

    def wait_for(self, predicate, timeout=5):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if predicate():
                return True
            time.sleep(0.05)
        return False

    def test_the_bar_gets_the_reader_and_steers_it(self):
        self.hold()
        got = self.lines(self.bar("resume"))
        self.assertEqual([m["type"] for m in got], ["ready", "key"])
        self.assertEqual(got[1]["key"], "K")

    def test_a_bar_that_goes_leaves_the_reader_paused(self):
        self.hold()
        self.lines(self.bar("resume", seconds=0.5))
        self.assertTrue(self.wait_for(lambda: self.control()[-1:] == ["pause"]), self.control())

    def test_the_next_bar_is_told_the_reader_is_ready_and_steers_it_again(self):
        self.hold()
        self.lines(self.bar(seconds=0.5))
        got = self.lines(self.bar("resume"))
        self.assertEqual([m["type"] for m in got], ["ready", "key"])

    def test_keys_with_no_bar_reach_no_later_bar(self):
        self.hold()
        # Resumed, then gone before the key comes back: the key is dropped.
        first = self.bar("resume", seconds=0.01)
        first.communicate(timeout=5)
        time.sleep(0.3)
        got = self.lines(self.bar(seconds=0.5))
        self.assertEqual([m["type"] for m in got], ["ready"])

    def test_only_the_bar_may_connect(self):
        self.hold()
        other = self.dir / "elsewhere"
        other.mkdir()
        self.assertEqual(self.lines(self.bar("resume", bar_dir=other)), [])
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
            conn.settimeout(2)
            conn.connect(str(self.sock))
            self.assertEqual(conn.recv(64), b"")
        self.assertNotIn("resume", self.control())

    def test_stop_ends_the_reader_and_the_holder_and_says_how(self):
        holder = self.hold()
        got = self.lines(self.bar("await:ready", "stop"))
        self.assertEqual(got[-1], {"type": "exit", "code": 0, "complaint": ""})
        holder.communicate(timeout=10)
        self.assertEqual(holder.returncode, 0)
        self.assertEqual(self.control()[-2:], ["stop", "ended"])
        self.assertEqual(sorted(p.name for p in self.sock.parent.iterdir()), ["lock"])

    def test_a_reader_that_ends_says_why(self):
        self.hold(env={"READER_EXIT": "127"})
        got = self.lines(self.bar(seconds=2))
        self.assertEqual(got[-1]["type"], "exit")
        self.assertEqual(got[-1]["code"], 127)
        self.assertEqual(got[-1]["complaint"], "Error executing command as another user: Not authorized")

    def test_a_reader_not_installed_is_said(self):
        missing = self.dir / "absent"
        self.hold(needs=missing)
        got = self.lines(self.bar(seconds=2))
        self.assertEqual(got, [{"type": "exit", "code": 69, "complaint": ""}])

    def test_a_second_holder_leaves_the_first_be(self):
        first = self.hold()
        second = subprocess.run(
            [sys.executable, "-I", "-S", str(SCRIPT), str(self.sock), str(self.bar_dir),
             "--needs", str(self.reader), "--", str(self.reader)],
            env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(second.returncode, 0)
        self.assertIsNone(first.poll())
        self.assertEqual([m["type"] for m in self.lines(self.bar())], ["ready"])

    def test_a_signal_stops_the_reader_and_cleans_up(self):
        holder = self.hold()
        self.lines(self.bar("await:ready", seconds=0.3))
        holder.send_signal(signal.SIGTERM)
        holder.communicate(timeout=10)
        self.assertEqual(holder.returncode, 0)
        self.assertIn("ended", self.control())
        self.assertFalse(self.sock.exists())

    def test_a_directory_others_can_enter_is_refused(self):
        self.sock.parent.mkdir(mode=0o755)
        self.sock.parent.chmod(0o755)
        holder = self.hold()
        holder.communicate(timeout=10)
        self.assertEqual(holder.returncode, 2)
        self.assertFalse(self.log.exists())

    def test_usage(self):
        for args in ([], [str(self.sock), str(self.bar_dir), "--", str(self.reader)]):
            done = subprocess.run([sys.executable, "-I", "-S", str(SCRIPT), *args],
                                  capture_output=True, text=True, timeout=10)
            self.assertEqual(done.returncode, 2)
            self.assertIn("usage", done.stderr)


if __name__ == "__main__":
    unittest.main()
