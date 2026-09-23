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
        ddcDetect.running = true;
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
                    const next = Object.assign({}, root.buses);
                    next[conn[1]] = ddcDetect.pendingBus;
                    root.buses = next;
                    ddcDetect.pendingBus = "";
                }
            }
        }

        onRunningChanged: {
            if (!ddcDetect.running) {
                root.detected = true;
                root.read();
            }
        }
    }

    // ---- reading --------------------------------------------------------

    function read() {
        if (!root.available)
            return;
        if (root.mechanism === "ddc")
            readDdc.command = ["ddcutil", "-b", root.buses[root.monitor], "getvcp", "10", "--brief"];
        else
            readDdc.command = ["sh", "-c", "brightnessctl -m | cut -d, -f4 | tr -d '%'"];
        readDdc.running = true;
    }

    Process {
        id: readDdc

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
            if (root.mechanism === "ddc")
                writeProc.command = ["ddcutil", "-b", root.buses[root.monitor], "setvcp", "10", String(root.pending)];
            else
                writeProc.command = ["brightnessctl", "--class", "backlight", "-q", "s", `${root.pending}%`];
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
