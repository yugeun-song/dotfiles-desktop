#!/usr/bin/env python3
"""A window for tests/e2e/run.sh's see-through lock (scenario 35), of the class
glasswin: filled with the colour its file names (#rrggbb), read again ten
times a second, so that a colour written while the screen is locked shows
only if the compositor goes on drawing the desktop under the lock. Ends
after two minutes at most.

    glasswin.py COLOUR-FILE
"""

import sys

import gi

gi.require_version("Gdk", "3.0")
gi.require_version("Gtk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

path = sys.argv[1]
shown = {"colour": ""}

GLib.set_prgname("glasswin")
window = Gtk.Window(title="glasswin")
window.set_wmclass("glasswin", "glasswin")
area = Gtk.DrawingArea()
window.add(area)


def read():
    try:
        with open(path, encoding="ascii") as fh:
            colour = fh.read().strip()
    except OSError:
        return True
    if colour != shown["colour"]:
        shown["colour"] = colour
        area.queue_draw()
    return True


def draw(_widget, cr):
    rgba = Gdk.RGBA()
    if not rgba.parse(shown["colour"] or "#808080"):
        rgba.parse("#808080")
    cr.set_source_rgb(rgba.red, rgba.green, rgba.blue)
    cr.paint()
    return False


area.connect("draw", draw)
window.connect("destroy", Gtk.main_quit)
read()
GLib.timeout_add(100, read)
window.show_all()
GLib.timeout_add_seconds(120, Gtk.main_quit)
Gtk.main()
