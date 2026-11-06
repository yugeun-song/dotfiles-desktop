pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland

// One screen of the video wallpaper's player (videowall.qml): a window on
// the background level over hyprpaper's picture, the video's first frame,
// so the video takes over and gives back without a jump (rules.lua orders
// it over hyprpaper whichever came first). Muted, looping, decoded by the
// GPU where the driver can (VA-API through Qt's FFmpeg backend), filling
// the screen as hyprpaper does (PreserveAspectCrop). Clicks pass through.
//
// `mode` is the bar's word for this screen (VideoWallpaperSeat): "play",
// "pause" (the window and its frame kept, no decoding), or "" (the window
// and the decoder gone). Played again after a pause it goes on from where it
// stopped; after "" from its start.
Scope {
    id: root

    required property ShellScreen screen
    property string source: ""
    property string mode: ""

    LazyLoader {
        active: root.mode !== "" && root.source !== ""

        PanelWindow {
            id: win

            screen: root.screen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: false
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell:video-wallpaper"
            mask: Region {}

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            MediaPlayer {
                id: player

                source: root.source
                loops: MediaPlayer.Infinite
                videoOutput: output

                // A new source stops a playing player.
                onSourceChanged: win.follow()
                onErrorOccurred: (error, message) => console.warn("[videowall]", root.screen?.name ?? "", message)
            }

            function follow(): void {
                if (root.mode === "play")
                    player.play();
                else
                    player.pause();
            }

            Connections {
                target: root

                function onModeChanged() {
                    win.follow();
                }
            }

            Component.onCompleted: win.follow()

            VideoOutput {
                id: output

                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectCrop
            }
        }
    }
}
