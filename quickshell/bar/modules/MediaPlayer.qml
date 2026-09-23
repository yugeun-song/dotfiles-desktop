pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.services

// The player card: art and title, then position, then transport.
// Tones come from the bar's foreground, never a literal white, so the card
// reads as the bar opening rather than another program's window.
Item {
    id: root

    readonly property var player: Media.player
    readonly property bool hasMedia: Media.present
    readonly property bool playing: Media.playing
    // Gates the position poll.
    readonly property bool live: Media.open

    // Theme.localArt filters the URL; hasArt also waits for a real decode.
    readonly property string artSource: Theme.localArt(root.player?.trackArtUrl ?? "")
    readonly property bool hasArt: root.artSource !== "" && cover.status === Image.Ready

    readonly property bool seekable: root.hasMedia
                                     && (root.player?.lengthSupported ?? false)
                                     && (root.player?.positionSupported ?? false)
                                     && (root.player?.length ?? 0) > 0

    // MPRIS does not announce position changes; polled 1 s while open.
    property real position: 0

    // Glide only for ordinary 1 s playback steps; jump on track change, seek
    // or reopening the card (the stored position is stale by then).
    property bool glide: false

    // While scrubbing, follow the pointer, not the poll: players answer a
    // seek late.
    readonly property bool canScrub: root.seekable && (root.player?.canSeek ?? false)
    property bool scrubbing: false
    property real scrubPosition: 0

    readonly property real shownPosition: root.scrubbing ? root.scrubPosition : root.position

    Timer {
        id: poll

        running: root.live && root.seekable
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const next = root.player?.position ?? 0;
            // More than a couple of seconds is not playback.
            if (Math.abs(next - root.position) > 2) {
                root.glide = false;
                settle.restart();
            }
            root.position = next;
        }
    }

    // Re-enables glide after a jump; longer than a frame so a slow frame
    // cannot animate the jump.
    Timer {
        id: settle

        interval: 80
        onTriggered: root.glide = true
    }

    onLiveChanged: {
        if (!root.live)
            root.glide = false;
    }

    function clock(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        const m = Math.floor(s / 60);
        const r = s % 60;
        return `${m}:${r < 10 ? "0" : ""}${r}`;
    }

    implicitHeight: root.hasMedia ? content.implicitHeight : idle.implicitHeight

    Column {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.mediaGap
        visible: root.hasMedia

        // Row one: art, title and artist, level meter.
        Row {
            width: parent.width
            spacing: Theme.px(13)

            // No placeholder: when art is unavailable the row closes up.
            Rectangle {
                id: art

                anchors.verticalCenter: parent.verticalCenter
                visible: root.hasArt
                width: root.hasArt ? Theme.mediaArtSize : 0
                height: Theme.mediaArtSize
                radius: Theme.px(11)
                color: "transparent"
                clip: true

                Image {
                    id: cover

                    anchors.fill: parent
                    source: root.artSource
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - (root.hasArt ? art.width + Theme.px(13) : 0)
                       - mark.width - Theme.px(13)
                spacing: Theme.px(2)

                Text {
                    width: parent.width
                    text: root.player?.trackTitle ?? ""
                    // Player metadata (for a browser, the page's); never markup.
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.mediaTitleSize
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }

                Text {
                    width: parent.width
                    text: root.player?.trackArtist ?? ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.mediaSubSize
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.55)
                }
            }

            // Meter while cava has levels; otherwise a dim note glyph, since a
            // flat meter beside a playing track reads as broken.
            Item {
                id: mark

                anchors.verticalCenter: parent.verticalCenter
                width: meter.implicitWidth
                height: Theme.mediaArtSize

                Visualizer {
                    id: meter

                    anchors.centerIn: parent
                    visible: root.playing && Cava.levels.length > 0
                    showWell: false
                    wellHeight: Theme.mediaArtSize
                    barColor: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.85)
                }

                Text {
                    anchors.centerIn: parent
                    visible: !meter.visible
                    text: Theme.iconMusic
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.px(18)
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.25)
                }
            }
        }

        // Row two: position. Hidden when unknown; a bar stuck at zero lies.
        Item {
            width: parent.width
            height: Theme.mediaProgressHeight
            visible: root.seekable

            Text {
                id: elapsed

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.clock(root.shownPosition)
                font.family: Theme.monoFont
                font.pixelSize: Theme.mediaTimeSize
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.55)
            }

            Text {
                id: remaining

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "-" + root.clock((root.player?.length ?? 0) - root.shownPosition)
                font.family: Theme.monoFont
                font.pixelSize: Theme.mediaTimeSize
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.55)
            }

            Rectangle {
                id: track

                anchors.left: elapsed.right
                anchors.right: remaining.left
                anchors.leftMargin: Theme.px(13)
                anchors.rightMargin: Theme.px(13)
                anchors.verticalCenter: parent.verticalCenter
                height: Math.max(3, Theme.px(5))
                radius: height / 2
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.15)

                Rectangle {
                    id: fill

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(height, parent.width * Math.min(1, root.shownPosition / Math.max(1, root.player?.length ?? 1)))
                    height: parent.height
                    radius: height / 2
                    color: Theme.surfaceText

                    // ~Poll interval, so the fill moves continuously.
                    Behavior on width {
                        enabled: root.glide && !root.scrubbing

                        NumberAnimation {
                            duration: 950
                            easing.type: Easing.Linear
                        }
                    }
                }

                // Handle only on hover or drag.
                Rectangle {
                    x: Math.round(fill.width - width / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.px(9)
                    height: width
                    radius: width / 2
                    color: Theme.surfaceText
                    visible: root.canScrub && (scrub.containsMouse || root.scrubbing)
                }

                // Taller than the 5 px track it drives.
                MouseArea {
                    id: scrub

                    anchors.fill: parent
                    anchors.topMargin: -Theme.px(8)
                    anchors.bottomMargin: -Theme.px(8)
                    enabled: root.canScrub
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: root.canScrub ? Qt.PointingHandCursor : Qt.ArrowCursor

                    function at(x) {
                        const length = root.player?.length ?? 0;
                        if (length <= 0 || track.width <= 0)
                            return 0;
                        return Math.max(0, Math.min(1, x / track.width)) * length;
                    }

                    onPressed: mouse => {
                        root.scrubbing = true;
                        root.scrubPosition = scrub.at(mouse.x);
                    }

                    onPositionChanged: mouse => {
                        if (root.scrubbing)
                            root.scrubPosition = scrub.at(mouse.x);
                    }

                    onReleased: {
                        if (!root.scrubbing)
                            return;
                        const target = root.scrubPosition;
                        root.scrubbing = false;
                        // Absolute set; seek() is relative to a stale position.
                        if (root.player)
                            root.player.position = target;
                        // Keep the fill where it was dropped until the poll
                        // catches up.
                        root.glide = false;
                        root.position = target;
                        settle.restart();
                    }

                    onCanceled: root.scrubbing = false
                }
            }
        }

        // Row three: transport, one equal cell per control across the width.
        Row {
            width: parent.width
            topPadding: Theme.px(9)

            Repeater {
                model: [
                    { key: "shuffle", size: Theme.mediaControlEdge },
                    { key: "prev", size: Theme.mediaControlSkip },
                    { key: "toggle", size: Theme.mediaControlMain },
                    { key: "next", size: Theme.mediaControlSkip },
                    { key: "loop", size: Theme.mediaControlEdge }
                ]

                Item {
                    id: control

                    required property var modelData

                    width: parent.width / 5
                    height: Theme.mediaControlMain

                    // Unsupported controls are drawn visibly disabled.
                    readonly property bool usable: {
                        switch (control.modelData.key) {
                        case "prev":
                            return root.player?.canGoPrevious ?? false;
                        case "next":
                            return root.player?.canGoNext ?? false;
                        case "shuffle":
                            return root.player?.shuffleSupported ?? false;
                        case "loop":
                            return root.player?.loopSupported ?? false;
                        default:
                            return root.player?.canTogglePlaying ?? false;
                        }
                    }

                    // Shuffle and repeat hold state, so they are lit when on.
                    readonly property bool engaged: {
                        switch (control.modelData.key) {
                        case "shuffle":
                            return root.player?.shuffle ?? false;
                        case "loop":
                            return (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None;
                        default:
                            return false;
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: {
                            switch (control.modelData.key) {
                            case "shuffle":
                                return Theme.iconShuffle;
                            case "prev":
                                return Theme.iconPrev;
                            case "next":
                                return Theme.iconNext;
                            case "loop":
                                return (root.player?.loopState ?? MprisLoopState.None) === MprisLoopState.Track
                                       ? Theme.iconRepeatOne : Theme.iconRepeat;
                            default:
                                return root.playing ? Theme.iconPause : Theme.iconPlay;
                            }
                        }
                        font.family: Theme.iconFont
                        font.pixelSize: control.modelData.size
                        color: !control.usable ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.20)
                                               : control.engaged ? Theme.accentSky
                                               : controlHover.hovered ? Theme.surfaceText : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.82)

                        Behavior on color {
                            ColorAnimation {
                                duration: 90
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    HoverHandler {
                        id: controlHover

                        enabled: control.usable
                    }

                    MouseArea {
                        // Whole cell: no dead space between controls.
                        anchors.fill: parent
                        enabled: control.usable
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            switch (control.modelData.key) {
                            case "prev":
                                root.player.previous();
                                break;
                            case "next":
                                root.player.next();
                                break;
                            case "shuffle":
                                root.player.shuffle = !root.player.shuffle;
                                break;
                            case "loop":
                                // Off -> playlist -> track.
                                root.player.loopState = root.player.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                                                      : root.player.loopState === MprisLoopState.Playlist ? MprisLoopState.Track
                                                      : MprisLoopState.None;
                                break;
                            default:
                                root.player.togglePlaying();
                                break;
                            }
                        }
                    }
                }
            }
        }
    }

    Column {
        id: idle

        anchors.centerIn: parent
        visible: !root.hasMedia
        spacing: Theme.px(7)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Theme.iconMusic
            font.family: Theme.iconFont
            font.pixelSize: Theme.px(27)
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.22)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Nothing playing"
            font.family: Theme.uiFont
            font.pixelSize: Theme.mediaSubSize
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.35)
        }
    }
}
