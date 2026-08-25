pragma Singleton

import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool active: false

    Process {
        running: true
        command: [Quickshell.shellPath("scripts/capslock.sh")]

        stdout: SplitParser {
            onRead: line => {
                const value = line.trim();
                if (value === "0" || value === "1")
                    root.active = value === "1";
            }
        }
    }
}
