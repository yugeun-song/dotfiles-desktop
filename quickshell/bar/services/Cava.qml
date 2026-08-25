pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // cava runs only while something is actually playing. Leaving it running
    // holds a PipeWire capture stream open and burns CPU for nothing.
    property bool active: false

    readonly property int barCount: 12
    readonly property bool demo: Quickshell.env("BAR_VIZ_DEMO") === "1"

    property var levels: []

    Process {
        id: cava

        running: root.active && !root.demo
        command: ["cava", "-p", Quickshell.shellPath("cava.conf")]

        stdout: SplitParser {
            onRead: data => {
                const parsed = data.split(";").map(v => parseFloat(v)).filter(v => !isNaN(v));
                if (parsed.length > 0)
                    root.levels = parsed;
            }
        }

        onRunningChanged: {
            if (!cava.running)
                root.levels = [];
        }
    }

    // Synthetic spectrum for laying the widget out without playing anything.
    Timer {
        running: root.demo
        interval: 60
        repeat: true
        onTriggered: {
            const out = [];
            for (let i = 0; i < root.barCount; ++i) {
                const shape = Math.sin(i / root.barCount * Math.PI);
                out.push(Math.round(shape * (35 + Math.random() * 65)));
            }
            root.levels = out;
        }
    }
}
