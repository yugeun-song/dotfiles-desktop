pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Not "InputMethod": QtQuick exports that name and silently shadows this
// singleton (empty label, "Unable to assign [undefined]").
Singleton {
    id: root

    property string state: ""
    property string method: ""

    readonly property bool present: root.state !== "" && root.state !== "none"

    // Keyboard layouts are always latin; for an IM, state 2 means converting,
    // which is the only way to tell Hangul from latin within fcitx5-hangul.
    readonly property bool hangul: root.present && !root.method.startsWith("keyboard") && root.state === "2"

    // State 0: no focused input context (video, viewer, browser outside a
    // field). Reads latin and dims; fcitx5 is fine, just not in the path.
    readonly property bool idle: root.state === "0"

    // Latin labels: a Hangul glyph falls back to another font and misaligns.
    readonly property string label: root.hangul ? "KR" : "EN"

    // Restart over D-Bus like the tray does; kill-and-relaunch loses the
    // running input contexts.
    function toggle() {
        Quickshell.execDetached(["fcitx5-remote", "-t"]);
    }

    function restart() {
        Quickshell.execDetached(["gdbus", "call", "--session", "--dest", "org.fcitx.Fcitx5", "--object-path", "/controller", "--method", "org.fcitx.Fcitx.Controller1.Restart"]);
    }

    // The only long-lived child here, so it goes through Apps; the one-shot
    // fcitx5-remote/gdbus calls stay on execDetached.
    function configure() {
        Apps.open(["fcitx5-configtool"]);
    }

    function reloadConfig() {
        Quickshell.execDetached(["fcitx5-remote", "-r"]);
    }

    // When state/method were last confirmed; 0 = unknown. The helper prints
    // only on change, so silence is normal.
    property double asOf: 0
    property int restarts: 0

    // Exponential backoff (2 s to 60 s): the helper exits at once when
    // fcitx5-remote is missing.
    Timer {
        id: supervisor

        property int delay: 2000

        interval: supervisor.delay
        repeat: false
        onTriggered: {
            root.restarts = root.restarts + 1;
            console.warn("[ime] helper exited, restart", root.restarts);
            supervisor.delay = Math.min(supervisor.delay * 2, 60000);
            poller.running = true;
        }
    }

    Process {
        id: poller

        running: true
        command: [Quickshell.shellPath("scripts/inputmethod.sh")]

        onRunningChanged: {
            if (!poller.running) {
                // Keep state (pill stays), mark it stale; hiding the pill
                // would claim there is no input method.
                root.asOf = 0;
                supervisor.restart();
            }
        }

        stdout: SplitParser {
            onRead: line => {
                // Any output resets the backoff.
                supervisor.delay = 2000;
                // Only the line ending is cut: trim() would also eat the tab
                // that ends "0<TAB>" (state 0, no engine name), leaving one
                // field and a spurious warning on every unfocused input.
                const raw = line.replace(/[\r\n]+$/, "");
                // "-": fcitx5 did not answer (not the same as "no IM").
                if (raw.trim() === "-") {
                    root.asOf = 0;
                    return;
                }
                // An empty engine name is valid; an empty state is not.
                const parts = raw.split("\t");
                if (parts.length !== 2 || parts[0] === "") {
                    console.warn("[ime] unexpected line:", raw);
                    return;
                }
                root.state = parts[0];
                root.method = parts[1];
                root.asOf = Date.now();
            }
        }
    }
}
