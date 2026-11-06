import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules

// The video wallpaper's player (modules/VideoWallpaper.qml), a process apart
// from the bar: the bar starts it when a screen is to play and ends it once
// every screen has been let go, so all it held, decoder libraries included,
// goes with it. It plays what VIDEO_STATE says: the video, and each screen's
// word ("play", "pause"; a screen not named has no window), a file the bar
// rewrites and this watches. It decides nothing itself.
ShellRoot {
    id: root

    FileView {
        id: stateFile

        path: Quickshell.env("VIDEO_STATE") ?? ""
        watchChanges: true
        printErrors: false
        onFileChanged: stateFile.reload()
    }

    readonly property var state: {
        try {
            return JSON.parse(stateFile.text());
        } catch (e) {
            return ({});
        }
    }

    Variants {
        model: Quickshell.screens

        VideoWallpaperScreen {
            required property ShellScreen modelData

            screen: modelData
            source: (root.state.source ?? "") !== "" ? `file://${root.state.source}` : ""
            mode: root.state.screens?.[modelData.name] ?? ""
        }
    }
}
