pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Screen brightness across two very different mechanisms.
//
// An internal panel has a backlight class device and responds instantly. An
// external monitor has neither; it is driven over DDC/CI on the i2c bus behind
// the video cable, which is slow and occasionally just does not answer.
//
// Measured on this machine: `ddcutil detect` takes 717 ms, a getvcp 75 ms.
// So detection runs once at startup and writes are coalesced, because holding
// a brightness key would otherwise queue dozens of half-second round trips
// and the display would keep stepping long after the key came up.
Singleton {
    id: root

    property int percent: -1          // -1 until something is known
    property var buses: ({})          // connector name -> i2c bus number
    property bool hasBacklight: false
    property bool detected: false

    readonly property string monitor: Hyprland.focusedMonitor?.name ?? ""

    readonly property string mechanism: {
        if (root.buses[root.monitor] !== undefined)
            return "ddc";
        if (root.hasBacklight)
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

        // --brief keeps the output to the two lines that matter and cuts the
        // run time roughly in half.
        command: ["ddcutil", "detect", "--brief"]

        property string pendingBus: ""

        stdout: SplitParser {
            onRead: line => {
                const bus = line.match(/\/dev\/i2c-(\d+)/);
                if (bus) {
                    ddcDetect.pendingBus = bus[1];
                    return;
                }
                const conn = line.match(/DRM connector:\s+card\d+-(\S+)/);
                if (conn && ddcDetect.pendingBus !== "") {
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
                    const max = Number(vcp[2]) || 100;
                    root.percent = Math.round(Number(vcp[1]) / max * 100);
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

    // Not zero. A backlight at zero is a panel that shows nothing, and the way
    // back is a key on a screen that cannot be read. One percent is still dark
    // enough to be the bottom of the range and leaves the screen legible.
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
        // Before the first read there is nothing to step from; ask, and let
        // the next press act on a real number rather than guessing.
        if (root.percent < 0) {
            root.read();
            return;
        }
        root.set(root.percent + delta);
    }

    // One write per idle period rather than one per key repeat.
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

    // The focused monitor can change under us. What was a DDC bus a moment
    // ago may now be a backlight device, and the cached percentage belongs to
    // the other screen.
    onMonitorChanged: {
        root.percent = -1;
        if (root.detected)
            root.read();
    }
}
