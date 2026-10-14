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
import time
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


class FakeConsole:
    """The console in front, as the test says; no file to poll."""
    front = {"ours": True}

    def __init__(self, session_vt, path=None):
        self.fd = None

    def ours(self):
        return FakeConsole.front["ours"]


class Loop(unittest.TestCase):
    def run_main(self, steps, events=b"", later_events=b"", args=(), ours=True):
        """main() with stdin fed by steps, (seconds, bytes) pairs, then
        ended; one keyboard with events waiting, and later_events written to
        it 0.3 s in. Returns the exit status, what the bar got, and the
        keyboards each open and close saw."""
        FakeConsole.front["ours"] = ours
        r, w = os.pipe()
        kr, kw = os.pipe()
        os.write(kw, events)
        opens, closes = [], []

        def feed():
            begun = time.monotonic()
            for at, data in steps:
                time.sleep(max(0, at - (time.monotonic() - begun)))
                if callable(data):
                    data()
                else:
                    os.write(w, data)
            time.sleep(0.1)
            os.close(w)

        def open_keyboards(skip=frozenset()):
            if skip:
                return {}
            opens.append(True)
            return {kr: "/dev/input/event9"}

        def close_keyboards(devices):
            closes.append(sorted(devices))
            devices.clear()

        writer = threading.Thread(target=feed)
        later = threading.Timer(0.3, os.write, (kw, later_events)) if later_events else None
        try:
            with stdio(r) as out, \
                 mock.patch.object(keyfeed, "open_keyboards", side_effect=open_keyboards), \
                 mock.patch.object(keyfeed, "close_keyboards", side_effect=close_keyboards), \
                 mock.patch.object(keyfeed, "drop_privileges"), \
                 mock.patch.object(keyfeed, "Console", FakeConsole), \
                 mock.patch.object(keyfeed.signal, "signal"):
                writer.start()
                if later:
                    later.start()
                code = keyfeed.main(args)
                out.seek(0)
                return code, out.read().decode(), opens, closes
        finally:
            writer.join()
            if later:
                later.join()
            os.close(r)
            os.close(kr)
            os.close(kw)

    def test_end_of_stdin_stops_it(self):
        code, out, opens, _ = self.run_main([])
        self.assertEqual(code, 0)
        self.assertEqual(out, '{"type": "ready"}\n')
        self.assertEqual(opens, [], "no keyboard is opened before a resume")

    def test_a_stop_line_stops_it(self):
        code, _, _, _ = self.run_main([(0, b"stop\n")])
        self.assertEqual(code, 0)

    @unittest.skipUnless(os.path.exists(HEADER), "the kernel's input header is not installed")
    def test_paused_it_holds_no_keyboard(self):
        _, out, opens, _ = self.run_main([(0, b"pause\n")], event(1, 30, 1))
        self.assertEqual(opens, [])
        self.assertNotIn('"key"', out)

    @unittest.skipUnless(os.path.exists(HEADER), "the kernel's input header is not installed")
    def test_resumed_it_reads(self):
        _, out, opens, _ = self.run_main([(0, b"resume\n")], event(1, 30, 1))
        self.assertEqual(len(opens), 1)
        self.assertIn('{"type": "key", "mods": [], "key": "A"}', out)

    @unittest.skipUnless(os.path.exists(HEADER), "the kernel's input header is not installed")
    def test_a_pause_closes_the_keyboards(self):
        _, out, _, closes = self.run_main([(0, b"resume\n"), (0.2, b"pause\n")],
                                          event(1, 30, 1), later_events=event(1, 48, 1))
        self.assertEqual(len(closes), 1)
        self.assertIn('"key": "A"', out)
        self.assertNotIn('"key": "B"', out, "a key pressed while paused was read")

    @unittest.skipUnless(os.path.exists(HEADER), "the kernel's input header is not installed")
    def test_another_console_in_front(self):
        def back():
            FakeConsole.front["ours"] = True

        _, out, opens, _ = self.run_main([(0, b"resume\n"), (0.2, back), (0.2, b"wake\n")],
                                         event(1, 30, 1), args=["--vt", "1"], ours=False)
        self.assertEqual(len(opens), 1, "opened once the session's console was back")
        self.assertIn('"key": "A"', out)

    def test_modifiers_held_across_a_pause(self):
        def ioctl(fd, request, bits, mutate):
            bits[29 // 8] |= 1 << (29 % 8)
            bits[125 // 8] |= 1 << (125 % 8)
            return 0

        with mock.patch.object(keyfeed.fcntl, "ioctl", side_effect=ioctl):
            self.assertEqual(keyfeed.held_modifiers({7: "/dev/input/event7"}), {29, 125})


class Consoles(unittest.TestCase):
    def test_the_active_file(self):
        with tempfile.NamedTemporaryFile("w") as fh:
            fh.write("tty2\n")
            fh.flush()
            self.assertTrue(keyfeed.Console("tty2", fh.name).ours())
            self.assertFalse(keyfeed.Console("tty1", fh.name).ours())
        self.assertTrue(keyfeed.Console(None).ours(), "no console given: always ours")


if __name__ == "__main__":
    unittest.main()
