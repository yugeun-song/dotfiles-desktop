#!/usr/bin/env python3
"""A plain window for tests/e2e/run.sh, of the class plainwin: nothing in it
and nothing behind it, for what a window's presence does to the desktop
(the desktop widgets hide under a tiled one). Ends after a minute at most.
"""

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

GLib.set_prgname("plainwin")
window = Gtk.Window(title="plainwin")
window.set_wmclass("plainwin", "plainwin")
window.set_default_size(640, 400)
window.connect("destroy", Gtk.main_quit)
window.show_all()
GLib.timeout_add_seconds(60, Gtk.main_quit)
Gtk.main()
