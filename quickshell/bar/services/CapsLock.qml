pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool active: false

    // When `active` was last confirmed. The helper prints only on change, so
    // silence is normal.
    property double asOf: 0
    property int restarts: 0

    // Exponential backoff (2 s to 60 s): the helper never exits by itself, so
    // repeated exits mean it cannot run here.
    Timer {
        id: supervisor

        property int delay: 2000

        interval: supervisor.delay
        repeat: false
        onTriggered: {
            root.restarts = root.restarts + 1;
            console.warn("[capslock] helper exited, restart", root.restarts);
            supervisor.delay = Math.min(supervisor.delay * 2, 60000);
            poller.running = true;
        }
    }

    Process {
        id: poller

        running: true
        command: [Quickshell.shellPath("scripts/capslock.sh")]

        onRunningChanged: {
            if (!poller.running) {
                // Keep `active`, mark it stale: hiding the pill would claim
                // Caps Lock is off.
                root.asOf = 0;
                supervisor.restart();
            }
        }

        stdout: SplitParser {
            onRead: line => {
                // Any output resets the backoff.
                supervisor.delay = 2000;
                const value = line.trim();
                if (value === "0" || value === "1") {
                    root.active = value === "1";
                    root.asOf = Date.now();
                    return;
                }
                // "-": no LED node readable (keyboard mid-replug); unknown.
                if (value === "-") {
                    root.asOf = 0;
                    return;
                }
                console.warn("[capslock] unexpected line:", value);
            }
        }
    }
}
