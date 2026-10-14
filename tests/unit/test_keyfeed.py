"""Tests for keyfeed/keyfeed.py, without touching a device.

The reader's file and device access is replaced with mocks: a test must never
open /dev/input, which would read the keyboard of whoever runs it.
"""

import contextlib
import importlib.util
import os
import pathlib
import struct
import sys
import tempfile
import threading
import unittest
from unittest import mock

# No bytecode cache beside the script: install.sh would see an extra file.
sys.dont_write_bytecode = True

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "keyfeed/keyfeed.py"
HEADER = "/usr/include/linux/input-event-codes.h"


def load():
    spec = importlib.util.spec_from_file_location("keyfeed", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


keyfeed = load()


@unittest.skipUnless(os.path.exists(HEADER), "the kernel's input header is not installed")
class Labels(unittest.TestCase):
    def test_letter(self):
        self.assertEqual(keyfeed.label(30), "A")

    def test_pretty(self):
        self.assertEqual(keyfeed.label(1), "Esc")
        self.assertEqual(keyfeed.label(122), "한/영")

    def test_function_key(self):
        self.assertEqual(keyfeed.label(88), "F12")

    def test_other_names_capitalised(self):
        self.assertEqual(keyfeed.label(115), "Volumeup")

    def test_unknown(self):
        code = next(c for c in range(0x2FE, 0, -1) if c not in keyfeed.NAMES)
        self.assertEqual(keyfeed.label(code), f"#{code}")


class Keyboards(unittest.TestCase):
    def caps(self, words):
        return mock.patch("builtins.open", mock.mock_open(read_data=words))

    def test_letter_bit_set(self):
        # KEY_A is bit 30 of the lowest word, which is printed last.
        with self.caps("0 0 0 40000000\n"):
            self.assertTrue(keyfeed.is_keyboard("event3"))

    def test_buttons_only(self):
        with self.caps("70000 0 0 0 0 0 0 0\n"):
            self.assertFalse(keyfeed.is_keyboard("event4"))

    def test_unreadable(self):
        with mock.patch("builtins.open", side_effect=OSError):
            self.assertFalse(keyfeed.is_keyboard("event9"))

    def test_open_skips_what_is_open(self):
        opened = []

        def fake_open(path, flags):
            opened.append(path)
            return 100 + len(opened)

        with mock.patch.object(keyfeed.os, "listdir", return_value=["event1", "event0", "mouse0"]), \
             mock.patch.object(keyfeed, "is_keyboard", return_value=True), \
             mock.patch.object(keyfeed.os, "open", side_effect=fake_open):
            found = keyfeed.open_keyboards(frozenset({"/dev/input/event0"}))
        self.assertEqual(opened, ["/dev/input/event1"])
        self.assertEqual(list(found.values()), ["/dev/input/event1"])

    def test_open_failure_is_not_fatal(self):
        with mock.patch.object(keyfeed.os, "listdir", return_value=["event0"]), \
             mock.patch.object(keyfeed, "is_keyboard", return_value=True), \
             mock.patch.object(keyfeed.os, "open", side_effect=PermissionError):
            self.assertEqual(keyfeed.open_keyboards(), {})


def event(etype, code, value):
    return struct.pack(keyfeed.FORMAT, 0, 0, etype, code, value)


@unittest.skipUnless(os.path.exists(HEADER), "the kernel's input header is not installed")
class Decode(unittest.TestCase):
    def test_chord_and_zeroed_buffer(self):
        raw = b"".join([event(1, 29, 1), event(1, 30, 1), event(1, 30, 2), event(1, 30, 0),
                        event(0, 0, 0), event(1, 29, 0), event(1, 48, 1)])
        buf = bytearray(keyfeed.EVENT_SIZE * 64)
        buf[:len(raw)] = raw
        held = set()
        out = keyfeed.decode(buf, len(raw), held)
        self.assertEqual(out, [{"type": "key", "mods": ["Ctrl"], "key": "A"},
                               {"type": "key", "mods": [], "key": "B"}])
        self.assertEqual(held, set())
        self.assertEqual(bytes(buf), bytes(len(buf)), "the events stay in the buffer")

    def test_modifier_held_across_reads(self):
        buf = bytearray(event(1, 125, 1))
        held = set()
        self.assertEqual(keyfeed.decode(buf, len(buf), held), [])
        buf = bytearray(event(1, 30, 1))
        self.assertEqual(keyfeed.decode(buf, len(buf), held), [{"type": "key", "mods": ["Super"], "key": "A"}])


class Privileges(unittest.TestCase):
    def test_not_root_keeps_everything(self):
        with mock.patch.object(keyfeed.os, "geteuid", return_value=1000), \
             mock.patch.object(keyfeed.os, "setuid") as setuid:
            keyfeed.drop_privileges()
        setuid.assert_not_called()

    def test_root_becomes_nobody_with_the_input_group(self):
        calls = []
        with mock.patch.object(keyfeed.os, "geteuid", return_value=0), \
             mock.patch.object(keyfeed.grp, "getgrnam", return_value=mock.Mock(gr_gid=992)), \
             mock.patch.object(keyfeed.pwd, "getpwnam", return_value=mock.Mock(pw_uid=65534, pw_gid=65534)), \
             mock.patch.object(keyfeed.os, "setgroups", side_effect=lambda g: calls.append(("groups", g))), \
             mock.patch.object(keyfeed.os, "setgid", side_effect=lambda g: calls.append(("gid", g))), \
             mock.patch.object(keyfeed.os, "setuid", side_effect=lambda u: calls.append(("uid", u))), \
             mock.patch.object(keyfeed, "undumpable", side_effect=lambda: calls.append(("undumpable",))):
            keyfeed.drop_privileges()
        self.assertEqual(calls, [("groups", []), ("gid", 992), ("uid", 65534), ("undumpable",)])


@contextlib.contextmanager
def stdio(stdin_fd):
    """fd 0 from stdin_fd and fd 1 into a file, as the bar's pipes would be."""
    saved = os.dup(0), os.dup(1)
    with tempfile.TemporaryFile() as out:
        os.dup2(stdin_fd, 0)
        os.dup2(out.fileno(), 1)
        try:
            yield out
        finally:
            os.dup2(saved[0], 0)
            os.dup2(saved[1], 1)
            os.close(saved[0])
            os.close(saved[1])


class Lines(unittest.TestCase):
    def control(self, *chunks):
        r, w = os.pipe()
        c = keyfeed.Control(r)
        try:
            for chunk in chunks:
                os.write(w, chunk)
                if not c.read():
                    return c, False
            return c, True
        finally:
            os.close(r)
            os.close(w)

    def test_starts_paused(self):
        self.assertFalse(keyfeed.Control(0).open)

    def test_resume_then_pause(self):
        self.assertTrue(self.control(b"resume\n")[0].open)
        self.assertFalse(self.control(b"resume\npause\n")[0].open)

    def test_a_line_in_two_reads(self):
        c, going = self.control(b"res", b"ume\n")
        self.assertTrue(going)
        self.assertTrue(c.open)

    def test_unknown_lines_are_ignored(self):
        c, going = self.control(b"louder\nresume\n")
        self.assertTrue(going and c.open)

    def test_stop(self):
        self.assertFalse(self.control(b"resume\nstop\n")[1])

    def test_args(self):
        self.assertIsNone(keyfeed.parse_args([]))
        self.assertEqual(keyfeed.parse_args(["--vt", "2"]), "tty2")
        with self.assertRaises(SystemExit):
            keyfeed.parse_args(["--vt", "two"])


class Control(unittest.TestCase):
    def run_main(self, feed, events=b"", args=(), console="tty1", end=True):
        """main() on a stdin that carries feed, then ends after a moment
        (or at once, with nothing fed), with one keyboard that has events
        waiting. The output, as written to the bar."""
        r, w = os.pipe()
        kr, kw = os.pipe()
        os.write(kw, events)
        if feed:
            os.write(w, feed)
            closer = threading.Timer(0.4, os.close, (w,))
            closer.start()
        else:
            os.close(w)
        try:
            with stdio(r) as out, \
                 mock.patch.object(keyfeed, "open_keyboards", side_effect=[{kr: "/dev/input/event9"}, {}]), \
                 mock.patch.object(keyfeed, "drop_privileges"), \
                 mock.patch.object(keyfeed, "foreground_vt", return_value=console), \
                 mock.patch.object(keyfeed.signal, "signal"):
                code = keyfeed.main(args)
                out.seek(0)
                return code, out.read().decode()
        finally:
            if feed:
                closer.join()
            os.close(r)
            os.close(kr)
            os.close(kw)

    def test_end_of_stdin_stops_it(self):
        code, out = self.run_main(b"")
        self.assertEqual(code, 0)
        self.assertEqual(out, '{"type": "ready", "devices": 1}\n')

    def test_a_line_on_stdin_stops_it(self):
        code, _ = self.run_main(b"stop\n")
        self.assertEqual(code, 0)

    @unittest.skipUnless(os.path.exists(HEADER), "the kernel's input header is not installed")
    def test_paused_until_resumed(self):
        _, out = self.run_main(b"pause\n", event(1, 30, 1))
        self.assertNotIn('"key"', out)

    @unittest.skipUnless(os.path.exists(HEADER), "the kernel's input header is not installed")
    def test_resumed_sends_keys(self):
        _, out = self.run_main(b"resume\n", event(1, 30, 1))
        self.assertIn('{"type": "key", "mods": [], "key": "A"}', out)

    @unittest.skipUnless(os.path.exists(HEADER), "the kernel's input header is not installed")
    def test_nothing_while_another_console_is_in_front(self):
        _, out = self.run_main(b"resume\n", event(1, 30, 1), args=["--vt", "1"], console="tty3")
        self.assertNotIn('"key"', out)
        _, out = self.run_main(b"resume\n", event(1, 30, 1), args=["--vt", "1"], console="tty1")
        self.assertIn('"key"', out)


if __name__ == "__main__":
    unittest.main()
