pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

// One screen's word to the video wallpaper's player (VideoWallpaper.qml):
// "play" while its desktop can be seen; "pause" once it cannot, which keeps
// the frame and costs no decoding; nothing after a minute of that, and the
// player lets the screen's window and decoder go, so hyprpaper's picture,
// the video's first frame, shows again.
//
// Seen: the screen lit (the screensaver's stage), the session unlocked, and
// its workspace without a tiled or fullscreen window (the widgets' rule,
// WidgetScreen.qml). No QtMultimedia here: the bar only decides.
Scope {
    id: root

    required property ShellScreen screen

    readonly property var monitor: Hyprland.monitorFor(root.screen)
    readonly property var workspace: root.monitor?.activeWorkspace ?? null

    // As WidgetScreen.covered: a window not described yet counts as tiled.
    readonly property bool covered: {
        const ws = root.workspace;
        if (!ws)
            return false;
        if (ws.hasFullscreen)
            return true;
        for (const t of ws.toplevels?.values ?? []) {
            const ipc = t.lastIpcObject;
            if (!ipc || typeof ipc.floating !== "boolean" || !ipc.floating || (ipc.fullscreen ?? 0) > 0)
                return true;
        }
        return false;
    }
    readonly property bool dark: (Screensaver.stages[root.screen?.name ?? ""] ?? "lit") !== "lit"
    readonly property bool seen: !root.covered && !root.dark && !KeyFeed.locked

    // Kept for a minute after it was last seen.
    property bool kept: false
    readonly property string mode: root.seen ? "play" : root.kept ? "pause" : ""

    Timer {
        id: letGo

        interval: 60000
        onTriggered: root.kept = false
    }

    onSeenChanged: {
        if (root.seen) {
            letGo.stop();
            root.kept = true;
        } else {
            letGo.restart();
        }
    }

    Component.onCompleted: root.kept = root.seen
}
