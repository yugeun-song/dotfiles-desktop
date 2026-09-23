pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Key presses for the on-screen overlay, read by scripts/keyfeed.py (evdev,
// needs the input group) over a JSON-lines protocol. Not named "Keys": that
// would shadow the attached type and break every Keys.onPressed.
Singleton {
    id: root

    // Off by default: an always-on reader is a keylogger nobody asked for.
    property bool enabled: false

    // {mods: [...], key: "C", id: n}
    property var chords: []

    readonly property int dwellMs: 500

    readonly property int maxVisible: 5

    // Keys Inter has no symbol for, drawn from the icon font instead. Modifier
    // and other key symbols live in Theme.modSymbol / Theme.keySymbol.
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

    // Tells KeyCap which font to use; the wrong one draws a box.
    function keyIsIcon(name) {
        return root.keyIcon[name] !== undefined;
    }

    // Printed order. The feed sends names; symbols are the shell's concern.
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
        // Overflow is cut without an exit animation; animating it kept its
        // width and stacked chords across the screen during fast typing.
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
            // Exit while enabled is a failure; surface it.
            root.failure = `the key feed exited with ${code}`;
            console.warn("[keyfeed]", root.failure);
            root.enabled = false;
        }
    }
}
