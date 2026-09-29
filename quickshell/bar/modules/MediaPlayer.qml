pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.services

// The player card: art and title, then the transport, then the position.
// The lower two follow the desktop Spotify player: a filled disc for play and
// pause between the skips, shuffle and repeat at the ends with a dot under
// them while on, and the elapsed and whole time either side of a thin bar
// that shows a knob when the pointer is over it. Tones come from the bar's
// foreground, never a literal white, so the card reads as the bar opening
// rather than another program's window. The only accent is the sky the card
// already used for a control that is on, now also on the bar under the
// pointer, where Spotify's turns green.
Item {
    id: root

    readonly property var player: Media.player
    readonly property bool hasMedia: Media.present
    readonly property bool playing: Media.playing

    // Theme.localArt filters the URL; hasArt also waits for a real decode.
    readonly property string artSource: Theme.localArt(root.player?.trackArtUrl ?? "")
    readonly property bool hasArt: root.artSource !== "" && cover.status === Image.Ready

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

    readonly property color faint: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.55)
    readonly property color unusable: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.20)

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

        // Row one: art, title and artist, level meter.
        Row {
            width: parent.width
            spacing: Theme.px(13)

            // No placeholder: when art is unavailable the row closes up.
            // ClippingRectangle, since clip on a Rectangle cuts square and the
            // cover came out with sharp corners on a rounded card.
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
                    color: root.faint
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

        // Row two: transport, a tight group in the middle of the card as in
        // Spotify's player, rather than one cell per fifth of its width.
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

                        // Shuffle and repeat hold state, so they are marked
                        // when on.
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
                            color: control.usable ? Theme.surfaceText : root.unusable
                            // Grows under the pointer and gives under the
                            // press, so the one filled control answers like a
                            // button.
                            scale: press.pressed ? 0.94 : control.hot ? 1.06 : 1

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        // Play and pause are drawn, not taken from the icon
                        // font: its glyphs fill little more than half their
                        // size, and the pause came out as two slivers in the
                        // disc. The ink is the bar's background, as if cut out
                        // of the disc.
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
                                        color: Theme.bg
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
                                    fillColor: Theme.bg
                                    strokeColor: Theme.bg
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
                            // and sky while switched on.
                            color: !control.usable ? root.unusable
                                   : control.engaged ? Theme.accentSky
                                   : control.hot ? Theme.surfaceText
                                   : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.62)
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
                            color: Theme.accentSky
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

                // The whole time, as in Spotify's player, not the time left: it
                // does not move, so the eye finds the elapsed one by what
                // changes.
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
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.16)

                    Rectangle {
                        id: fill

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(height, parent.width * root.progress)
                        height: parent.height
                        radius: height / 2
                        // Sky under the pointer: the bar is live, a click
                        // seeks.
                        color: track.hot ? Theme.accentSky : Theme.surfaceText

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
                        color: Theme.surfaceText
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
