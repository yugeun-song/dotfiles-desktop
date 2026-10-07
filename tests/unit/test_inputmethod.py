"""Tests for quickshell/bar/scripts/inputmethod.py, the input method poller.

Its D-Bus client is checked two ways: against a private dbus-daemon started
here with no service directory, so asking for fcitx5 can never start a second
one (a second fcitx5 has emptied XIM_SERVERS before), and over a socketpair
fed hand-built replies for what a daemon will not readily produce (a signal
in between, a late reply, a message cut in half by a timeout).
"""

import importlib.util
import os
import pathlib
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "quickshell/bar/scripts/inputmethod.py"
spec = importlib.util.spec_from_file_location("inputmethod", SCRIPT)
im = importlib.util.module_from_spec(spec)
spec.loader.exec_module(im)

BUS_CONFIG = """<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
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


def reply(reply_to, signature="", body=b"", kind=im.METHOD_RETURN):
    """A message as a daemon sends it: little-endian, the header padded to 8."""
    msg = bytearray(struct.pack("<cBBBII", b"l", kind, 0, 1, len(body), 1000 + (reply_to or 0)))
    msg += b"\0\0\0\0"

    def align(n):
        msg.extend(b"\0" * (-len(msg) % n))

    if reply_to is not None:
        align(8)
        msg += bytes([im.REPLY_SERIAL]) + b"\x01u\0"
        align(4)
        msg += struct.pack("<I", reply_to)
    if signature:
        align(8)
        msg += bytes([im.SIGNATURE]) + b"\x01g\0" + bytes([len(signature)]) + signature.encode() + b"\0"
    struct.pack_into("<I", msg, 12, len(msg) - 16)
    align(8)
    return bytes(msg) + body


def string(value):
    data = value.encode()
    return struct.pack("<I", len(data)) + data + b"\0"


class Addresses(unittest.TestCase):
    def test_path_with_escapes(self):
        with mock.patch.dict(os.environ, {"DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/1000/a%20b,guid=x"}):
            self.assertEqual(im.addresses(), ["/run/user/1000/a b"])

    def test_abstract_and_order(self):
        env = {"DBUS_SESSION_BUS_ADDRESS": "tcp:host=x,port=1;unix:abstract=/tmp/dbus-1;unix:path=/run/bus"}
        with mock.patch.dict(os.environ, env):
            self.assertEqual(im.addresses(), ["\0/tmp/dbus-1", "/run/bus"])

    def test_fallback(self):
        env = {"DBUS_SESSION_BUS_ADDRESS": "", "XDG_RUNTIME_DIR": "/run/user/7"}
        with mock.patch.dict(os.environ, env):
            self.assertEqual(im.addresses(), ["/run/user/7/bus"])


class Marshal(unittest.TestCase):
    def test_header_parses_back(self):
        msg = im.marshal_call(7, "org.fcitx.Fcitx5", "/controller", "org.fcitx.Fcitx.Controller1", "State")
        self.assertEqual(len(msg) % 8, 0)
        self.assertEqual(struct.unpack_from("<I", msg, 4)[0], 0)
        self.assertEqual(struct.unpack_from("<I", msg, 8)[0], 7)
        length = struct.unpack_from("<I", msg, 12)[0]
        self.assertEqual(im.header_fields(msg, "<", length), {
            im.PATH: "/controller", im.INTERFACE: "org.fcitx.Fcitx.Controller1",
            im.MEMBER: "State", im.DESTINATION: "org.fcitx.Fcitx5"})


class Stream(unittest.TestCase):
    def setUp(self):
        self.ours, self.theirs = socket.socketpair()
        self.ours.settimeout(0.3)
        self.bus = im.Bus(self.ours)

    def tearDown(self):
        self.ours.close()
        self.theirs.close()

    def test_int_reply_after_a_signal(self):
        self.theirs.sendall(reply(None, kind=4) + reply(1, "i", struct.pack("<i", 2)))
        self.assertEqual(self.bus.call(*im.FCITX, "State"), 2)

    def test_late_reply_is_passed_over(self):
        self.theirs.sendall(reply(5, "s", string("old")) + reply(1, "s", string("hangul")))
        self.assertEqual(self.bus.call(*im.FCITX, "CurrentInputMethod"), "hangul")

    def test_error_reply(self):
        self.theirs.sendall(reply(1, "s", string("org.freedesktop.DBus.Error.ServiceUnknown"), kind=im.ERROR))
        self.assertIsNone(self.bus.call(*im.FCITX, "State"))

    def test_timeout_mid_message_keeps_the_stream(self):
        whole = reply(1, "i", struct.pack("<i", 1))
        self.theirs.sendall(whole[:10])
        with self.assertRaises(TimeoutError):
            self.bus.call(*im.FCITX, "State")
        self.assertEqual(self.bus.pending, whole[:10])
        # The rest of the late reply, then the answer to the next call.
        self.theirs.sendall(whole[10:] + reply(2, "i", struct.pack("<i", 2)))
        self.assertEqual(self.bus.call(*im.FCITX, "State"), 2)

    def test_closed_bus(self):
        self.theirs.close()
        with self.assertRaises(ConnectionError):
            self.bus.call(*im.FCITX, "State")


@unittest.skipUnless(shutil.which("dbus-daemon"), "dbus-daemon is not installed")
class PrivateBus(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        config = os.path.join(self.dir, "bus.conf")
        with open(config, "w") as fh:
            fh.write(BUS_CONFIG)
        out = subprocess.run(["dbus-daemon", f"--config-file={config}", "--fork", "--print-address=1", "--print-pid=1"],
                             capture_output=True, text=True, check=True).stdout.split("\n")
        self.address, self.pid = out[0].strip(), int(out[1])

    def tearDown(self):
        os.kill(self.pid, 15)
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_hello_and_a_missing_fcitx5(self):
        with mock.patch.dict(os.environ, {"DBUS_SESSION_BUS_ADDRESS": self.address}):
            bus = im.connect()
        self.assertIsNotNone(bus)
        self.assertRegex(bus.call(*im.BUS, "GetId"), r"^[0-9a-f]{32}$")
        self.assertIsNone(bus.call(*im.FCITX, "State"))
        bus.sock.close()

    def test_the_script_reports_no_answer(self):
        env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=self.address, INPUTMETHOD_POLL_INTERVAL="0.05")
        proc = subprocess.Popen([sys.executable, "-I", str(SCRIPT)], env=env, stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(proc.stdout.readline(), "-\n")
        finally:
            proc.kill()
            proc.wait()

    def test_no_bus_exits(self):
        env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=f"unix:path={self.dir}/none")
        self.assertEqual(subprocess.run([sys.executable, "-I", str(SCRIPT)], env=env, timeout=10).returncode, 1)


if __name__ == "__main__":
    unittest.main()
