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

    // A helper that dies takes its pill's value with it, and a stale number
    // that still looks live is worse than an obviously missing one. So the
    // service says when it last heard anything, and brings the helper back.
    property bool stale: true
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
                // Clearing the state hides the pill instead of leaving a label
                // that claims hangul while the user is typing latin. The script
                // reprints the current state as soon as it comes back.
                root.stale = true;
                root.state = "";
                root.method = "";
                supervisor.restart();
            } else {
                root.stale = false;
            }
        }

        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split("\t");
                if (parts.length < 2)
                    return;
                root.state = parts[0];
                root.method = parts[1];
            }
        }
    }
}
