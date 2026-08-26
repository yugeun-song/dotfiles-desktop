pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Named Ime, not InputMethod. QtQuick exports a type called InputMethod, and
// any file importing QtQuick resolves that name to Qt's type instead of this
// singleton. The failure is silent: the pill renders with an empty label and
// a stray "Unable to assign [undefined]" in the log.
Singleton {
    id: root

    property string state: ""
    property string method: ""

    readonly property bool present: root.state !== "" && root.state !== "none"

    // A plain keyboard layout is always latin. Otherwise fcitx5 reports state
    // 2 while it is actively converting, which is what distinguishes 한 from
    // EN inside the same hangul input method.
    readonly property bool hangul: root.present && !root.method.startsWith("keyboard") && root.state === "2"

    readonly property string label: root.hangul ? "한" : "EN"

    // fcitx5-remote -t flips between converting and passthrough. Restart goes
    // through D-Bus because that is what the tray's own Restart does; killing
    // and relaunching the process loses the running input contexts.
    function toggle() {
        Quickshell.execDetached(["fcitx5-remote", "-t"]);
    }

    function restart() {
        Quickshell.execDetached(["gdbus", "call", "--session", "--dest", "org.fcitx.Fcitx5", "--object-path", "/controller", "--method", "org.fcitx.Fcitx.Controller1.Restart"]);
    }

    function configure() {
        Quickshell.execDetached(["fcitx5-configtool"]);
    }

    function reloadConfig() {
        Quickshell.execDetached(["fcitx5-remote", "-r"]);
    }

    // When state and method were last confirmed, which is not the same as when
    // the helper was last seen alive: the script prints only on a transition,
    // so silence is its normal condition and liveness says nothing about the
    // value. Zero means nothing has been accepted, and the pill says so.
    property double asOf: 0
    property int restarts: 0

    Timer {
        id: supervisor

        interval: 2000
        repeat: false
        onTriggered: {
            root.restarts = root.restarts + 1;
            console.warn("[ime] helper exited, restart", root.restarts);
            poller.running = true;
        }
    }

    Process {
        id: poller

        running: true
        command: [Quickshell.shellPath("scripts/inputmethod.sh")]

        onRunningChanged: {
            if (!poller.running) {
                // state is kept, so present stays true and the pill holds its
                // place saying it cannot read. Clearing it hid the pill, and a
                // pill that leaves reads as "there is no input method" -- a
                // different and equally wrong claim to the stale label this was
                // about avoiding. Dropping the stamp says neither.
                root.asOf = 0;
                supervisor.restart();
            }
        }

        stdout: SplitParser {
            onRead: line => {
                const raw = line.trim();
                // The script's no-reading token: fcitx5 did not answer, which
                // is not the same as it answering that no input method is on.
                if (raw === "-") {
                    root.asOf = 0;
                    return;
                }
                const parts = raw.split("\t");
                if (parts.length !== 2 || parts[0] === "" || parts[1] === "") {
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
