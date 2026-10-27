pragma Singleton

import QtQuick
import Quickshell
import qs.services

// Not "InputMethod": QtQuick exports that name and silently shadows this
// singleton (empty label, "Unable to assign [undefined]"). The readings come
// from the input helper (InputWatch).
Singleton {
    id: root

    readonly property string state: InputWatch.imeState
    readonly property string method: InputWatch.imeMethod

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

    // When state/method were last confirmed; 0 = unknown. Kept, not
    // cleared, when unknown: hiding the pill would claim there is no input
    // method. The helper prints only on change, so silence is normal.
    readonly property double asOf: InputWatch.imeAsOf

    // Every reading from the helper, the answer to ask() or a change it saw.
    signal answered()

    Connections {
        target: InputWatch

        function onImeAnswered() {
            root.answered();
        }
    }

    // A reading now instead of at the next poll, for the key overlay
    // (KeyFeed), which holds a letter back until the answer: the poll's last
    // reading can be 0.3 s old. The line carries no key, only the moment.
    // False with no helper to ask.
    function ask(): bool {
        return InputWatch.ask();
    }
}
