pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services

// The screen shares under way, for the island (MediaChip.qml; the user,
// 2026-10-25: Discord or Zoom, web Zoom included, little per program) and
// for the screensaver (ScreensaverDpms.qml), which keeps a shared display up.
//
// What is shared comes from Hyprland's screencastv2 event, which names no
// program: the portal copies through the compositor for every program that
// shares by it, a browser or a recorder as much as Discord. Any screencopy,
// a screenshot too, reads as a share until half a second after its last
// frame, so a share counts once it has lasted (Theme.shareLastsMs). Keyed
// "monitor,<output>" or "region,<output>" as the event gives them, and
// "window," for every window share: Hyprland names one by the title as of
// its next resize, so it may stop under another name. A program that copies
// the screen any other way is not seen.
//
// Who shares comes from PipeWire, by no name either (scripts/share-apps.py),
// looked up when the lasting shares change.
Singleton {
    id: root

    // { key: { since, count } }: when the first share under the key began,
    // and how many are on (one start and one stop each).
    property var shares: ({})
    // Those that have lasted, as { type, name, since }, set after active,
    // since and kind so that its handlers find them set: as bindings on it
    // they read stale there, and the clock and the lookup never started.
    property var lasting: []
    property bool active: false
    // When the longest share still on began; the island's clock runs from it.
    property real since: 0
    // What the island says is shared: a whole screen before a window before
    // a part of a screen.
    property string kind: ""

    // The clock, read again on each whole second of the share.
    property real now: Date.now()

    // How long, as m:ss, and h:mm:ss past an hour (Theme's, which the
    // island's calls and recordings share).
    function clockText(ms: real): string {
        return Theme.clockText(ms);
    }

    // The programs the lookup printed, and who shares as the bar shows them:
    // { name, icon } from each program's desktop entry, empty until found
    // and when nothing is. Looked up again once the entries have been read,
    // which they are not yet when a reload finds a share going on.
    property var found: []
    readonly property var apps: root.looks(root.found, DesktopEntries.applications.values.length)

    // Kept across reloads: install.sh reloads the bar, and a new instance
    // forgot a share in progress, whose display could then go dark under the
    // call. A JSON string, as in Notifications.qml.
    PersistentProperties {
        id: kept

        reloadableId: "screenShare"

        property string shares: "{}"

        onLoaded: {
            root.shares = root.parseObject(kept.shares);
            root.settle();
        }
    }

    onSharesChanged: kept.shares = JSON.stringify(root.shares)

    function parseObject(text: string): var {
        try {
            const value = JSON.parse(text);
            return value !== null && typeof value === "object" ? value : {};
        } catch (e) {
            return {};
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "screencastv2")
                root.take(String(event.data));
        }
    }

    // One event's data, "<1|0>,<type>,<name>"; a window title may hold commas.
    function take(data: string): void {
        const a = data.indexOf(",");
        const b = a < 0 ? -1 : data.indexOf(",", a + 1);
        if (b < 0)
            return;
        const type = data.slice(a + 1, b);
        const key = type === "window" ? "window," : data.slice(a + 1);
        const next = Object.assign({}, root.shares);
        const entry = next[key];
        if (data.slice(0, a) === "1") {
            next[key] = entry ? { since: entry.since, count: entry.count + 1 } : { since: Date.now(), count: 1 };
        } else if (entry) {
            // A stop with no start seen began before this instance.
            if (entry.count > 1)
                next[key] = { since: entry.since, count: entry.count - 1 };
            else
                delete next[key];
        }
        root.shares = next;
        root.settle();
    }

    Timer {
        id: settleTimer

        onTriggered: root.settle()
    }

    function settle(): void {
        const now = Date.now();
        const lasting = [];
        let wait = 0;
        for (const key of Object.keys(root.shares)) {
            const since = root.shares[key].since;
            const left = Theme.shareLastsMs - (now - since);
            if (left <= 0) {
                const at = key.indexOf(",");
                lasting.push({ type: key.slice(0, at), name: key.slice(at + 1), since: since });
            } else if (wait === 0 || left < wait) {
                wait = left;
            }
        }
        // Only a real change: every one sends the lookup off again.
        if (JSON.stringify(lasting) !== JSON.stringify(root.lasting)) {
            root.active = lasting.length > 0;
            root.since = lasting.reduce((first, s) => first === 0 || s.since < first ? s.since : first, 0);
            root.kind = ["monitor", "window", "region"].find(t => lasting.some(s => s.type === t)) ?? "";
            root.lasting = lasting;
        }
        if (wait > 0) {
            settleTimer.interval = wait + 50;
            settleTimer.restart();
        }
    }

    // On the share's own seconds, so the island's clock never skips one.
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

    onLastingChanged: {
        root.ticked();
        if (!root.active) {
            root.found = [];
            return;
        }
        root.find();
    }

    // A change while the lookup runs sends it off once more after.
    property bool findAgain: false

    function find(): void {
        if (lookup.running)
            root.findAgain = true;
        else
            lookup.running = true;
    }

    Process {
        id: lookup

        command: ["python3", "-I", "-S", Quickshell.shellPath("scripts/share-apps.py")]

        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.active)
                    return;
                let found = [];
                try {
                    found = JSON.parse(this.text);
                } catch (e) {
                    console.warn("[share] the lookup printed no list");
                }
                root.found = Array.isArray(found) ? found : [];
                const names = root.apps.map(a => a.name).join(", ");
                console.info(`[share] ${root.kind}: ${names !== "" ? names : "no program in PipeWire"}`);
            }
        }

        onExited: {
            const again = root.findAgain;
            root.findAgain = false;
            if (again && root.active)
                lookup.running = true;
        }
    }

    // The lookup's programs, named and drawn by their desktop entries: the
    // window's class first, then what PipeWire calls the program. An entry
    // may name its icon by a file's path, which no theme lookup finds.
    // `entries` is only there to look again when their number changes.
    function looks(found: var, entries: int): var {
        return found.filter(p => p !== null && typeof p === "object").map(p => {
            const names = [p.class, p.binary, p.name].filter(s => typeof s === "string" && s !== "");
            const entry = names.map(s => DesktopEntries.heuristicLookup(s)).find(e => e) ?? null;
            const icon = entry?.icon ?? "";
            return {
                name: entry?.name || p.name || p.binary || p.class || "",
                icon: icon.startsWith("/") ? `file://${icon}` : icon !== "" ? Quickshell.iconPath(icon, true) : ""
            };
        }).filter(a => a.name !== "");
    }
}
