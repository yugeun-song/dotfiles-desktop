pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.services

// Calls under way, for the island (MediaChip.qml), shown the way what plays
// is (the user, 2026-10-26: Zoom, then Discord). Told by no program's name,
// as the share is (ScreenShare.qml): a call is a program recording from an
// audio source in PipeWire's graph (scripts/share-apps.py --mic), so a
// meeting in a browser counts too, named and drawn by its desktop entry. A
// Recorder is left to its own part (Obs.qml: OBS holds the microphone for its
// meters either way); a program with no entry (a helper, a sound server) is
// no call.
//
// No microphone switch or light (the user, 2026-10-27): a program's own mute
// is told to nothing outside it (Zoom records on through it), so one here
// could only be the system's microphone, which read as the call's and
// disagreed with it.
Singleton {
    id: root

    // The programs linked to an audio source, by node id, off PipeWire's own
    // events (no poll); a change sends the lookup off. A source is an audio
    // node that sends and is no program's stream (a microphone or a filter's
    // virtual one); a sink's monitor, which cava records from, is none.
    readonly property string streams: {
        const ids = [];
        const sends = t => (t & PwNodeType.AudioSource) === PwNodeType.AudioSource && (t & PwNodeType.Stream) === 0;
        for (const g of Pipewire.linkGroups.values) {
            if (g?.source && g?.target && sends(g.source.type) && g.target.type === PwNodeType.AudioInStream)
                ids.push(g.target.id);
        }
        return ids.sort((a, b) => a - b).join(",");
    }

    // What the lookup printed, and the calls as the island shows them: one
    // { key, name, icon, cls, since } per program, the longest first.
    property var found: []
    readonly property var apps: root.looks(root.found, DesktopEntries.applications.values.length, root.started)
    readonly property bool active: root.apps.length > 0
    readonly property real since: root.apps.reduce((first, a) => first === 0 || a.since < first ? a.since : first, 0)

    // When each program's call began, by key: kept across reloads, since
    // install.sh reloads the bar and a call's clock started again at zero.
    property var started: ({})

    PersistentProperties {
        id: kept

        reloadableId: "calls"

        property string started: "{}"

        onLoaded: {
            try {
                const value = JSON.parse(kept.started);
                root.started = value !== null && typeof value === "object" ? value : {};
            } catch (e) {
                root.started = {};
            }
        }
    }

    onStartedChanged: kept.started = JSON.stringify(root.started)

    onStreamsChanged: Qt.callLater(root.find)
    Component.onCompleted: Qt.callLater(root.find)

    // A change while the lookup runs sends it off once more after.
    property bool findAgain: false

    function find(): void {
        if (root.streams === "") {
            root.found = [];
            root.started = {};
            return;
        }
        if (lookup.running)
            root.findAgain = true;
        else
            lookup.running = true;
    }

    Process {
        id: lookup

        command: ["python3", "-I", "-S", Quickshell.shellPath("scripts/share-apps.py"), "--mic"]

        stdout: StdioCollector {
            onStreamFinished: {
                let found = [];
                try {
                    found = JSON.parse(this.text);
                } catch (e) {
                    console.warn("[calls] the lookup printed no list");
                }
                if (!Array.isArray(found) || root.streams === "")
                    found = [];
                root.found = found;
                // A program first seen now starts its clock; one gone loses it.
                const now = Date.now();
                const started = {};
                for (const p of found) {
                    const key = root.keyOf(p);
                    if (key !== "")
                        started[key] = root.started[key] ?? now;
                }
                if (JSON.stringify(started) !== JSON.stringify(root.started))
                    root.started = started;
            }
        }

        onExited: {
            const again = root.findAgain;
            root.findAgain = false;
            if (again)
                lookup.running = true;
        }
    }

    function keyOf(p: var): string {
        return String(p?.class || p?.binary || p?.name || "");
    }

    // The lookup's programs that are calls, named and drawn by their desktop
    // entries: the window's class first, then what PipeWire calls the
    // program. `entries` is only there to look again when their number
    // changes: they are not read yet when a reload finds a call going on.
    function looks(found: var, entries: int, started: var): var {
        const out = [];
        for (const p of found) {
            if (p === null || typeof p !== "object")
                continue;
            const names = [p.class, p.binary, p.name].filter(s => typeof s === "string" && s !== "");
            const entry = names.map(s => DesktopEntries.heuristicLookup(s)).find(e => e) ?? null;
            if (entry === null || Array.from(entry.categories ?? []).indexOf("Recorder") !== -1)
                continue;
            const key = root.keyOf(p);
            if (out.some(a => a.name === entry.name))
                continue;
            const icon = entry.icon ?? "";
            out.push({
                key: key,
                name: entry.name || p.name || p.binary || "",
                icon: icon.startsWith("/") ? `file://${icon}` : icon !== "" ? Quickshell.iconPath(icon, true) : "",
                cls: String(p.class || entry.startupClass || ""),
                entry: entry,
                since: started[key] ?? Date.now()
            });
        }
        return out.sort((a, b) => a.since - b.since);
    }

    // The clock, read again on each whole second of the longest call.
    property real now: Date.now()

    Timer {
        id: tick

        onTriggered: root.ticked()
    }

    function ticked(): void {
        root.now = Date.now();
        if (!root.active) {
            tick.stop();
            return;
        }
        tick.interval = 1000 - (root.now - root.since) % 1000 + 20;
        tick.restart();
    }

    onActiveChanged: root.ticked()
    onSinceChanged: root.ticked()

    // The call's window brought forward: the program's last-opened window,
    // which for a meeting is the meeting's. One with no window (Discord in
    // its tray) is started again from its entry, which brings it back.
    function show(app: var): void {
        const cls = String(app?.cls ?? "").toLowerCase();
        const mine = ToplevelManager.toplevels.values.filter(t => cls !== "" && String(t.appId ?? "").toLowerCase() === cls);
        if (mine.length > 0)
            mine[mine.length - 1].activate();
        else
            app?.entry?.execute();
    }
}
