pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    // The location lives in scripts/weather.sh, not here. Editing that one
    // file changes the city for both the bar and the command line, and the
    // script asks Open-Meteo by coordinate so nothing infers a location.
    property var data: null

    readonly property bool ready: root.data !== null

    // When the reading was obtained, in ms, taken from the payload rather than
    // from the moment the line arrived. weather.sh serves a ten-minute cache
    // and, when a fetch fails, falls back to an older one and still exits 0 --
    // so a line arriving says the script ran, never that the sky was looked
    // at. The script has published this field all along for exactly this.
    readonly property double asOf: (root.data?.fetched ?? 0) * 1000

    readonly property string place: root.data?.place ?? ""

    // Sentinels rather than plausible numbers. A field the payload did not
    // carry used to read as 0°, 0% and 0 km/h, which are all weather; is_day
    // defaulting to 1 asserted daylight, which is a sun glyph at midnight.
    // Nothing below is a value the sky can take.
    readonly property int code: root.data?.code ?? -1
    readonly property int temp: root.data?.temp ?? -999
    readonly property int feels: root.data?.feels ?? -999
    readonly property int humidity: root.data?.humidity ?? -1
    readonly property real wind: root.data?.wind ?? -1
    readonly property bool dayKnown: typeof root.data?.day === "number"
    readonly property bool day: root.data?.day === 1
    readonly property int todayMin: root.data?.today?.min ?? -999
    readonly property int todayMax: root.data?.today?.max ?? -999

    // Only what the pill's face claims: the glyph and the colour are chosen
    // from code and day together, the label carries temp. A bool has no
    // sentinel to hold a missing is_day, so it is refused here instead --
    // otherwise `day` would just assert night where it used to assert noon.
    //
    // The tooltip-only fields are absent on purpose; they are checked where
    // they print, so one missing figure does not blank a readable sky.
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

    // Consecutive failed fetches, used to space out the retries. A boot that
    // beats NetworkManager to the network would otherwise leave the pill absent
    // until the next 15-minute tick.
    property int failures: 0

    // The age past which a served reading is not a live one. weather.sh caches
    // for ten minutes, so a cache hit lands under this and is still a success;
    // anything older came from the stale fallback.
    readonly property int liveWithin: 660000

    // A fetch that fails and falls back to an older cache still exits 0 and
    // still prints a payload -- that is what keeps the last known value on the
    // bar while the network is down. So the exit code says the script ran, not
    // that the sky was read; only the payload's own timestamp says that. Judged
    // on the code alone, the ladder below never armed in the one case it was
    // written for, because a cache from the previous session is almost always
    // there to fall back on, and the pill sat at "?" until the next 15-minute
    // tick however early the network came back.
    function settle(): void {
        if (root.ready && Date.now() - root.asOf < root.liveWithin) {
            root.failures = 0;
            return;
        }
        root.failures = Math.min(root.failures + 1, 5);
        retry.restart();
    }

    // NetworkManager finishing after the bar is the ordinary shape of a login,
    // so the link coming up is the signal to try again rather than the next
    // tick. Net picks its backend once, at startup, and reads None when
    // NetworkManager was not running then; nothing here fires in that case and
    // the ladder is the only way back, which is why it is still a ladder.
    readonly property bool online: Net.wifiConnected || Net.wiredConnected

    onOnlineChanged: {
        if (root.online)
            fetch.running = true;
    }

    Process {
        id: fetch

        command: [Quickshell.shellPath("scripts/weather.sh"), "--bar"]

        // Deferred, so the run is judged against the payload this run printed
        // rather than the one before it.
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
