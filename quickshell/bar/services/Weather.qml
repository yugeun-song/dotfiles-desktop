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
