pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// What the keyboard is doing, for the on-screen visualiser.
//
// Named KeyFeed and not Keys: Keys is a built-in QML attached type, and a
// singleton of that name shadows it everywhere, so every Keys.onPressed in the
// shell stops resolving and the whole configuration fails to load.
//
// The reading happens in scripts/keyfeed.py because evdev is a binary stream
// and QML has no business parsing struct input_event. That script is the only
// part of this that needs a permission, and the permission is membership of the
// input group rather than root.
//
// The two halves talk in JSON lines on stdout. That seam is deliberate: a Rust
// binary printing the same lines would drop in without a change here.
Singleton {
    id: root

    // Off unless asked for. A visualiser that runs all the time is a keylogger
    // nobody switched on, and it holds three device descriptors to do it.
    property bool enabled: false

    // The chords on screen. Each is {mods: [...], key: "C", id: n}.
    property var chords: []

    // Long enough to read a chord that went past quickly, short enough that the
    // overlay is gone before it becomes furniture.
    readonly property int dwellMs: 500

    readonly property int maxVisible: 5

    // The symbols every printed keyboard shortcut has used for decades. They
    // are not in the Nerd Font the icons come from, but they are in Inter,
    // which is what the caps already draw their labels with.
    //
    // Super takes the diamond rather than the command glyph: this is Linux, and
    // U+2318 means Command on a Mac. Borrowing it would be saying the wrong
    // thing in a symbol chosen for being unambiguous.
    // The tables moved to Theme, which is where both drawers of them can
    // reach without reaching this file's device reader as well.

    // The keys Inter has no symbol for. These come from the icon font instead,
    // and every one is a codepoint Theme already draws somewhere in the bar, so
    // it has been looked at on a screen rather than guessed from a table.
    readonly property var keyIcon: ({
        "Playpause":  Theme.iconPlay,
        "Play":       Theme.iconPlay,
        "Pause":      Theme.iconPause,
        "Nextsong":   Theme.iconNext,
        "Previoussong": Theme.iconPrev,
        "Stopcd":     Theme.iconStop,
        "Mute":       Theme.iconVolumeOff,
        "Volumedown": Theme.iconVolumeLow,
        "Volumeup":   Theme.iconVolume,
        "Brightnessdown": Theme.iconBrightness,
        "Brightnessup":   Theme.iconBrightness,
        "Power":      Theme.iconPower,
        "Sleep":      Theme.iconSleep,
        "Search":     Theme.iconSearch,
        "Compose":    Theme.iconApps
    })

    function keyLabel(name) {
        return root.keyIcon[name] ?? Theme.keySymbol[name] ?? name;
    }

    // Which family draws it. A glyph from the icon font rendered in Inter is a
    // box, and the reverse loses the symbol's proportions, so the label has to
    // say where it came from.
    function keyIsIcon(name) {
        return root.keyIcon[name] !== undefined;
    }

    // Ctrl, Alt, Shift, Super, which is the order they are printed in and so
    // the order they are read in. The feed sends names; assembling them is the
    // shell's job, so that replacing the reader leaves this table alone.
    function symbolsFor(mods) {
        const order = ["Ctrl", "Alt", "Shift", "Super"];
        let out = "";
        for (let i = 0; i < order.length; i++)
            if (mods.indexOf(order[i]) !== -1)
                out += Theme.modSymbol[order[i]];
        return out;
    }

    property int nextId: 0
    property string failure: ""

    readonly property bool running: feed.running

    function push(mods, key) {
        const next = root.chords.concat([{ mods: mods, key: key, id: root.nextId }]);
        root.nextId = root.nextId + 1;
        // Cut, not asked to leave. Marking the oldest and letting it play an
        // exit kept its width while it fell, so typing faster than the
        // animation stacked chords across the screen; scheduling the
        // departures apart from each other to unstack them was a second queue
        // on top of the first. A chord shows for its dwell and goes.
        while (next.length > root.maxVisible)
            next.shift();
        root.chords = next;
    }

    function drop(id) {
        const next = [];
        for (let i = 0; i < root.chords.length; i++)
            if (root.chords[i].id !== id)
                next.push(root.chords[i]);
        root.chords = next;
    }

    function clear() {
        root.chords = [];
    }

    function toggle() {
        root.enabled = !root.enabled;
        if (!root.enabled)
            root.clear();
    }

    Process {
        id: feed

        running: root.enabled
        command: ["python3", Quickshell.shellPath("scripts/keyfeed.py")]

        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (t === "")
                    return;
                let msg;
                try {
                    msg = JSON.parse(t);
                } catch (e) {
                    // A line that will not parse means the two halves disagree
                    // about the protocol, which is worth one warning and not a
                    // silent drop.
                    console.warn("[keyfeed] unparseable line:", t);
                    return;
                }
                if (msg.type === "key") {
                    root.failure = "";
                    root.push(msg.mods ?? [], msg.key ?? "?");
                } else if (msg.type === "ready") {
                    root.failure = "";
                } else if (msg.type === "error") {
                    root.failure = msg.reason ?? "unknown";
                    console.warn("[keyfeed]", root.failure);
                }
            }
        }

        onExited: code => {
            if (!root.enabled)
                return;
            // Exiting while still switched on is a failure, not a stop. Saying
            // so beats an overlay that is on and silent.
            root.failure = `the key feed exited with ${code}`;
            console.warn("[keyfeed]", root.failure);
            root.enabled = false;
        }
    }
}
