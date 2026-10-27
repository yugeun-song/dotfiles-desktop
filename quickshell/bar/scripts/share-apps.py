#!/usr/bin/env python3
"""Which programs are taking the screen, for the island's share
(services/ScreenShare.qml): Hyprland's screencastv2 event says what is
shared, never by whom.

Found in PipeWire's graph, with no list of applications. A share through the
desktop portal (a call in Discord or Zoom, a browser's) is a stream:
xdg-desktop-portal-hyprland makes a Video/Source node of the screen and the
sharing program links a node of its own to it. So the sharers are the far
ends of links from a Video/Source no device backs (a camera's node carries
device.id). A node's own application.* keys win over its client's, which
PipeWire fills from the process.

The class comes from the window of the stream's process or its nearest
ancestor with one, since a program may stream from a child; the bar takes
the icon and name from the desktop entry that class names.

With --mic, the programs taking a microphone instead, for the island's
calls (services/Calls.qml): the far ends of links from an Audio/Source node.
A sink's monitor, which cava records from, is a port of an Audio/Sink and no
source here.

stdout: one JSON array, one {"class", "binary", "name"} per program; empty
when none is found, as for a recorder that copies the screen through
Hyprland itself (wf-recorder, OBS's wlrobs), which has no stream. Window
titles are read to match nothing and printed nowhere.

Run when what it answers changes, not on a timer: pw-dump takes 15 ms and
prints about 300 kB, and parsing it as much again.
"""

import json
import subprocess
import sys

# Deeper than any launcher, sandbox and helper chain seen; a loop in a
# racing /proc read cannot outlast it.
MAX_ANCESTORS = 32


def props(obj):
    return ((obj or {}).get("info") or {}).get("props") or {}


def is_screen(node):
    return props(node).get("media.class") == "Video/Source" and "device.id" not in props(node)


def is_microphone(node):
    return str(props(node).get("media.class", "")).startswith("Audio/Source")


def screen_streams(objects):
    """The programs linked to a screen, as {pid, binary, name}."""
    return linked_streams(objects, is_screen)


def mic_streams(objects):
    """The programs linked to a microphone, as {pid, binary, name}."""
    return linked_streams(objects, is_microphone)


def linked_streams(objects, is_source):
    nodes, clients = {}, {}
    for obj in objects:
        kind = obj.get("type")
        if kind == "PipeWire:Interface:Node":
            nodes[obj.get("id")] = obj
        elif kind == "PipeWire:Interface:Client":
            clients[obj.get("id")] = obj
    sources = {node_id for node_id, node in nodes.items() if is_source(node)}
    found = []
    for obj in objects:
        if obj.get("type") != "PipeWire:Interface:Link":
            continue
        info = obj.get("info") or {}
        if info.get("output-node-id") not in sources:
            continue
        node = nodes.get(info.get("input-node-id"))
        if node is None:
            continue
        keys = dict(props(clients.get(props(node).get("client.id"))))
        keys.update({k: v for k, v in props(node).items() if k.startswith("application.")})
        try:
            pid = int(keys.get("application.process.id", 0))
        except (TypeError, ValueError):
            pid = 0
        found.append({
            "pid": pid,
            "binary": str(keys.get("application.process.binary", "")),
            "name": str(keys.get("application.name", "")),
        })
    return found


def ppid_in(stat):
    # The command name is in parentheses and may hold any character, these
    # included; the parent's pid is the second field after it.
    fields = stat[stat.rfind(")") + 2:].split()
    try:
        return int(fields[1])
    except (IndexError, ValueError):
        return 0


def parent_of(pid):
    try:
        with open(f"/proc/{pid}/stat", encoding="utf-8", errors="replace") as fh:
            return ppid_in(fh.read())
    except OSError:
        return 0


def window_class(pid, windows, parent=parent_of):
    """The class of the window owned by pid or its nearest ancestor that has one."""
    seen = set()
    while pid > 1 and pid not in seen and len(seen) < MAX_ANCESTORS:
        if pid in windows:
            return windows[pid]
        seen.add(pid)
        pid = parent(pid)
    return ""


def sharers(objects, windows, parent=parent_of, streams=screen_streams):
    """One entry per program: a call's several streams name it once."""
    out, keys = [], set()
    for stream in streams(objects):
        entry = {
            "class": window_class(stream["pid"], windows, parent) if stream["pid"] > 0 else "",
            "binary": stream["binary"],
            "name": stream["name"],
        }
        key = entry["class"] or entry["binary"] or entry["name"]
        if key == "" or key in keys:
            continue
        keys.add(key)
        out.append(entry)
    return out


def read_json(argv):
    try:
        done = subprocess.run(argv, capture_output=True, timeout=5, check=False)
        return json.loads(done.stdout or b"null")
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None


def main(argv):
    streams = mic_streams if argv[1:] == ["--mic"] else screen_streams
    objects = read_json(["pw-dump"])
    clients = read_json(["hyprctl", "-j", "clients"])
    windows = {}
    for client in clients if isinstance(clients, list) else []:
        pid, cls = client.get("pid"), client.get("class") or client.get("initialClass") or ""
        if isinstance(pid, int) and pid > 0 and cls and pid not in windows:
            windows[pid] = cls
    found = sharers(objects if isinstance(objects, list) else [], windows, streams=streams)
    print(json.dumps(found), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
