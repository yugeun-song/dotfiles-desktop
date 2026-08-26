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
    readonly property int dwellMs: 2000

    readonly property int maxVisible: 5

    // A hard ceiling on what is on screen, counting the ones playing their exit.
    // maxVisible alone bounds only the live ones, and an exit takes about half a
    // second, so typing faster than that stacked five live chords on top of
    // however many were still falling and the row grew across the screen.
    // Past this the oldest is cut rather than asked to leave: at that rate
    // nobody is reading the animation anyway.
    readonly property int maxOnScreen: root.maxVisible * 2

    // The shortest gap allowed between two departures. Each chord already has
    // its own timer started when it arrived, but typing puts five of them
    // inside a couple of hundred milliseconds, so five timers fire inside a
    // couple of hundred milliseconds and the stack looks like it emptied at
    // once. Holding each exit this far behind the one before it lets a burst
    // unravel in the order it was typed.
    readonly property int minGapMs: 130

    // When the chord scheduled furthest out is due to leave. A new arrival is
    // scheduled after it rather than a flat dwell from now, which is what keeps
    // the departures in arrival order.
    property real lastLeaveAt: 0

    // The symbols every printed keyboard shortcut has used for decades. They
    // are not in the Nerd Font the icons come from, but they are in Inter,
    // which is what the caps already draw their labels with.
    //
    // Super takes the diamond rather than the command glyph: this is Linux, and
    // U+2318 means Command on a Mac. Borrowing it would be saying the wrong
    // thing in a symbol chosen for being unambiguous.
    readonly property var modSymbol: ({
        "Ctrl":  "\u2303",
        "Alt":   "\u2325",
        "Shift": "\u21E7",
        "Super": "\u2756"
    })

    // The keys that have had a printed symbol longer than they have had a name.
    // Every codepoint here was checked against Inter, which is what the caps
    // draw with; the ones Inter does not carry, Home and End among them, keep
    // their words rather than becoming a box.
    readonly property var keySymbol: ({
        "Enter":     "\u23CE",
        "Tab":       "\u21E5",
        "Backspace": "\u232B",
        "Del":       "\u2326",
        "Esc":       "\u238B",
        "Space":     "\u2423",
        "Caps":      "\u21EA",
        "PgUp":      "\u21DE",
        "PgDn":      "\u21DF",
        "Up":        "\u2191",
        "Down":      "\u2193",
        "Left":      "\u2190",
        "Right":     "\u2192"
    })

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
        return root.keyIcon[name] ?? root.keySymbol[name] ?? name;
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
                out += root.modSymbol[order[i]];
        return out;
    }

    property int nextId: 0
    property string failure: ""

    // Chords that have been asked to leave but are still on screen playing the
    // exit. Cutting one out of the model instead would make it disappear where
    // every other one falls, and the difference is exactly what a viewer reads
    // as the drawing having glitched.
    property var expiring: []

    readonly property bool running: feed.running

    function push(mods, key) {
        const now = Date.now();
        let leaveAt = now + root.dwellMs;
        if (leaveAt < root.lastLeaveAt + root.minGapMs)
            leaveAt = root.lastLeaveAt + root.minGapMs;
        root.lastLeaveAt = leaveAt;

        root.chords = root.chords.concat([{
            mods: mods, key: key, id: root.nextId, leaveAt: leaveAt
        }]);
        root.nextId = root.nextId + 1;

        // Count only the ones not already on their way out, or a burst of keys
        // would ask the same chord to leave several times over and the ones
        // behind it would never be asked at all.
        const live = [];
        for (let i = 0; i < root.chords.length; i++)
            if (root.expiring.indexOf(root.chords[i].id) === -1)
                live.push(root.chords[i]);
        if (live.length > root.maxVisible)
            root.expiring = root.expiring.concat([live[0].id]);

        while (root.chords.length > root.maxOnScreen) {
            const gone = root.chords[0].id;
            root.chords = root.chords.slice(1);
            const still = [];
            for (let i = 0; i < root.expiring.length; i++)
                if (root.expiring[i] !== gone)
                    still.push(root.expiring[i]);
            root.expiring = still;
        }
    }

    function drop(id) {
        const next = [];
        for (let i = 0; i < root.chords.length; i++)
            if (root.chords[i].id !== id)
                next.push(root.chords[i]);
        root.chords = next;

        const still = [];
        for (let i = 0; i < root.expiring.length; i++)
            if (root.expiring[i] !== id)
                still.push(root.expiring[i]);
        root.expiring = still;
    }

    function clear() {
        root.chords = [];
        root.expiring = [];
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
