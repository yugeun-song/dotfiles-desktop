pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Brightness of the focused monitor: sysfs backlight for the internal panel,
// DDC/CI over i2c for externals. DDC is slow (detect ~0.7 s, getvcp ~75 ms
// here), so detection runs once and writes are coalesced, or a held key
// queues round trips that keep stepping after release.
Singleton {
    id: root

    property int percent: -1          // -1 until something is known
    property var buses: ({})          // connector name -> i2c bus number
    property bool hasBacklight: false
    property bool detected: false

    readonly property string monitor: Hyprland.focusedMonitor?.name ?? ""

    // The backlight is used only when the internal panel is focused, or a key
    // on a non-DDC external would dim the laptop instead.
    function isInternal(name) {
        return /^(eDP|LVDS|DSI)(-|$)/.test(name);
    }

    readonly property string mechanism: {
        if (root.buses[root.monitor] !== undefined)
            return "ddc";
        if (root.hasBacklight && (root.monitor === "" || root.isInternal(root.monitor)))
            return "backlight";
        return "";
    }

    readonly property bool available: root.mechanism !== ""

    signal changed

    // ---- detection ------------------------------------------------------

    Component.onCompleted: {
        backlightProbe.running = true;
        root.detect();
    }

    // When detection last finished, for the retry in step().
    property double lastDetect: 0

    function detect() {
        if (ddcDetect.running) {
            redetect.restart();
            return;
        }
        ddcDetect.found = {};
        ddcDetect.pendingBus = "";
        ddcDetect.pendingUsable = false;
        ddcDetect.running = true;
    }

    // Detection ran once, at the start: an external connected later, or one
    // back from a dropped link on another bus, had no bus and its keys did
    // nothing until the bar restarted. It runs again once a monitor comes or
    // goes, after the newcomer has had time to answer DDC.
    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "monitoraddedv2" || event.name === "monitorremovedv2")
                redetect.restart();
        }
    }

    Timer {
        id: redetect

        interval: 3000
        onTriggered: root.detect()
    }

    Process {
        id: backlightProbe

        command: ["sh", "-c", "ls /sys/class/backlight/ 2>/dev/null | head -1"]

        stdout: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    root.hasBacklight = true;
            }
        }
    }

    Process {
        id: ddcDetect

        // --brief roughly halves the run time.
        command: ["ddcutil", "detect", "--brief"]

        property string pendingBus: ""
        property bool pendingUsable: false
        // Filled during a run and swapped in at its end, so the map in use
        // never empties while ddcutil probes.
        property var found: ({})

        stdout: SplitParser {
            onRead: line => {
                // Honour the "Display N" / "Invalid display" verdict: the laptop
                // panel is enumerated on i2c but does not answer DDC, and
                // recording its bus would bypass its backlight.
                const head = line.trim();
                if (/^Display\s+\d+/.test(head)) {
                    ddcDetect.pendingUsable = true;
                    ddcDetect.pendingBus = "";
                    return;
                }
                if (/^Invalid display/.test(head)) {
                    ddcDetect.pendingUsable = false;
                    ddcDetect.pendingBus = "";
                    return;
                }
                const bus = line.match(/\/dev\/i2c-(\d+)/);
                if (bus) {
                    ddcDetect.pendingBus = bus[1];
                    return;
                }
                const conn = line.match(/DRM connector:\s+card\d+-(\S+)/);
                if (conn && ddcDetect.pendingBus !== "" && ddcDetect.pendingUsable) {
                    const next = Object.assign({}, ddcDetect.found);
                    next[conn[1]] = ddcDetect.pendingBus;
                    ddcDetect.found = next;
                    ddcDetect.pendingBus = "";
                }
            }
        }

        onRunningChanged: {
            if (!ddcDetect.running) {
                root.buses = ddcDetect.found;
                root.detected = true;
                root.lastDetect = Date.now();
                root.read();
            }
        }
    }

    // ---- reading --------------------------------------------------------

    // The bus is read once here and checked: between a focus change and this
    // call the map can lack the new monitor, and an undefined bus reached
    // ddcutil as the word "undefined" (one journal line per such read).
    function read() {
        if (!root.available)
            return;
        const bus = root.buses[root.monitor];
        if (root.mechanism === "ddc") {
            if (bus === undefined)
                return;
            readProc.command = ["ddcutil", "-b", String(bus), "getvcp", "10", "--brief"];
        } else {
            readProc.command = ["sh", "-c", "brightnessctl -m | cut -d, -f4 | tr -d '%'"];
        }
        readProc.running = true;
    }

    Process {
        id: readProc

        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (t === "")
                    return;
                // ddcutil --brief prints: VCP 10 C <current> <max>
                const vcp = t.match(/^VCP\s+10\s+\S+\s+(\d+)\s+(\d+)/);
                if (vcp) {
                    // Reject max <= 0 and clamp: monitors can report current > max.
                    const max = Number(vcp[2]);
                    if (!Number.isFinite(max) || max <= 0) {
                        console.warn("[brightness] unusable VCP max:", t);
                        return;
                    }
                    root.percent = Math.max(0, Math.min(100, Math.round(Number(vcp[1]) / max * 100)));
                    return;
                }
                const plain = Number(t);
                if (!isNaN(plain))
                    root.percent = Math.max(0, Math.min(100, Math.round(plain)));
            }
        }
    }

    // ---- writing --------------------------------------------------------

    property int pending: -1

    // Not zero: a backlight at zero is a black panel.
    readonly property int floorPercent: 1

    function set(value) {
        if (!root.available)
            return;
        root.percent = Math.max(root.floorPercent, Math.min(100, Math.round(value)));
        root.changed();
        root.pending = root.percent;
        coalesce.restart();
    }

    function step(delta) {
        // An external that slept through detection (switched off and on by
        // hand, which is no hotplug) has no bus: look again, at most every
        // half minute, and let a later press act.
        if (!root.available && root.monitor !== "" && !root.isInternal(root.monitor)) {
            if (Date.now() - root.lastDetect > 30000)
                root.detect();
            return;
        }
        // Nothing to step from yet: read, and let the next press act.
        if (root.percent < 0) {
            root.read();
            return;
        }
        root.set(root.percent + delta);
    }

    Timer {
        id: coalesce

        interval: 120
        onTriggered: {
            if (root.pending < 0 || !root.available)
                return;
            const bus = root.buses[root.monitor];
            if (root.mechanism === "ddc") {
                if (bus === undefined) {
                    root.pending = -1;
                    return;
                }
                writeProc.command = ["ddcutil", "-b", String(bus), "setvcp", "10", String(root.pending)];
            } else {
                writeProc.command = ["brightnessctl", "--class", "backlight", "-q", "s", `${root.pending}%`];
            }
            root.pending = -1;
            writeProc.running = true;
        }
    }

    Process {
        id: writeProc
    }

    // The cached value belongs to the previous screen and maybe mechanism.
    onMonitorChanged: {
        root.percent = -1;
        if (root.detected)
            root.read();
    }
}
