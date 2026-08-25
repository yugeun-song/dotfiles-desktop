pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool active: false

    // A helper that dies takes its pill's value with it, and a stale number
    // that still looks live is worse than an obviously missing one. So the
    // service says when it last heard anything, and brings the helper back.
    property bool stale: true
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
                // The pill is dropped rather than left lit: the script only
                // prints on a transition, so the last value it sent says
                // nothing about the key once the script is gone.
                root.stale = true;
                root.active = false;
                supervisor.restart();
            } else {
                root.stale = false;
            }
        }

        stdout: SplitParser {
            onRead: line => {
                const value = line.trim();
                if (value === "0" || value === "1")
                    root.active = value === "1";
            }
        }
    }
}
