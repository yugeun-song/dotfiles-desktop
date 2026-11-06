pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services

// A video on the desktop (the user, 2026-11-05: high resolution on the
// wallpaper too), where wallpaper.sh linked one beside the desktop's picture
// (current-desktop.video). hyprpaper keeps showing that picture, the video's
// first frame; a player of its own plays the video over it on each screen
// whose desktop can be seen, and rests where it cannot (VideoWallpaperSeat:
// a pause at once, the screen let go after a minute of it, the user's
// choice).
//
// The player is a process apart (videowall.qml), as the lock screen is:
// measured, a Quickshell that had played a video kept some 170 MiB of
// decoder libraries and heap after every player in it was gone, so only its
// end returns all of it. The bar decides, from what it already knows (the
// windows, the screensaver, the lock), and writes each screen's word to a
// file the player watches; it starts the player when a screen is to play
// and ends it once every screen has been let go.
//
// Nothing of it without a video: no seats, no file, no process. The link is
// read at the start and when wallpaper.sh says the desktop changed (`qs ipc
// call wallpaper changed`), never polled.
Scope {
    id: root

    readonly property string link: (Quickshell.env("HOME") ?? "") + "/Pictures/Wallpapers/current-desktop.video"
    property string video: ""

    function read(): void {
        reader.running = false;
        reader.running = true;
    }

    // readlink -e: the link's target, or nothing (exit 1) when the link or
    // the video it names is gone.
    Process {
        id: reader

        command: ["readlink", "-e", "--", root.link]

        stdout: StdioCollector {
            onStreamFinished: {
                const path = this.text.trim();
                if (path !== "")
                    root.video = path;
            }
        }

        onExited: code => {
            if (code !== 0)
                root.video = "";
        }
    }

    Component.onCompleted: root.read()

    IpcHandler {
        target: "wallpaper"

        // wallpaper.sh: the desktop's picture, and with it its video, changed.
        function changed(): void {
            root.read();
        }
    }

    // The seats' coverage reads the windows' IPC objects, which quickshell
    // reads only when asked: asked after each window or workspace event, a
    // moment later, and only while a video is set (as WidgetDesk does for
    // its widgets).
    readonly property var windowEvents: ["openwindow", "closewindow", "changefloatingmode", "movewindowv2",
                                         "fullscreen", "workspacev2", "focusedmonv2"]

    Connections {
        target: Hyprland
        enabled: root.video !== ""

        function onRawEvent(event) {
            if (root.windowEvents.indexOf(event.name) !== -1)
                refresh.restart();
        }
    }

    Timer {
        id: refresh

        interval: 120
        onTriggered: Hyprland.refreshToplevels()
    }

    onVideoChanged: {
        if (root.video !== "")
            Hyprland.refreshToplevels();
    }

    // ---- each screen's word ------------------------------------------------
    // "play" or "pause" by screen name; a screen let go is not in it.
    property var modes: ({})

    function setMode(name: string, mode: string): void {
        if ((root.modes[name] ?? "") === mode)
            return;
        const next = Object.assign({}, root.modes);
        if (mode === "")
            delete next[name];
        else
            next[name] = mode;
        root.modes = next;
    }

    Variants {
        model: root.video !== "" ? Quickshell.screens : []

        VideoWallpaperSeat {
            id: seat

            required property ShellScreen modelData

            screen: modelData
            onModeChanged: root.setMode(seat.modelData.name, seat.mode)
            Component.onCompleted: root.setMode(seat.modelData.name, seat.mode)
            Component.onDestruction: root.setMode(seat.modelData.name, "")
        }
    }

    readonly property bool wanted: root.video !== "" && Object.keys(root.modes).length > 0

    // Private to the user and gone with the session (the runtime directory).
    FileView {
        id: stateFile

        path: Paths.runtimeDir === "" ? "" : Paths.runtimeDir + "/quickshell-video.json"
        printErrors: false
    }

    function publish(): void {
        if (stateFile.path !== "")
            stateFile.setText(JSON.stringify({ source: root.video, screens: root.modes }) + "\n");
    }

    onModesChanged: root.publish()

    // A player an earlier bar left (one killed outright cannot end its child)
    // is ended first, so there is only ever this one.
    Process {
        id: player

        running: root.wanted && stateFile.path !== ""
        command: ["sh", "-c", 'qs kill -p "$1" >/dev/null 2>&1; exec qs -n -p "$1"', "sh",
                  Quickshell.shellPath("videowall.qml")]
        environment: ({ VIDEO_STATE: stateFile.path })

        onRunningChanged: {
            if (player.running)
                root.publish();
        }
        onExited: code => {
            if (root.wanted && code !== 0)
                console.warn("[video-wallpaper] the player ended", code);
        }
    }
}
