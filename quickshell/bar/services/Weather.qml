pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    // Location is configured in scripts/weather.sh (fixed coordinates).
    property var data: null

    readonly property bool ready: root.data !== null

    // Payload's own fetch time (ms). weather.sh may serve a stale cache and
    // still exit 0, so arrival time says nothing about freshness.
    readonly property double asOf: (root.data?.fetched ?? 0) * 1000

    readonly property string place: root.data?.place ?? ""

    // Out-of-range sentinels for missing fields; 0 would read as real weather.
    readonly property int code: root.data?.code ?? -1
    readonly property int temp: root.data?.temp ?? -999
    readonly property int feels: root.data?.feels ?? -999
    readonly property int humidity: root.data?.humidity ?? -1
    readonly property real wind: root.data?.wind ?? -1
    readonly property bool dayKnown: typeof root.data?.day === "number"
    readonly property bool day: root.data?.day === 1
    readonly property int todayMin: root.data?.today?.min ?? -999
    readonly property int todayMax: root.data?.today?.max ?? -999

    // Checks only what the pill face shows (code, temp, day flag); tooltip
    // fields are checked where they print. `day` is a bool with no sentinel,
    // so a missing is_day is caught via dayKnown.
    readonly property string unknown: {
        if (!root.ready)
            return "";
        if (root.code < 0)
            return "The feed carried no weather code";
        if (root.temp <= -999)
            return "The feed carried no temperature";
        if (!root.dayKnown)
            return "The feed carried no day-or-night flag";
        return "";
    }

    // Consecutive failures; drives the retry backoff so an early boot does
    // not wait for the 15-minute tick.
    property int failures: 0

    // Just above weather.sh's 10-minute cache; older means stale fallback.
    readonly property int liveWithin: 660000

    // Judge success by payload age, not exit code: the stale-cache fallback
    // exits 0.
    function settle(): void {
        if (root.ready && Date.now() - root.asOf < root.liveWithin) {
            root.failures = 0;
            return;
        }
        root.failures = Math.min(root.failures + 1, 5);
        retry.restart();
    }

    // Refetch when the link comes up. If Net's backend is None (NetworkManager
    // absent at startup) this never fires and the retry backoff is the fallback.
    readonly property bool online: Net.wifiConnected || Net.wiredConnected

    onOnlineChanged: {
        if (root.online)
            fetch.running = true;
    }

    Process {
        id: fetch

        command: [Quickshell.shellPath("scripts/weather.sh"), "--bar"]

        // Deferred so settle() sees the payload this run printed.
        onExited: Qt.callLater(root.settle)

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

        // quickshell closes stderr unless something reads it.
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

    // Above the script's 10-minute cache; faster polls would only hit it.
    Timer {
        interval: 900000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: fetch.running = true
    }
}
