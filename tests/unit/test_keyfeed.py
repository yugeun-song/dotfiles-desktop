"""Tests for quickshell/bar/scripts/keyfeed.py, without touching a device.

The reader's file and device access is replaced with mocks: a test must never
open /dev/input, which would read the keyboard of whoever runs it.
"""

import importlib.util
import os
import pathlib
import sys
import unittest
from unittest import mock

# The script is imported from the tree install.sh mirrors, and a bytecode
# cache written beside it went out with the next install.
sys.dont_write_bytecode = True

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "quickshell/bar/scripts/keyfeed.py"
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


if __name__ == "__main__":
    unittest.main()
