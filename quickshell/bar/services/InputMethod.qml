pragma Singleton

import Quickshell
import Quickshell.Io

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

    Process {
        running: true
        command: [Quickshell.shellPath("scripts/inputmethod.sh")]

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
