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

    readonly property bool fetching: fetch.running

    // The last complaint from weather.sh or curl ("Could not resolve host"),
    // cleared by a live reading; the tooltip shows it while the chip is stale.
    property string lastError: ""

    // Consecutive failures; drives the retry backoff so an early boot does
    // not wait for the next poll.
    property int failures: 0

    // What the current run printed, judged on its own: `data` keeps the last
    // payload, which after a run that printed nothing would speak for an
    // older one.
    property var received: null
    property bool refreshQueued: false

    // Wall-clock age at which the poll asks again. Above weather.sh's
    // 10-minute cache, so each poll reaches the network.
    readonly property int pollEvery: 900000

    // Success is the script's own `live` flag, not the payload's age: after a
    // hard power-off the clock runs on the last shutdown time until NTP
    // answers, so a stale cache served before that looked recent, no retry was
    // scheduled, and the chip went grey once the clock jumped ahead.
    function settle(): void {
        const got = root.received;
        root.received = null;
        if (got?.live === true) {
            root.failures = 0;
            root.lastError = "";
            retry.stop();
        } else {
            root.failures = Math.min(root.failures + 1, 5);
            retry.restart();
        }
        if (root.refreshQueued) {
            root.refreshQueued = false;
            root.start(true);
        }
    }

    function start(force: bool): void {
        if (fetch.running)
            return;
        root.received = null;
        fetch.command = [Quickshell.shellPath("scripts/weather.sh"), "--bar"].concat(force ? ["--refresh"] : []);
        fetch.running = true;
    }

    // The chip's click: past the cache and the backoff, now or right after the
    // run in flight.
    function refresh(): void {
        root.failures = 0;
        retry.stop();
        if (fetch.running)
            root.refreshQueued = true;
        else
            root.start(true);
    }

    // Refetch when the link comes up. If Net's backend is None (NetworkManager
    // absent at startup) this never fires and the retry backoff is the fallback.
    readonly property bool online: Net.wifiConnected || Net.wiredConnected

    // A new link starts the backoff over: failures from before it (a hotspot
    // still coming up at boot) would otherwise put the next try minutes away.
    onOnlineChanged: {
        if (!root.online)
            return;
        root.failures = 0;
        retry.stop();
        root.start(false);
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
                    const parsed = JSON.parse(trimmed);
                    root.data = parsed;
                    root.received = parsed;
                } catch (error) {
                    console.warn("[weather] could not parse:", trimmed);
                }
            }
        }

        // quickshell closes stderr unless something reads it.
        stderr: SplitParser {
            onRead: line => {
                console.warn("[weather]", line);
                if (line.trim() !== "")
                    root.lastError = line.trim();
            }
        }
    }

    Timer {
        id: retry

        interval: 30000 * Math.pow(2, root.failures - 1)
        repeat: false
        onTriggered: root.start(false)
    }

    // A minute's check against the wall clock instead of a 15-minute timer:
    // Qt's timers run on the monotonic clock, which stands still in suspend
    // and never sees NTP move the wall clock. A reading stamped more than a
    // minute in the future is as suspect as an old one.
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (fetch.running || retry.running)
                return;
            const age = Date.now() - root.asOf;
            if (!root.ready || age >= root.pollEvery || age < -60000)
                root.start(false);
        }
    }
}
