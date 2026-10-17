"""Tests for quickshell/bar/scripts/inputstate.py, the bar's input helper:
Caps Lock's LEDs, the input method over D-Bus, and the terminal watch.

The D-Bus client is checked two ways: against a private dbus-daemon started
here with no service directory, so asking for fcitx5 can never start a second
one (a second fcitx5 has emptied XIM_SERVERS before), and over a socketpair
fed hand-built replies for what a daemon will not readily produce (a signal
in between, a late reply, a message cut in half by a timeout). The LEDs are
a directory of stand-ins. The terminal watch runs on a pseudo-terminal of
its own: a child process holds it as stdin, and its flags are set as a
password prompt, a full-screen program or a plain command would set them.
Nothing is typed into it and nothing is read from it.
"""

import importlib.util
import os
import pathlib
import select
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time
import unittest
import urllib.parse
from unittest import mock

# The script is imported from the tree install.sh mirrors, and a bytecode
# cache written beside it went out with the next install.
sys.dont_write_bytecode = True

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "quickshell/bar/scripts/inputstate.py"
spec = importlib.util.spec_from_file_location("inputstate", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

BUS_CONFIG = """<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>{listen}</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <!-- Without the receive side, the reference daemon delivers no reply at
         all, to dbus-send either. -->
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
"""


def reply(reply_to, signature="", body=b"", kind=m.METHOD_RETURN):
    """A message as a daemon sends it: little-endian, the header padded to 8."""
    msg = bytearray(struct.pack("<cBBBII", b"l", kind, 0, 1, len(body), 1000 + (reply_to or 0)))
    msg += b"\0\0\0\0"

    def align(n):
        msg.extend(b"\0" * (-len(msg) % n))

    if reply_to is not None:
        align(8)
        msg += bytes([m.REPLY_SERIAL]) + b"\x01u\0"
        align(4)
        msg += struct.pack("<I", reply_to)
    if signature:
        align(8)
        msg += bytes([m.SIGNATURE]) + b"\x01g\0" + bytes([len(signature)]) + signature.encode() + b"\0"
    struct.pack_into("<I", msg, 12, len(msg) - 16)
    align(8)
    return bytes(msg) + body


def string(value):
    data = value.encode()
    return struct.pack("<I", len(data)) + data + b"\0"


class Lines:
    """The helper's stdout, read with a deadline: a line, or None. Read off
    the descriptor with a buffer of its own: a buffered readline took two
    lines written together, and select, which sees only the descriptor, then
    waited out its deadline over the one left in the file object."""

    def __init__(self, stream):
        self.fd = stream.fileno()
        self.buffer = b""

    def next(self, timeout=5.0):
        end = time.monotonic() + timeout
        while b"\n" not in self.buffer:
            left = end - time.monotonic()
            if left <= 0 or not select.select([self.fd], [], [], left)[0]:
                return None
            data = os.read(self.fd, 4096)
            if not data:
                return None
            self.buffer += data
        line, self.buffer = self.buffer.split(b"\n", 1)
        return line.decode()

    def tagged(self, tag, timeout=5.0):
        """The next line of one kind, the others passed over."""
        end = time.monotonic() + timeout
        while (left := end - time.monotonic()) > 0:
            line = self.next(left)
            if line is None:
                return None
            if line.split(" ", 1)[0] == tag:
                return line
        return None


def start(env=None, args=()):
    """The script as the bar runs it."""
    proc = subprocess.Popen([sys.executable, "-I", "-S", str(SCRIPT), *args],
                            env=dict(os.environ, **(env or {})), stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, text=True, bufsize=1)
    return proc, Lines(proc.stdout)


def stop(proc):
    if proc.poll() is None:
        proc.kill()
    proc.wait()
    proc.stdout.close()
    proc.stdin.close()


def tell(proc, line):
    proc.stdin.write(line + "\n")
    proc.stdin.flush()


# --------------------------------------------------------------------------
# The input method.
# --------------------------------------------------------------------------


class Addresses(unittest.TestCase):
    def test_path_with_escapes(self):
        with mock.patch.dict(os.environ, {"DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/a%20b,guid=x"}):
            self.assertEqual(m.addresses(), ["/run/user/1000/a b"])

    def test_abstract_and_order(self):
        env = {"DBUS_SESSION_BUS_ADDRESS": "tcp:host=x,port=1;unix:abstract=/tmp/dbus-1;unix:path=/run/bus"}
        with mock.patch.dict(os.environ, env):
            self.assertEqual(m.addresses(), ["\0/tmp/dbus-1", "/run/bus"])

    def test_fallback(self):
        env = {"DBUS_SESSION_BUS_ADDRESS": "", "XDG_RUNTIME_DIR": "/run/user/7"}
        with mock.patch.dict(os.environ, env):
            self.assertEqual(m.addresses(), ["/run/user/7/bus"])

    def test_unescape_reads_as_urllib_did(self):
        # The helper dropped urllib.parse for its memory; what it reads must
        # not change, malformed escapes and non-ASCII included.
        for value in ["/run/user/1000/bus", "a%20b", "%2Fx%2f", "bad%zz", "%4", "end%", "%%41",
                      "%C3%A9t%C3%A9", "%FF", "ü%20x"]:
            self.assertEqual(m.unescape(value), urllib.parse.unquote(value), value)


class Marshal(unittest.TestCase):
    def test_header_parses_back(self):
        msg = m.marshal_call(7, "org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1", "State")
        self.assertEqual(len(msg) % 8, 0)
        self.assertEqual(struct.unpack_from("<I", msg, 4)[0], 0)
        self.assertEqual(struct.unpack_from("<I", msg, 8)[0], 7)
        length = struct.unpack_from("<I", msg, 12)[0]
        self.assertEqual(m.header_fields(msg, "<", length), {
            m.PATH: "/controller", m.INTERFACE: "org.fcitx.Fcitx.Controller1",
            m.MEMBER: "State", m.DESTINATION: "org.fcitx.Fcitx5"})


class Stream(unittest.TestCase):
    def setUp(self):
        self.ours, self.theirs = socket.socketpair()
        self.ours.settimeout(0.3)
        self.bus = m.Bus(self.ours)

    def tearDown(self):
        self.ours.close()
        self.theirs.close()

    def test_int_reply_after_a_signal(self):
        self.theirs.sendall(reply(None, kind=4) + reply(1, "i", struct.pack("<i", 2)))
        self.assertEqual(self.bus.call(*m.FCITX, "State"), 2)

    def test_late_reply_is_passed_over(self):
        self.theirs.sendall(reply(5, "s", string("old")) + reply(1, "s", string("hangul")))
        self.assertEqual(self.bus.call(*m.FCITX, "CurrentInputMethod"), "hangul")

    def test_error_reply(self):
        self.theirs.sendall(reply(1, "s", string("org.freedesktop.DBus.Error.ServiceUnknown"), kind=m.ERROR))
        self.assertIsNone(self.bus.call(*m.FCITX, "State"))

    def test_timeout_mid_message_keeps_the_stream(self):
        whole = reply(1, "i", struct.pack("<i", 1))
        self.theirs.sendall(whole[:10])
        with self.assertRaises(TimeoutError):
            self.bus.call(*m.FCITX, "State")
        self.assertEqual(self.bus.pending, whole[:10])
        # The rest of the late reply, then the answer to the next call.
        self.theirs.sendall(whole[10:] + reply(2, "i", struct.pack("<i", 2)))
        self.assertEqual(self.bus.call(*m.FCITX, "State"), 2)

    def test_closed_bus(self):
        self.theirs.close()
        with self.assertRaises(ConnectionError):
            self.bus.call(*m.FCITX, "State")


class Requests(unittest.TestCase):
    def setUp(self):
        self.ime = m.Ime(m.Out(os.open(os.devnull, os.O_WRONLY)))

    def test_a_request_ends_the_wait(self):
        self.ime.ask()
        start_ = time.monotonic()
        self.assertTrue(self.ime.wait(5))
        self.assertLess(time.monotonic() - start_, 1)

    def test_silence_waits_it_out(self):
        start_ = time.monotonic()
        self.assertFalse(self.ime.wait(0.1))
        self.assertGreaterEqual(time.monotonic() - start_, 0.1)

    def test_requests_made_meanwhile_are_one(self):
        for _ in range(3):
            self.ime.ask()
        self.assertTrue(self.ime.wait(1))
        self.assertFalse(self.ime.wait(0.05))


class PrivateBus(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("dbus-daemon"):
            raise unittest.SkipTest("dbus-daemon is not installed")

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.pids = []

    def tearDown(self):
        for pid in self.pids:
            try:
                os.kill(pid, 15)
            except ProcessLookupError:
                pass
        shutil.rmtree(self.dir, ignore_errors=True)

    def daemon(self, listen="unix:tmpdir=/tmp"):
        config = os.path.join(self.dir, f"bus{len(self.pids)}.conf")
        with open(config, "w") as fh:
            fh.write(BUS_CONFIG.format(listen=listen))
        out = subprocess.run(["dbus-daemon", f"--config-file={config}", "--fork", "--print-address=1", "--print-pid=1"],
                             capture_output=True, text=True, check=True).stdout.split("\n")
        self.pids.append(int(out[1]))
        return out[0].strip()

    def test_hello_and_a_missing_fcitx5(self):
        with mock.patch.dict(os.environ, {"DBUS_SESSION_BUS_ADDRESS": self.daemon()}):
            bus = m.connect()
        self.assertIsNotNone(bus)
        self.assertRegex(bus.call(*m.BUS, "GetId"), r"^[0-9a-f]{32}$")
        self.assertIsNone(bus.call(*m.FCITX, "State"))
        bus.sock.close()

    def test_no_answer_and_a_request_answered_though_nothing_changed(self):
        proc, out = start({"DBUS_SESSION_BUS_ADDRESS": self.daemon(), "INPUTSTATE_IME_INTERVAL": "0.05"})
        try:
            self.assertEqual(out.tagged("ime"), "ime -")
            self.assertIsNone(out.tagged("ime", 0.5), "an unchanged reading printed unasked")
            tell(proc, "ask")
            self.assertEqual(out.tagged("ime"), "ime -")
        finally:
            stop(proc)

    def test_without_a_bus_the_rest_goes_on(self):
        # Once the helper ended here and took Caps Lock with it.
        proc, out = start({"DBUS_SESSION_BUS_ADDRESS": f"unix:path={self.dir}/none",
                           "INPUTSTATE_LEDS": self.dir})
        try:
            lines = [out.next(), out.next(), out.next()]
            self.assertEqual(sorted(lines), ["caps -", "echo clear", "ime -"])
            # An ask while the bus is away is answered at once, with the
            # no-reading it is: the key overlay waits for that answer.
            tell(proc, "ask")
            started = time.monotonic()
            self.assertEqual(out.tagged("ime", 1), "ime -")
            self.assertLess(time.monotonic() - started, 0.5)
            self.assertIsNone(proc.poll())
        finally:
            stop(proc)

class FakeFcitx:
    """Just enough of a session bus on a unix socket, with fcitx5 on it: the
    handshake, Hello, and fcitx5's two calls. close() drops the bus and
    every connection, as a bus that goes away does."""

    def __init__(self, path, state=2, name="hangul"):
        self.path, self.state, self.name = path, state, name
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(path)
        self.server.listen(4)
        self.conns = []
        threading.Thread(target=self.serve, daemon=True).start()

    def serve(self):
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            self.conns.append(conn)
            threading.Thread(target=self.talk, args=(conn,), daemon=True).start()

    def talk(self, conn):
        try:
            data = b""
            while not data.endswith(b"\r\n"):
                chunk = conn.recv(512)
                if not chunk:
                    return
                data += chunk
            conn.sendall(b"OK 0123456789abcdef0123456789abcdef\r\n")
            data = b""
            while True:
                while b"BEGIN\r\n" in data or len(data) < 16:
                    if b"BEGIN\r\n" in data:
                        data = data.split(b"BEGIN\r\n", 1)[1]
                        continue
                    chunk = conn.recv(65536)
                    if not chunk:
                        return
                    data += chunk
                body_len, serial, fields_len = struct.unpack_from("<III", data, 4)
                total = 16 + fields_len + (-(16 + fields_len) % 8) + body_len
                while len(data) < total:
                    chunk = conn.recv(65536)
                    if not chunk:
                        return
                    data += chunk
                member = m.header_fields(data[:total], "<", fields_len).get(m.MEMBER)
                data = data[total:]
                if member == "Hello":
                    conn.sendall(reply(serial, "s", string(":1.7")))
                elif member == "State":
                    conn.sendall(reply(serial, "i", struct.pack("<i", self.state)))
                elif member == "CurrentInputMethod":
                    conn.sendall(reply(serial, "s", string(self.name)))
                else:
                    conn.sendall(reply(serial, "s", string("org.freedesktop.DBus.Error.UnknownMethod"), kind=m.ERROR))
        except OSError:
            return

    def close(self):
        self.server.close()
        for conn in self.conns:
            try:
                conn.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            conn.close()
        os.unlink(self.path)


class Reconnection(unittest.TestCase):
    """The input method's fallback: a bus that is missing or goes away reads
    as no answer, and is tried again, while the other parts go on."""

    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.path = os.path.join(self.dir, "bus")
        self.env = {"DBUS_SESSION_BUS_ADDRESS": f"unix:path={self.path}", "INPUTSTATE_IME_RETRY": "0.2",
                    "INPUTSTATE_IME_INTERVAL": "0.05", "INPUTSTATE_LEDS": self.dir}

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_a_bus_that_comes_later_is_used(self):
        proc, out = start(self.env)
        try:
            self.assertEqual(out.tagged("ime"), "ime -")
            bus = FakeFcitx(self.path)
            self.assertEqual(out.tagged("ime", 3), "ime 2\thangul")
            bus.close()
        finally:
            stop(proc)

    def test_a_bus_that_goes_away_is_reported_then_used_again(self):
        bus = FakeFcitx(self.path)
        proc, out = start(self.env)
        try:
            self.assertEqual(out.tagged("ime"), "ime 2\thangul")
            bus.close()
            self.assertEqual(out.tagged("ime", 3), "ime -")
            # The rest went on meanwhile.
            tell(proc, "pid 0")
            self.assertEqual(out.tagged("echo", 2), "echo clear")
            bus = FakeFcitx(self.path, state=1, name="keyboard-us")
            self.assertEqual(out.tagged("ime", 3), "ime 1\tkeyboard-us")
            bus.close()
        finally:
            stop(proc)


# --------------------------------------------------------------------------
# Caps Lock.
# --------------------------------------------------------------------------


class Caps(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def led(self, name, value):
        # Renamed into place: a sysfs read is whole, and the helper reading
        # a file truncated and not yet written once took it for no LED.
        os.makedirs(os.path.join(self.dir, name), exist_ok=True)
        path = os.path.join(self.dir, name, "brightness")
        with open(path + ".new", "w") as fh:
            fh.write(f"{value}\n")
        os.replace(path + ".new", path)

    def test_no_led_is_unknown(self):
        self.assertEqual(m.caps_reading(self.dir), "-")
        self.assertEqual(m.caps_reading(os.path.join(self.dir, "missing")), "-")

    def test_other_leds_do_not_count(self):
        self.led("input3::numlock", 1)
        self.led("input3::scrolllock", 1)
        self.assertEqual(m.caps_reading(self.dir), "-")

    def test_off_and_on(self):
        self.led("input2::capslock", 0)
        self.assertEqual(m.caps_reading(self.dir), "0")
        self.led("input3::capslock", 1)
        self.assertEqual(m.caps_reading(self.dir), "1")

    def test_an_unreadable_led_is_passed_over(self):
        self.led("input2::capslock", 1)
        os.chmod(os.path.join(self.dir, "input2::capslock", "brightness"), 0)
        if os.access(os.path.join(self.dir, "input2::capslock", "brightness"), os.R_OK):
            self.skipTest("running as root: nothing is unreadable")
        self.assertEqual(m.caps_reading(self.dir), "-")
        self.led("input3::capslock", 0)
        self.assertEqual(m.caps_reading(self.dir), "0")

    def test_a_replugged_keyboard_is_found_under_its_new_name(self):
        self.led("input3::capslock", 1)
        self.assertEqual(m.caps_reading(self.dir), "1")
        os.rename(os.path.join(self.dir, "input3::capslock"), os.path.join(self.dir, "input25::capslock"))
        self.assertEqual(m.caps_reading(self.dir), "1")

    def test_printed_on_change_only(self):
        self.led("input3::capslock", 0)
        proc, out = start({"INPUTSTATE_LEDS": self.dir, "INPUTSTATE_CAPS_INTERVAL": "0.05",
                           "DBUS_SESSION_BUS_ADDRESS": f"unix:path={self.dir}/none"})
        try:
            self.assertEqual(out.tagged("caps"), "caps 0")
            self.assertIsNone(out.tagged("caps", 0.3), "an unchanged reading printed again")
            self.led("input3::capslock", 1)
            self.assertEqual(out.tagged("caps", 1), "caps 1")
            shutil.rmtree(os.path.join(self.dir, "input3::capslock"))
            self.assertEqual(out.tagged("caps", 1), "caps -")
        finally:
            stop(proc)

    def test_a_reading_that_fails_is_unknown(self):
        out = m.Out(os.open(os.devnull, os.O_WRONLY))
        with mock.patch.object(m, "caps_reading", side_effect=RuntimeError):
            self.assertEqual(m.caps_turn(out, self.dir, "1"), "-")


# --------------------------------------------------------------------------
# The terminal watch.
# --------------------------------------------------------------------------


class Terminal(unittest.TestCase):
    def setUp(self):
        self.master, self.slave = os.openpty()
        self.child = subprocess.Popen(["sleep", "30"], stdin=self.slave,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def tearDown(self):
        self.child.kill()
        self.child.wait()
        os.close(self.slave)
        os.close(self.master)

    def flags(self, echo, icanon):
        attrs = termios.tcgetattr(self.slave)
        lflag = attrs[3]
        lflag = lflag | termios.ECHO if echo else lflag & ~termios.ECHO
        lflag = lflag | termios.ICANON if icanon else lflag & ~termios.ICANON
        attrs[3] = lflag
        termios.tcsetattr(self.slave, termios.TCSANOW, attrs)

    def asking(self):
        return any(m.asking(t) for t in m.terminals(self.child.pid))

    def test_the_childs_terminal_is_found(self):
        self.assertEqual(m.terminals(self.child.pid), {os.ttyname(self.slave)})

    def test_a_password_prompt(self):
        self.flags(echo=False, icanon=True)
        self.assertTrue(self.asking())

    def test_a_plain_command(self):
        self.flags(echo=True, icanon=True)
        self.assertFalse(self.asking())

    def test_a_full_screen_program(self):
        self.flags(echo=False, icanon=False)
        self.assertFalse(self.asking())

    def test_found_through_a_parent(self):
        # The focused window is the terminal emulator; the prompt is its
        # child's. This process is the child's parent here.
        self.flags(echo=False, icanon=True)
        self.assertTrue(any(m.asking(t) for t in m.terminals(os.getpid())))

    def test_the_tree_walk_finds_what_the_full_scan_finds(self):
        # The children lists walk a window's tree; without them (a kernel
        # with no CONFIG_PROC_CHILDREN) every process in /proc is read.
        if not m.HAS_CHILDREN:
            self.skipTest("this kernel keeps no children lists")
        self.assertEqual(m.terminals(os.getpid(), has_children=True), m.terminals(os.getpid(), has_children=False))
        self.assertIn(os.ttyname(self.slave), m.terminals(os.getpid(), has_children=False))

    def test_the_protocol(self):
        self.flags(echo=True, icanon=True)
        proc, out = start({"DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent"})
        try:
            self.assertEqual(out.tagged("echo"), "echo clear")
            tell(proc, f"pid {self.child.pid}")
            self.assertEqual(out.tagged("echo"), "echo clear")
            self.flags(echo=False, icanon=True)
            started = time.monotonic()
            self.assertEqual(out.tagged("echo"), "echo secret")
            self.assertLess(time.monotonic() - started, 0.5)
            self.flags(echo=True, icanon=True)
            self.assertEqual(out.tagged("echo"), "echo clear")
            # Lines the helper does not know are passed over.
            tell(proc, "pid x")
            tell(proc, "nonsense")
            tell(proc, "pid 0")
            self.assertEqual(out.tagged("echo"), "echo clear")
            proc.stdin.close()
            self.assertEqual(proc.wait(timeout=5), 0)
        finally:
            stop(proc)

    def test_started_over_with_a_pid_says_nothing_of_none(self):
        # A helper started over is handed the watched window on its command
        # line: its first word is that window's, never a "clear" for none
        # while a password prompt is up.
        self.flags(echo=False, icanon=True)
        proc, out = start({"DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent"},
                          args=("--pid", str(self.child.pid)))
        try:
            self.assertEqual(out.tagged("echo"), "echo secret")
        finally:
            stop(proc)


class Watch(unittest.TestCase):
    def setUp(self):
        self.r, w = os.pipe()
        self.out = m.Out(w)
        self.watch = m.Watch(self.out)

    def said(self):
        data = b""
        while select.select([self.r], [], [], 0)[0]:
            data += os.read(self.r, 4096)
        return data.decode().splitlines()

    def test_a_window_without_a_terminal_is_not_ticked(self):
        child = subprocess.Popen(["sleep", "30"], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            self.assertEqual(m.terminals(child.pid), set())
            self.watch.target(child.pid)
            now = time.monotonic()
            self.watch.tick(now, 0.0)
            self.assertEqual(self.said(), ["echo clear"])
            # Its next turn is the tree's, a second away, not the 25 ms of
            # the flags.
            self.assertEqual(self.watch.deadlines(), [self.watch.next_tree])
            self.assertGreaterEqual(min(self.watch.deadlines()) - now, m.TREE_EVERY - 0.01)
        finally:
            child.kill()
            child.wait()

    def test_a_fault_reads_as_a_prompt(self):
        # The key reader is paused rather than a password let through.
        self.watch.target(os.getpid())
        with mock.patch.object(m, "terminals", side_effect=RuntimeError):
            m.watch_turn(self.watch, time.monotonic(), 0.0)
        self.assertEqual(self.said(), ["echo secret"])


if __name__ == "__main__":
    unittest.main()
