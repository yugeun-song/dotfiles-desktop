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

    // Exits within this of a start, this many times in a row, mean cava is
    // missing or cannot open a stream at all; then it is left alone (the
    // meter stays empty) instead of being respawned every two seconds for
    // as long as anything plays.
    readonly property int quickExitMs: 1500
    readonly property int giveUpAfter: 3
    property int quickExits: 0
    property double startedAt: 0
    readonly property bool givenUp: root.quickExits >= root.giveUpAfter

    // cava exits when its capture stream goes away (sink switch, PipeWire
    // restart); without this it stays dead until playback restarts.
    Timer {
        id: relaunch

        interval: 2000
        repeat: false
        onTriggered: {
            if (!root.active || root.demo || root.givenUp)
                return;
            root.restarts = root.restarts + 1;
            console.warn("[cava] exited, restart", root.restarts);
            cava.running = true;
            // Restore the binding so cava still stops with playback.
            cava.running = Qt.binding(() => root.active && !root.demo && !root.givenUp);
        }
    }

    Process {
        id: cava

        running: root.active && !root.demo && !root.givenUp
        command: ["cava", "-p", Quickshell.shellPath("cava.conf")]

        onStarted: root.startedAt = Date.now()

        // An exit while inactive is the bar stopping cava (playback paused),
        // not a failure, and must not count towards giving up.
        onExited: {
            if (!root.active || root.demo)
                return;
            if (Date.now() - root.startedAt < root.quickExitMs) {
                root.quickExits = root.quickExits + 1;
                if (root.givenUp)
                    console.warn("[cava] exited at once", root.giveUpAfter, "times; not installed or no capture stream, giving up");
            } else {
                root.quickExits = 0;
            }
            if (!root.givenUp)
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
