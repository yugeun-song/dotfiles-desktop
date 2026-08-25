pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // The location lives in scripts/weather.sh, not here. Editing that one
    // file changes the city for both the bar and the command line, and the
    // script asks Open-Meteo by coordinate so nothing infers a location.
    property var data: null

    readonly property bool ready: root.data !== null
    readonly property string place: root.data?.place ?? ""
    readonly property int code: root.data?.code ?? -1
    readonly property int temp: root.data?.temp ?? 0
    readonly property int feels: root.data?.feels ?? 0
    readonly property int humidity: root.data?.humidity ?? 0
    readonly property real wind: root.data?.wind ?? 0
    readonly property bool day: (root.data?.day ?? 1) === 1
    readonly property int todayMin: root.data?.today?.min ?? 0
    readonly property int todayMax: root.data?.today?.max ?? 0

    // Consecutive failed fetches, used to space out the retries. A boot that
    // beats NetworkManager to the network would otherwise leave the pill absent
    // until the next 15-minute tick.
    property int failures: 0

    Process {
        id: fetch

        command: [Quickshell.shellPath("scripts/weather.sh"), "--bar"]

        onExited: code => {
            if (code === 0) {
                root.failures = 0;
                return;
            }
            root.failures = Math.min(root.failures + 1, 5);
            retry.restart();
        }

        stdout: SplitParser {
            onRead: line => {
                const trimmed = line.trim();
                if (trimmed === "")
                    return;
                try {
                    root.data = JSON.parse(trimmed);
                } catch (error) {
                    console.warn("[weather] could not parse:", trimmed);
                }
            }
        }

        // curl and jq write their diagnosis here, and quickshell closes the
        // channel outright unless something is reading it.
        stderr: SplitParser {
            onRead: line => console.warn("[weather]", line)
        }
    }

    Timer {
        id: retry

        interval: 30000 * Math.pow(2, root.failures - 1)
        repeat: false
        onTriggered: fetch.running = true
    }

    // The script caches for 15 minutes of its own accord, so polling more
    // often would only re-read the cache.
    Timer {
        interval: 900000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: fetch.running = true
    }
}
