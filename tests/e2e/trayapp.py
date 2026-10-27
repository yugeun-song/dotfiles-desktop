#!/usr/bin/env python3
"""A tray application for tests/e2e/run.sh, on the session bus it is run with
(the suite's private one): one StatusNotifierItem whose menu holds Open, a
separator and Exit, as Zoom's does, and whose icon is a white square that a
capture finds easily. Activate and every menu event go to the log given as
the only argument; Exit ends the program, as the real one's does. Ends after
two minutes at most.

Usage: trayapp.py LOG
"""

import os
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

LOG = sys.argv[1]
NAME = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
SIDE = 22

ITEM_XML = """
<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="WindowId" type="i" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconPixmap" type="a(iiay)" access="read"/>
    <property name="OverlayIconName" type="s" access="read"/>
    <property name="AttentionIconName" type="s" access="read"/>
    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <method name="ContextMenu"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="Activate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="SecondaryActivate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="Scroll"><arg type="i" direction="in"/><arg type="s" direction="in"/></method>
    <signal name="NewTitle"/>
    <signal name="NewIcon"/>
    <signal name="NewStatus"><arg type="s"/></signal>
  </interface>
</node>
"""

MENU_XML = """
<node>
  <interface name="com.canonical.dbusmenu">
    <property name="Version" type="u" access="read"/>
    <property name="TextDirection" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="IconThemePath" type="as" access="read"/>
    <method name="GetLayout">
      <arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="as" direction="in"/>
      <arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/>
    </method>
    <method name="GetGroupProperties">
      <arg type="ai" direction="in"/><arg type="as" direction="in"/><arg type="a(ia{sv})" direction="out"/>
    </method>
    <method name="GetProperty">
      <arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/>
    </method>
    <method name="Event">
      <arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/><arg type="u" direction="in"/>
    </method>
    <method name="EventGroup"><arg type="a(isvu)" direction="in"/><arg type="ai" direction="out"/></method>
    <method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
    <method name="AboutToShowGroup">
      <arg type="ai" direction="in"/><arg type="ai" direction="out"/><arg type="ai" direction="out"/>
    </method>
    <signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
    <signal name="ItemsPropertiesUpdated"><arg type="a(ia{sv})"/><arg type="a(ias)"/></signal>
  </interface>
</node>
"""

ENTRIES = {1: {"label": GLib.Variant("s", "_Open")},
           2: {"type": GLib.Variant("s", "separator")},
           3: {"label": GLib.Variant("s", "_Exit")}}
EXIT = 3

loop = GLib.MainLoop()


def log(line):
    with open(LOG, "a") as fh:
        fh.write(line + "\n")


def pixmap():
    return [(SIDE, SIDE, b"\xff" * (SIDE * SIDE * 4))]


def item_property(_conn, _sender, _path, _iface, name):
    values = {
        "Category": GLib.Variant("s", "ApplicationStatus"),
        "Id": GLib.Variant("s", "e2e-tray"),
        "Title": GLib.Variant("s", "E2E tray"),
        "Status": GLib.Variant("s", "Active"),
        "WindowId": GLib.Variant("i", 0),
        "IconName": GLib.Variant("s", ""),
        "IconPixmap": GLib.Variant("a(iiay)", pixmap()),
        "OverlayIconName": GLib.Variant("s", ""),
        "AttentionIconName": GLib.Variant("s", ""),
        "ToolTip": GLib.Variant("(sa(iiay)ss)", ("", [], "E2E tray", "")),
        "ItemIsMenu": GLib.Variant("b", False),
        "Menu": GLib.Variant("o", "/MenuBar"),
    }
    return values.get(name)


def item_call(_conn, _sender, _path, _iface, method, params, invocation):
    if method == "Activate":
        log("activate")
    invocation.return_value(None)


def node(entry_id):
    props = ENTRIES.get(entry_id, {"children-display": GLib.Variant("s", "submenu")})
    children = [] if entry_id else [GLib.Variant("(ia{sv}av)", node(i)) for i in ENTRIES]
    return (entry_id, props, children)


def menu_property(_conn, _sender, _path, _iface, name):
    values = {
        "Version": GLib.Variant("u", 3),
        "TextDirection": GLib.Variant("s", "ltr"),
        "Status": GLib.Variant("s", "normal"),
        "IconThemePath": GLib.Variant("as", []),
    }
    return values.get(name)


def menu_call(_conn, _sender, _path, _iface, method, params, invocation):
    if method == "GetLayout":
        parent = params.unpack()[0]
        invocation.return_value(GLib.Variant("(u(ia{sv}av))", (1, node(parent))))
    elif method == "GetGroupProperties":
        ids = params.unpack()[0] or list(ENTRIES)
        invocation.return_value(GLib.Variant("(a(ia{sv}))", ([(i, ENTRIES[i]) for i in ids if i in ENTRIES],)))
    elif method == "GetProperty":
        entry_id, name = params.unpack()
        value = ENTRIES.get(entry_id, {}).get(name, GLib.Variant("s", ""))
        invocation.return_value(GLib.Variant("(v)", (value,)))
    elif method == "Event":
        entry_id, event = params.unpack()[:2]
        log(f"event {entry_id} {event}")
        invocation.return_value(None)
        if entry_id == EXIT and event == "clicked":
            GLib.timeout_add(100, loop.quit)
    elif method == "EventGroup":
        events = params.unpack()[0]
        for entry_id, event, _data, _time in events:
            log(f"event {entry_id} {event}")
        invocation.return_value(GLib.Variant("(ai)", ([],)))
    elif method == "AboutToShow":
        invocation.return_value(GLib.Variant("(b)", (False,)))
    elif method == "AboutToShowGroup":
        invocation.return_value(GLib.Variant("(aiai)", ([], [])))
    else:
        invocation.return_value(None)


bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
item_info = Gio.DBusNodeInfo.new_for_xml(ITEM_XML).interfaces[0]
menu_info = Gio.DBusNodeInfo.new_for_xml(MENU_XML).interfaces[0]
bus.register_object("/StatusNotifierItem", item_info, item_call, item_property, None)
bus.register_object("/MenuBar", menu_info, menu_call, menu_property, None)
bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
              GLib.Variant("(su)", (NAME, 4)), None, Gio.DBusCallFlags.NONE, -1, None)


# The bar's watcher may not be on the bus yet: asked again until it answers.
def register():
    try:
        bus.call_sync("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
                      "RegisterStatusNotifierItem", GLib.Variant("(s)", (NAME,)), None,
                      Gio.DBusCallFlags.NO_AUTO_START, 2000, None)
    except GLib.Error:
        return True
    log("registered")
    return False


if register():
    GLib.timeout_add(200, register)
GLib.timeout_add_seconds(120, loop.quit)
loop.run()
log("exit")
