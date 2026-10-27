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

    // Checks only what the pill face shows (code, temp, day flag). `day` is a
    // bool with no sentinel, so a missing is_day is caught via dayKnown.
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

    // Consecutive failures; drives the retry backoff so an early boot does
    // not wait for the next poll.
    property int failures: 0

    // What the current run printed, judged on its own: `data` keeps the last
    // payload, which after a run that printed nothing would speak for an
    // older one.
    property var received: null

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
            retry.stop();
        } else {
            root.failures = Math.min(root.failures + 1, 5);
            retry.restart();
        }
        if (root.kickQueued) {
            root.kickQueued = false;
            // The run in flight went out before the network was usable.
            if (got?.live !== true) {
                retry.stop();
                root.start();
            }
        }
    }

    function start(): void {
        if (fetch.running)
            return;
        root.received = null;
        fetch.running = true;
    }

    // A link coming up, and the internet answering on it, each start the
    // backoff over and fetch: failures from before (no network at boot, DNS
    // not up yet when the link came) had put the next try minutes away. One
    // arriving during a fetch is kept for its end, when that fetch failed. If
    // Net's backend is None (NetworkManager absent at startup) neither fires
    // and the retry backoff is the fallback.
    readonly property bool online: Net.wifiConnected || Net.wiredConnected
    readonly property bool reachable: Net.reachable
    property bool kickQueued: false

    function kick(): void {
        root.failures = 0;
        retry.stop();
        if (fetch.running)
            root.kickQueued = true;
        else
            root.start();
    }

    onOnlineChanged: {
        if (root.online)
            root.kick();
    }
    onReachableChanged: {
        if (root.reachable)
            root.kick();
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
                    // Its length only: the line is the script's, and the
                    // journal keeps what is logged.
                    console.warn("[weather] could not parse a line of", trimmed.length, "characters");
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
        onTriggered: root.start()
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
                root.start();
        }
    }
}
