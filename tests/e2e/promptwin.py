#!/usr/bin/env python3
"""A window for tests/e2e/run.sh whose process holds a terminal that asks for
a password, as a terminal emulator's shell does under sudo: a pseudo-terminal
of its own as stdin, echo off and line-buffered. SIGUSR1 turns the echo back
on, as the prompt ending would. Nothing is typed into the terminal or read
from it. Ends after a minute at most.
"""

import os
import signal
import termios

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

master, slave = os.openpty()


def echo(on):
    attrs = termios.tcgetattr(slave)
    attrs[3] = attrs[3] | termios.ECHO if on else attrs[3] & ~termios.ECHO
    attrs[3] |= termios.ICANON
    termios.tcsetattr(slave, termios.TCSANOW, attrs)


echo(False)
os.dup2(slave, 0)

GLib.set_prgname("promptwin")
GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR1, lambda: echo(True) or True)
window = Gtk.Window(title="promptwin")
window.set_default_size(320, 200)
window.connect("destroy", Gtk.main_quit)
window.show_all()
GLib.timeout_add_seconds(60, Gtk.main_quit)
Gtk.main()
