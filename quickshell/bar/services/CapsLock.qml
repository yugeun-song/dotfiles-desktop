pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool active: false

    // When `active` was last confirmed, which is not the same as when the
    // helper was last seen alive: capslock.sh prints only on a transition, so
    // silence is its normal state and liveness says nothing about the value.
    property double asOf: 0
    property int restarts: 0

    Timer {
        id: supervisor

        interval: 2000
        repeat: false
        onTriggered: {
            root.restarts = root.restarts + 1;
            console.warn("[capslock] helper exited, restart", root.restarts);
            poller.running = true;
        }
    }

    Process {
        id: poller

        running: true
        command: [Quickshell.shellPath("scripts/capslock.sh")]

        onRunningChanged: {
            if (!poller.running) {
                // `active` is kept, not cleared. Clearing it hid the pill,
                // which tells a user whose Caps Lock is on that it is off --
                // and that is the one answer the bar cannot be recovered from
                // by looking at it. Dropping the stamp instead leaves the pill
                // where it was, saying it no longer knows.
                root.asOf = 0;
                supervisor.restart();
            }
        }

        stdout: SplitParser {
            onRead: line => {
                const value = line.trim();
                if (value === "0" || value === "1") {
                    root.active = value === "1";
                    root.asOf = Date.now();
                    return;
                }
                // The script's third token, documented in its header: no LED
                // node was readable, which is what a keyboard mid-replug looks
                // like. Dropping it silently left the last state on screen as
                // though the script had just confirmed it.
                if (value === "-") {
                    root.asOf = 0;
                    return;
                }
                console.warn("[capslock] unexpected line:", value);
            }
        }
    }
}
