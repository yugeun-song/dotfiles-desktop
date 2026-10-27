#!/usr/bin/env python3
"""A media player for tests/e2e/run.sh, on the session bus it is run with (the
suite's private one): one MPRIS player with a track, a cover read from a local
file, and play, pause and play-pause that switch its state as a real player's
do. Every method called goes to the log given as the first argument. Ends
after five minutes at most.

Usage: mprisapp.py LOG COVER
"""

import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

LOG, COVER = sys.argv[1], sys.argv[2]
NAME = "org.mpris.MediaPlayer2.e2e"
PATH = "/org/mpris/MediaPlayer2"

XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
    <method name="Raise"/>
    <method name="Quit"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Position" type="x" access="read"/>
    <property name="Rate" type="d" access="read"/>
    <property name="Volume" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
    <method name="Play"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Seek"><arg type="x" direction="in"/></method>
    <method name="SetPosition"><arg type="o" direction="in"/><arg type="x" direction="in"/></method>
  </interface>
</node>
"""

state = {"status": "Playing"}
loop = GLib.MainLoop()


def log(line):
    with open(LOG, "a") as fh:
        fh.write(line + "\n")


def metadata():
    return {
        "mpris:trackid": GLib.Variant("o", "/org/mpris/MediaPlayer2/e2e/1"),
        "mpris:length": GLib.Variant("x", 200_000_000),
        "mpris:artUrl": GLib.Variant("s", "file://" + COVER),
        "xesam:title": GLib.Variant("s", "E2E Song"),
        "xesam:artist": GLib.Variant("as", ["E2E Artist"]),
    }


def get_property(_conn, _sender, _path, iface, name):
    if iface == "org.mpris.MediaPlayer2":
        return {
            "Identity": GLib.Variant("s", "E2E player"),
            "DesktopEntry": GLib.Variant("s", "e2e-player"),
            "CanQuit": GLib.Variant("b", False),
            "CanRaise": GLib.Variant("b", False),
            "HasTrackList": GLib.Variant("b", False),
            "SupportedUriSchemes": GLib.Variant("as", []),
            "SupportedMimeTypes": GLib.Variant("as", []),
        }.get(name)
    return {
        "PlaybackStatus": GLib.Variant("s", state["status"]),
        "Metadata": GLib.Variant("a{sv}", metadata()),
        "Position": GLib.Variant("x", 30_000_000),
        "Rate": GLib.Variant("d", 1.0),
        "Volume": GLib.Variant("d", 1.0),
        "CanGoNext": GLib.Variant("b", True),
        "CanGoPrevious": GLib.Variant("b", True),
        "CanPlay": GLib.Variant("b", True),
        "CanPause": GLib.Variant("b", True),
        "CanSeek": GLib.Variant("b", False),
        "CanControl": GLib.Variant("b", True),
    }.get(name)


def set_status(conn, status):
    state["status"] = status
    conn.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                     GLib.Variant("(sa{sv}as)", ("org.mpris.MediaPlayer2.Player",
                                                 {"PlaybackStatus": GLib.Variant("s", status)}, [])))


def call(conn, _sender, _path, _iface, method, _params, invocation):
    log(method)
    if method == "Play":
        set_status(conn, "Playing")
    elif method == "Pause":
        set_status(conn, "Paused")
    elif method == "PlayPause":
        set_status(conn, "Paused" if state["status"] == "Playing" else "Playing")
    elif method == "Stop":
        set_status(conn, "Stopped")
    invocation.return_value(None)


bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
for info in Gio.DBusNodeInfo.new_for_xml(XML).interfaces:
    bus.register_object(PATH, info, call, get_property, None)
bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
              GLib.Variant("(su)", (NAME, 4)), None, Gio.DBusCallFlags.NONE, -1, None)
GLib.timeout_add_seconds(300, loop.quit)
loop.run()
