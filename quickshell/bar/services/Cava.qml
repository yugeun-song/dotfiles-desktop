pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Driven by MediaChip: cava holds a capture stream, so only while playing.
    property bool active: false

    // Must match bars in cava.conf.
    readonly property int barCount: 22
    readonly property bool demo: Quickshell.env("BAR_VIZ_DEMO") === "1"

    property var levels: []
    property int restarts: 0

    // cava exits when its capture stream goes away (sink switch, PipeWire
    // restart); without this it stays dead until playback restarts.
    Timer {
        id: relaunch

        interval: 2000
        repeat: false
        onTriggered: {
            if (!root.active || root.demo)
                return;
            root.restarts = root.restarts + 1;
            console.warn("[cava] exited, restart", root.restarts);
            cava.running = true;
            // Restore the binding so cava still stops with playback.
            cava.running = Qt.binding(() => root.active && !root.demo);
        }
    }

    Process {
        id: cava

        running: root.active && !root.demo
        command: ["cava", "-p", Quickshell.shellPath("cava.conf")]

        onExited: {
            if (root.active && !root.demo)
                relaunch.restart();
        }

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
