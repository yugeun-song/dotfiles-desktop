pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Key presses for the on-screen overlay, read by scripts/keyfeed.py (evdev,
// needs the input group) over a JSON-lines protocol. Not named "Keys": that
// would shadow the attached type and break every Keys.onPressed.
Singleton {
    id: root

    // Off until Super+Y turns it on, and on until Super+Y turns it off. Kept
    // in the state directory, outside the repository and the installed
    // config: held in memory only, every start or reload of the bar (a
    // reboot, install.sh) turned the overlay off behind the user's back. A
    // missing file is off: an always-on reader is a keylogger nobody asked
    // for.
    property bool enabled: false

    // Set by the first toggle, so a read landing after it does not undo it.
    property bool chosen: false

    // The reader sits on evdev, under the compositor, so it reads what is
    // typed into the lock screen too. The strip is not drawn over hyprlock,
    // but a chord younger than its dwell was drawn the moment the session
    // unlocked: the Enter and the last keys of the password. hypridle says
    // when the session locks and unlocks (on_lock_cmd, on_unlock_cmd), and
    // lock.sh as it starts hyprlock; keys in between are dropped. The unlock
    // comes from hypridle only: lock.sh also returns when hyprlock crashes
    // and the session stays locked.
    property bool locked: false

    IpcHandler {
        target: "keys"

        function lock(): void {
            root.locked = true;
            root.clear();
        }

        function unlock(): void {
            root.locked = false;
            root.clear();
        }
    }

    // With hypridle not running, no unlock would come and the overlay would
    // stay mute after the first lock. While locked, hyprlock is looked for
    // now and then, and its absence counts as the unlock.
    Timer {
        interval: 5000
        repeat: true
        running: root.locked

        onTriggered: {
            if (!lockProbe.running)
                lockProbe.running = true;
        }
    }

    Process {
        id: lockProbe

        command: ["pgrep", "-x", "hyprlock"]

        // pgrep: 0 found, 1 none.
        onExited: code => {
            if (code === 1 && root.locked) {
                root.locked = false;
                root.clear();
            }
        }
    }

    // {mods: [...], key: "C", id: n}. The only place keys are kept: at most
    // maxVisible, each dropped by its cap's exit (dwell plus the fall, under
    // a second), all of them on Super+Y off and on a lock or unlock. Nothing
    // reads them but the overlay.
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
        if (root.locked)
            return;
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
        root.chosen = true;
        root.enabled = !root.enabled;
        root.failure = "";
        supervisor.stop();
        supervisor.delay = 2000;
        if (!root.enabled)
            root.clear();
        store.setText(root.enabled ? "on\n" : "off\n");
    }

    FileView {
        id: store

        path: Paths.stateDir + "/keyoverlay"
        // A missing file is the default state, not an error worth a log line.
        printErrors: false

        onLoaded: {
            if (!root.chosen)
                root.enabled = store.text().trim() === "on";
        }
        onSaveFailed: error => console.warn("[keyfeed] could not keep the switch in", store.path, "-", error)
    }

    // A reader that dies while the overlay is on is started again, backing
    // off from 2 s to a minute like the other helpers. Switching the overlay
    // off at the first exit lost the user's choice and took down the strip
    // that would have said why; the strip now shows the reason until the
    // reader runs again or Super+Y turns the overlay off.
    Timer {
        id: supervisor

        property int delay: 2000

        interval: supervisor.delay
        onTriggered: {
            if (!root.enabled)
                return;
            supervisor.delay = Math.min(supervisor.delay * 2, 60000);
            feed.running = true;
            // Restored, or the reader would outlive Super+Y.
            feed.running = Qt.binding(() => root.enabled);
        }
    }

    Process {
        id: feed

        running: root.enabled
        // -I: no PYTHON* variables and no user site-packages, whose .pth
        // files would run inside the process holding the keyboard.
        command: ["python3", "-I", Quickshell.shellPath("scripts/keyfeed.py")]

        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (t === "")
                    return;
                let msg;
                try {
                    msg = JSON.parse(t);
                } catch (e) {
                    // Its length only: a line can carry a key, and the
                    // journal is kept on disk.
                    console.warn("[keyfeed] unparseable line of", t.length, "characters");
                    return;
                }
                // A reader that got this far works: the backoff starts over.
                // Not on an error line, which a failing reader sends just
                // before it exits.
                if (msg.type === "key") {
                    root.failure = "";
                    supervisor.delay = 2000;
                    root.push(msg.mods ?? [], msg.key ?? "?");
                } else if (msg.type === "ready") {
                    root.failure = "";
                    supervisor.delay = 2000;
                } else if (msg.type === "error") {
                    root.failure = msg.reason ?? "unknown";
                    console.warn("[keyfeed]", root.failure);
                }
            }
        }

        onExited: code => {
            if (!root.enabled)
                return;
            // The reader's own complaint, when it sent one, says more.
            if (root.failure === "")
                root.failure = `the key feed exited with ${code}`;
            console.warn("[keyfeed]", root.failure, "- retrying");
            supervisor.restart();
        }
    }
}
