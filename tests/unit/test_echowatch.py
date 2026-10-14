"""Tests for quickshell/bar/scripts/echowatch.py, on a pseudo-terminal of its
own: a child process holds the terminal as stdin, and the terminal's flags
are set as a password prompt, a full-screen program or a plain command
would set them. Nothing is typed into it and nothing is read from it."""

import importlib.util
import os
import pathlib
import subprocess
import sys
import termios
import time
import unittest

sys.dont_write_bytecode = True
SCRIPT = pathlib.Path(__file__).resolve().parents[2] / "quickshell/bar/scripts/echowatch.py"


def load():
    spec = importlib.util.spec_from_file_location("echowatch", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


echowatch = load()


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
        return any(echowatch.asking(t) for t in echowatch.terminals(self.child.pid))

    def test_the_childs_terminal_is_found(self):
        self.assertEqual(echowatch.terminals(self.child.pid), {os.ttyname(self.slave)})

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
        self.assertTrue(any(echowatch.asking(t) for t in echowatch.terminals(os.getpid())))

    def test_the_protocol(self):
        self.flags(echo=True, icanon=True)
        watch = subprocess.Popen([sys.executable, "-I", str(SCRIPT)], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, text=True, bufsize=1)
        try:
            watch.stdin.write(f"pid {self.child.pid}\n")
            watch.stdin.flush()
            self.assertEqual(watch.stdout.readline().strip(), "clear")
            self.flags(echo=False, icanon=True)
            started = time.monotonic()
            self.assertEqual(watch.stdout.readline().strip(), "secret")
            self.assertLess(time.monotonic() - started, 0.5)
            self.flags(echo=True, icanon=True)
            self.assertEqual(watch.stdout.readline().strip(), "clear")
            watch.stdin.write("pid 0\n")
            watch.stdin.flush()
            watch.stdin.close()
            self.assertEqual(watch.wait(timeout=5), 0)
        finally:
            if watch.poll() is None:
                watch.kill()
                watch.wait()
            watch.stdout.close()


class NoTerminal(unittest.TestCase):
    def test_a_window_without_one(self):
        child = subprocess.Popen(["sleep", "30"], stdin=subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            self.assertEqual(echowatch.terminals(child.pid), set())
        finally:
            child.kill()
            child.wait()


if __name__ == "__main__":
    unittest.main()
