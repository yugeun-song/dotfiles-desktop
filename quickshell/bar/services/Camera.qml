pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The camera switch (camera/camera-switch.py) as the bar shows it: a glyph
// while the cameras are off, nothing while they are on or there are none.
//
// The reading is `camera-switch status --json`, which needs no root, and it
// is taken on events only, never on a clock:
//   start         the bar starts or reloads
//   camera.sh     after every key press (qs ipc call camera refresh)
//   devices       udevadm monitor: a capture node or USB interface came,
//                 went, bound or unbound, whoever caused it (a key, a
//                 camera-switch run in a terminal, a plug, udev's enforce)
//   switch file   /var/lib/camera-switch/off appeared or went: a run that
//                 changed no device sends no device event
// A burst of events is one read, 300 ms after the first. A reading taken
// while a camera-switch holds its lock pairs the new switch position with
// devices not yet switched (it flashed "a camera is on" in red during every
// off), so it is kept off the screen and the read repeats every half second,
// then every five, until the lock is free. A failed read leaves the last
// good one on screen and is retried after 2 s, doubling to a minute. While
// udevadm is down device events stop, and a read every five minutes stands
// in until it is back.
//
//   switch  cameras                                  bar
//   -       no reading yet, or nothing installed     nothing
//   on      every one on, or none                    nothing
//   off     none, and no firmware camera switch      nothing
//   off     every one off, or only a firmware one    glyph
//   off     one still on: the switch did not hold    glyph in red
//   on      one still off: turning on failed         glyph in amber
Singleton {
    id: root

    // The last reading believed: parsed status JSON, null before the first.
    property var reading: null
    // Why the last read failed; empty once one succeeds.
    property string failure: ""
    // False when no camera-switch is installed: nothing to watch or show.
    property bool installed: true

    readonly property string state: root.classify(root.reading)
    readonly property bool shown: root.state === "off" || root.state === "leak" || root.state === "stuck"

    // The system copy first (the one udev's rule runs), then the user copy
    // install.sh puts in ~/.local/bin. The variables point tests at stand-ins.
    readonly property string program: Quickshell.env("CAMERA_SWITCH_SYSTEM") || "/usr/local/bin/camera-switch"
    readonly property string switchPath: Quickshell.env("CAMERA_SWITCH_FILE") || "/var/lib/camera-switch/off"

    function classify(r): string {
        if (!r || typeof r !== "object" || !Array.isArray(r.cameras))
            return "unknown";
        const switches = Array.isArray(r.power_switches) ? r.power_switches : [];
        const live = r.cameras.filter(c => c.state !== "off");
        if (r.switch === "off") {
            if (live.length > 0)
                return "leak";
            return r.cameras.length === 0 && switches.length === 0 ? "none" : "off";
        }
        const dark = r.cameras.filter(c => c.state === "off");
        return dark.length > 0 || switches.some(s => s.state === "off") ? "stuck" : "on";
    }

    // Any event: one read shortly after the first of a burst.
    function changed(): void {
        if (root.installed && !settle.running)
            settle.start();
    }

    // camera.sh's call: the action is over, read now.
    function refresh(): void {
        root.installed = true;
        settle.stop();
        root.read();
    }

    // At most one read runs; asked for meanwhile, one more follows it.
    property bool queued: false
    property var received: null
    property int busyReads: 0
    property int failures: 0

    function read(): void {
        if (status.running) {
            root.queued = true;
            return;
        }
        root.received = null;
        status.running = true;
    }

    function finish(code: int): void {
        const got = root.received;
        root.received = null;
        if (code === 127) {
            root.installed = false;
            root.reading = null;
            root.failure = "";
            root.queued = false;
            retry.stop();
            busy.stop();
            return;
        }
        root.installed = true;
        if (code !== 0 || got === null || typeof got !== "object" || !Array.isArray(got.cameras)) {
            root.failure = code !== 0 ? `camera-switch status exited with ${code}` : "camera-switch status printed no reading";
            root.failures = Math.min(root.failures + 1, 6);
            retry.restart();
        } else if (got.busy === true) {
            root.busyReads += 1;
            busy.restart();
        } else {
            root.reading = got;
            root.failure = "";
            root.failures = 0;
            root.busyReads = 0;
            retry.stop();
            busy.stop();
            // A watch set while /var/lib/camera-switch did not exist yet
            // sees nothing; a reading that disagrees with it sets it again.
            if ((got.switch === "off") !== switchFile.present) {
                switchFile.path = "";
                switchFile.path = root.switchPath;
            }
        }
        if (root.queued) {
            root.queued = false;
            root.read();
        }
    }

    IpcHandler {
        target: "camera"

        function refresh(): void {
            root.refresh();
        }

        // What the bar concluded (unknown, on, none, off, leak, stuck), for
        // a check that should not need a screenshot.
        function state(): string {
            return root.state;
        }
    }

    Component.onCompleted: root.read()

    Process {
        id: status

        command: ["sh", "-c", "for p in \"$1\" \"$HOME/.local/bin/camera-switch\"; do [ -x \"$p\" ] && exec \"$p\" status --json; done; exit 127",
            "camera-status", root.program]

        // Deferred so finish() sees what this run printed.
        onExited: code => Qt.callLater(root.finish, code)

        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (t === "")
                    return;
                try {
                    root.received = JSON.parse(t);
                } catch (e) {
                    console.warn("[camera] unparseable status:", t.slice(0, 120));
                }
            }
        }

        stderr: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    console.warn("[camera]", line.trim());
            }
        }
    }

    Timer {
        id: settle

        interval: 300
        onTriggered: root.read()
    }

    // Twenty tries half a second apart cover a normal action, the device
    // probe after `on` included; a lock held longer is checked every 5 s.
    Timer {
        id: busy

        interval: root.busyReads <= 20 ? 500 : 5000
        onTriggered: root.read()
    }

    Timer {
        id: retry

        interval: Math.min(2000 * Math.pow(2, Math.max(root.failures - 1, 0)), 60000)
        onTriggered: root.read()
    }

    // --udev: the event after udev's rules ran, so a camera plugged in while
    // the switch is off is read once enforce has turned it off.
    Process {
        id: monitor

        running: root.installed
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=video4linux", "--subsystem-match=usb/usb_interface"]

        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("UDEV ")) {
                    supervisor.delay = 2000;
                    root.changed();
                } else if (line.startsWith("monitor will print") && supervisor.restarted) {
                    // Back after an exit: what changed meanwhile was missed.
                    supervisor.restarted = false;
                    root.changed();
                }
            }
        }

        onExited: code => {
            if (!root.installed)
                return;
            console.warn("[camera] udevadm monitor exited with", code, "- restarting");
            supervisor.restart();
        }
    }

    // As the key reader's: 2 s, doubling to a minute.
    Timer {
        id: supervisor

        property int delay: 2000
        property bool restarted: false

        interval: supervisor.delay
        onTriggered: {
            if (!root.installed)
                return;
            supervisor.delay = Math.min(supervisor.delay * 2, 60000);
            supervisor.restarted = true;
            monitor.running = true;
            // Restored, or the monitor would outlive an uninstall.
            monitor.running = Qt.binding(() => root.installed);
        }
    }

    Timer {
        interval: 300000
        repeat: true
        running: root.installed && !monitor.running
        onTriggered: root.read()
    }

    FileView {
        id: switchFile

        property bool present: false

        path: root.switchPath
        watchChanges: root.installed
        // Absent is the switch being on, not an error.
        printErrors: false

        onLoaded: switchFile.present = true
        onLoadFailed: switchFile.present = false
        onFileChanged: {
            switchFile.reload();
            root.changed();
        }
    }
}
