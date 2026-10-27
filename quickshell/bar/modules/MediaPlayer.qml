pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.services

// The player card the island grows into (MediaPopup.qml): art and title, the
// transport, the position. The lower two follow the desktop Spotify player: a
// filled disc between the skips, shuffle and repeat at the ends with a dot
// while on, the elapsed and whole time either side of a thin bar. In the
// island's colours (the user's references, 2026-10-26): white and grey, their
// blue for a control that is on and the bar under the pointer, the meter in
// the cover's colour and, paused, at rest in its companion.
Item {
    id: root

    readonly property var player: Media.player
    // Held through a seek or a change of track, as the island is (Media);
    // play and pause show the player's state as it is, at once.
    readonly property bool hasMedia: Media.steadyPresent
    readonly property bool playing: Media.playing

    // Theme.localArt filters the URL; hasArt also waits for a real decode.
    readonly property string artSource: Theme.localArt(Media.shownArtUrl)
    // The cover before stands in until the next has loaded, so the row
    // keeps its cover across a change of track instead of closing up.
    readonly property bool hasArt: root.artSource !== ""
                                   && (cover.status === Image.Ready || coverBefore.status === Image.Ready)

    readonly property real length: root.player?.length ?? 0
    readonly property bool seekable: root.hasMedia
                                     && (root.player?.lengthSupported ?? false)
                                     && (root.player?.positionSupported ?? false)
                                     && root.length > 0

    // MPRIS does not announce position changes; polled 1 s. The card, and
    // this with it, exists only while it is open.
    property real position: 0

    // Glide only for ordinary 1 s playback steps; jump on track change, seek
    // or opening the card (the first reading is a jump from zero).
    property bool glide: false

    // While scrubbing, follow the pointer, not the poll: players answer a
    // seek late.
    readonly property bool canScrub: root.seekable && (root.player?.canSeek ?? false)
    property bool scrubbing: false
    property real scrubPosition: 0

    readonly property real shownPosition: root.scrubbing ? root.scrubPosition : root.position
    readonly property real progress: root.length > 0 ? Math.max(0, Math.min(1, root.shownPosition / root.length)) : 0

    readonly property color faint: Theme.islandSubtext
    readonly property color unusable: Theme.islandFillHigh

    Timer {
        id: poll

        running: root.seekable
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
        visible: root.hasMedia

        // Row one: art, title and artist, the waveform over the rest.
        Row {
            id: top

            // What the names and the waveform share.
            readonly property int free: top.width - (root.hasArt ? art.width + top.spacing : 0) - top.spacing

            width: parent.width
            spacing: Theme.px(13)

            // No placeholder: without art the row closes up. Clipped by a
            // ClippingRectangle: clip on a Rectangle cuts square corners.
            ClippingRectangle {
                id: art

                anchors.verticalCenter: parent.verticalCenter
                visible: root.hasArt
                width: root.hasArt ? Theme.mediaArtSize : 0
                height: Theme.mediaArtSize
                radius: Theme.px(11)
                color: "transparent"

                Image {
                    id: cover

                    anchors.fill: parent
                    source: root.artSource
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true

                    onStatusChanged: {
                        if (cover.status === Image.Ready)
                            coverBefore.source = cover.source;
                    }
                }

                Image {
                    id: coverBefore

                    anchors.fill: parent
                    visible: cover.status !== Image.Ready
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                }
            }

            // As wide as the longer name, short of the waveform's least width.
            Column {
                id: names

                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(Math.ceil(Math.max(title.implicitWidth, artist.implicitWidth)),
                                            top.free - Theme.mediaWaveMin))
                spacing: Theme.px(2)

                Text {
                    id: title

                    width: parent.width
                    text: Media.shownTitle
                    // Player metadata (for a browser, the page's); never markup.
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.mediaTitleSize
                    font.weight: Font.DemiBold
                    color: Theme.islandText
                }

                Text {
                    id: artist

                    width: parent.width
                    text: Media.shownArtist
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.mediaSubSize
                    color: root.faint
                }
            }

            // The meter while cava has levels, at rest while paused; else a dim
            // note, since a flat meter beside a playing track reads as broken.
            Item {
                id: mark

                anchors.verticalCenter: parent.verticalCenter
                width: top.free - names.width
                height: Theme.mediaArtSize

                // As many of cava's bands as fit at the meter's own pitch, as
                // tall as the cover at most.
                Visualizer {
                    id: meter

                    anchors.centerIn: parent
                    visible: Media.steadyPlaying ? Cava.levels.length > 0 : !Cava.givenUp
                    bars: Math.max(1, Math.min(Cava.barCount,
                        Math.floor((mark.width + Theme.vizBarSpacing) / (Theme.vizBarWidth + Theme.vizBarSpacing))))
                    levelHeight: Theme.mediaArtSize
                    // The cover's colour, paused its companion.
                    live: Media.steadyPlaying
                    barColor: Media.steadyPlaying ? Media.artColor : Media.artDim
                }

                Text {
                    anchors.centerIn: parent
                    visible: !meter.visible
                    text: Theme.iconMusic
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.px(18)
                    color: Theme.islandFillHigh
                }
            }
        }

        // Row two: the transport, a tight group in the middle as in Spotify's.
        Item {
            width: parent.width
            height: Theme.px(14) + Theme.mediaDiscSize

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                spacing: Theme.mediaControlGap

                Repeater {
                    model: ["shuffle", "prev", "toggle", "next", "loop"]

                    Item {
                        id: control

                        required property string modelData

                        readonly property bool disc: control.modelData === "toggle"

                        width: control.disc ? Theme.mediaDiscSize : Theme.mediaControlCell
                        height: Theme.mediaDiscSize

                        // Unsupported controls are drawn visibly disabled.
                        readonly property bool usable: {
                            switch (control.modelData) {
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

                        // Shuffle and repeat hold state: marked when on.
                        readonly property bool engaged: {
                            switch (control.modelData) {
                            case "shuffle":
                                return root.player?.shuffle ?? false;
                            case "loop":
                                return (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None;
                            default:
                                return false;
                            }
                        }

                        readonly property bool hot: controlHover.hovered && control.usable

                        Rectangle {
                            id: disc

                            anchors.centerIn: parent
                            visible: control.disc
                            width: Theme.mediaDiscSize
                            height: width
                            radius: width / 2
                            color: control.usable ? Theme.islandText : root.unusable
                            // Grows under the pointer and gives under a press:
                            // the one filled control answers like a button.
                            scale: press.pressed ? 0.94 : control.hot ? 1.06 : 1

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        // Drawn, not glyphs: the icon font's fill little more
                        // than half their box (the pause came out as two
                        // slivers). In the island's black, as if cut out.
                        Item {
                            anchors.centerIn: parent
                            visible: control.disc
                            width: Theme.mediaDiscGlyph
                            height: Theme.mediaDiscGlyph
                            scale: disc.scale

                            Row {
                                anchors.centerIn: parent
                                visible: root.playing
                                spacing: Math.round(Theme.mediaDiscGlyph * 0.26)

                                Repeater {
                                    model: 2

                                    Rectangle {
                                        width: Math.round(Theme.mediaDiscGlyph * 0.26)
                                        height: Math.round(Theme.mediaDiscGlyph * 0.86)
                                        radius: Math.max(1, width / 4)
                                        antialiasing: true
                                        color: Theme.islandColor
                                    }
                                }
                            }

                            // Nudged right: a triangle's weight sits a sixth of
                            // its width left of the middle of its box.
                            Shape {
                                id: playMark

                                readonly property real inset: Math.max(1, Theme.mediaDiscGlyph * 0.07)

                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: playMark.width / 6
                                visible: !root.playing
                                width: Math.round(Theme.mediaDiscGlyph * 0.84)
                                height: Theme.mediaDiscGlyph
                                preferredRendererType: Shape.CurveRenderer

                                ShapePath {
                                    fillColor: Theme.islandColor
                                    strokeColor: Theme.islandColor
                                    // Rounds the corners, as Spotify's are.
                                    strokeWidth: playMark.inset * 2
                                    joinStyle: ShapePath.RoundJoin
                                    startX: playMark.inset
                                    startY: playMark.inset

                                    PathLine {
                                        x: playMark.width - playMark.inset
                                        y: playMark.height / 2
                                    }
                                    PathLine {
                                        x: playMark.inset
                                        y: playMark.height - playMark.inset
                                    }
                                    PathLine {
                                        x: playMark.inset
                                        y: playMark.inset
                                    }
                                }
                            }
                        }

                        Text {
                            id: glyph

                            anchors.centerIn: parent
                            visible: !control.disc
                            text: {
                                switch (control.modelData) {
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
                                    return "";
                                }
                            }
                            font.family: Theme.iconFont
                            font.pixelSize: control.modelData === "prev" || control.modelData === "next"
                                            ? Theme.mediaControlSkip : Theme.mediaControlEdge
                            // Grey until pointed at, as in Spotify's player,
                            // and blue while switched on.
                            color: !control.usable ? root.unusable
                                   : control.engaged ? Theme.islandBlue
                                   : control.hot ? Theme.islandText
                                   : Theme.islandSubtext
                            scale: press.pressed ? 0.9 : 1

                            Behavior on color {
                                ColorAnimation {
                                    duration: 90
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 90
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        // The on mark, so a switched-on control does not rest
                        // on colour alone.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: Theme.px(14)
                            visible: control.engaged && control.usable
                            width: Math.max(3, Theme.px(4))
                            height: width
                            radius: width / 2
                            color: Theme.islandBlue
                        }

                        HoverHandler {
                            id: controlHover

                            enabled: control.usable
                        }

                        MouseArea {
                            id: press

                            // Whole cell: no dead space between controls.
                            anchors.fill: parent
                            enabled: control.usable
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                switch (control.modelData) {
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

        // Row three: position. Hidden when unknown; a bar stuck at zero lies.
        Item {
            width: parent.width
            height: Theme.px(10) + Theme.mediaProgressHeight
            visible: root.seekable

            // Both times in the width of the whole time, the longer of the two,
            // so the bar does not change length as the seconds tick.
            TextMetrics {
                id: timeMetrics

                font.family: Theme.monoFont
                font.pixelSize: Theme.mediaTimeSize
                text: root.clock(root.length)
            }

            Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Theme.mediaProgressHeight

                Text {
                    id: elapsed

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.ceil(timeMetrics.width)
                    horizontalAlignment: Text.AlignRight
                    // Held at the whole time: quickshell extrapolates the
                    // position between reads and can overshoot the end.
                    text: root.clock(Math.min(root.shownPosition, root.length))
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.mediaTimeSize
                    color: root.faint
                }

                // The whole time, as in Spotify's, not the time left: it stands
                // still, so the eye finds the elapsed one by what moves.
                Text {
                    id: whole

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.ceil(timeMetrics.width)
                    horizontalAlignment: Text.AlignLeft
                    text: root.clock(root.length)
                    font.family: Theme.monoFont
                    font.pixelSize: Theme.mediaTimeSize
                    color: root.faint
                }

                Rectangle {
                    id: track

                    readonly property bool hot: root.canScrub && (scrub.containsMouse || root.scrubbing)

                    anchors.left: elapsed.right
                    anchors.right: whole.left
                    anchors.leftMargin: Theme.px(10)
                    anchors.rightMargin: Theme.px(10)
                    anchors.verticalCenter: parent.verticalCenter
                    height: Theme.mediaTrackHeight
                    radius: height / 2
                    // White's quieter companion, as each colour's track is.
                    color: Theme.islandDim(Theme.islandText)

                    Rectangle {
                        id: fill

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(height, parent.width * root.progress)
                        height: parent.height
                        radius: height / 2
                        // Blue under the pointer: the bar is live, a click
                        // seeks.
                        color: track.hot ? Theme.islandBlue : Theme.islandText

                        // ~Poll interval, so the fill moves continuously.
                        Behavior on width {
                            enabled: root.glide && !root.scrubbing

                            NumberAnimation {
                                duration: 950
                                easing.type: Easing.Linear
                            }
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: 90
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Rectangle {
                        x: Math.round(fill.width - width / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.mediaKnobSize
                        height: width
                        radius: width / 2
                        color: Theme.islandText
                        visible: track.hot
                    }

                    // Taller than the track it drives.
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
                            if (root.length <= 0 || track.width <= 0)
                                return 0;
                            return Math.max(0, Math.min(1, x / track.width)) * root.length;
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
            color: Theme.islandFillHigh
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Nothing playing"
            font.family: Theme.uiFont
            font.pixelSize: Theme.mediaSubSize
            color: Theme.islandSubtext
        }
    }
}
