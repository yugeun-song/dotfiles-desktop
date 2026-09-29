pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// The screensaver's per-display setting: after how many minutes without input
// on a display its saver comes up, 0 for never. Off everywhere by default, on
// this machine and on the next one: the file is state (XDG_STATE_HOME), never
// installed or tracked, and a missing file means off. The Displays panel
// writes it; modules/ScreensaverWindows.qml reads the resolved minutes from here.
//
// One line per display, <selector> TAB <minutes>, the selector as in the
// monitor overrides: the description as `hyprctl monitors` prints it with
// commas dropped (so it follows the display across connectors), or
// name:<connector>. A description line wins over a name: line for the same
// output, as override_for in monitors.lua resolves them. Comments and lines
// that do not parse are kept as they are, so a hand edit is never lost to the
// panel's next write.
Singleton {
    id: root

    readonly property string stateDir: {
        const configured = Quickshell.env("XDG_STATE_HOME");
        if (configured)
            return configured + "/quickshell/bar";
        const home = Quickshell.env("HOME");
        return (home ? home : "") + "/.local/state/quickshell/bar";
    }
    readonly property string file: root.stateDir + "/screensaver"

    // A timer under a minute would fire from the pauses within ordinary use;
    // above a day it is off in all but name.
    readonly property int minMinutes: 1
    readonly property int maxMinutes: 1440
    // What "on" means before a choice is made: the panel's + from Off.
    readonly property int defaultMinutes: 5
    // The panel's - and + walk this list; the wheel moves by one minute.
    readonly property var steps: [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240]

    // [{ selector, minutes }] in file order, and the lines kept verbatim.
    property var entries: []
    property var kept: []
    property string error: ""

    // Minutes per connector for every monitor the compositor lists, rebuilt
    // whenever the file or the monitor set changes. A property rather than a
    // function for the module's bindings: a singleton's functions are not
    // always callable when a window's first binding runs at start.
    readonly property var minutesByName: {
        const out = {};
        for (const m of Hyprland.monitors.values) {
            const n = root.minutesOf(m.name, root.normalize(m.description));
            if (n > 0)
                out[m.name] = n;
        }
        return out;
    }

    function normalize(description) {
        return String(description ?? "").replace(/,/g, "").trim();
    }

    function minutesOf(name, description) {
        let byName = 0;
        let byDescription = 0;
        for (const e of root.entries) {
            if (e.selector === "name:" + name)
                byName = e.minutes;
            else if (description !== "" && e.selector === description)
                byDescription = e.minutes;
        }
        return byDescription > 0 ? byDescription : byName;
    }

    function parse(text) {
        const entries = [];
        const kept = [];
        for (const raw of String(text).split("\n")) {
            const line = raw.replace(/\r$/, "");
            if (line.trim() === "")
                continue;
            const at = line.indexOf("\t");
            const minutes = at > 0 ? Number(line.slice(at + 1).trim()) : NaN;
            if (line.startsWith("#") || at <= 0 || !Number.isInteger(minutes)
                || minutes < root.minMinutes || minutes > root.maxMinutes) {
                if (!line.startsWith("#"))
                    console.warn(`[screensaver] ${root.file}: kept but ignored: ${line}`);
                kept.push(line);
                continue;
            }
            entries.push({ selector: line.slice(0, at), minutes: minutes });
        }
        root.entries = entries;
        root.kept = kept;
    }

    // Writes several displays' minutes in one go (0 removes a display's
    // line). Each change names its selector and the other selectors that
    // speak for the same output (`aliases`), which are dropped so the new
    // line is the only one.
    function setMany(changes) {
        let next = root.entries;
        for (const c of changes) {
            const drop = [c.selector].concat(c.aliases ?? []);
            next = next.filter(e => drop.indexOf(e.selector) === -1);
            const n = Math.round(Number(c.minutes) || 0);
            if (n >= root.minMinutes)
                next.push({ selector: c.selector, minutes: Math.min(root.maxMinutes, n) });
        }
        let text = "";
        for (const line of root.kept)
            text += line + "\n";
        for (const e of next)
            text += `${e.selector}\t${e.minutes}\n`;
        root.error = "";
        // In force from here; the write is the record, and the watcher's
        // reload of what was written changes nothing.
        root.entries = next;
        store.setText(text);
    }

    FileView {
        id: store

        path: root.file
        watchChanges: true
        // A missing file is the default state, not an error worth a log line.
        printErrors: false

        onLoaded: root.parse(store.text())
        onLoadFailed: {
            root.entries = [];
            root.kept = [];
        }
        onFileChanged: store.reload()
        onSaveFailed: error => {
            root.error = `could not write ${root.file} (${error}); bin/bar creates its directory`;
            console.warn("[screensaver]", root.error);
        }
    }
}
