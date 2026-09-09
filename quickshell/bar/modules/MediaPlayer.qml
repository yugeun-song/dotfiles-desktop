pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.services

// The player: art and title on one line, the position on the next, the
// transport under both. Three rows down the card rather than two columns
// across it, which is what makes it read as a player and not a panel with a
// player in it.
//
// Every tone here is the bar's foreground at some opacity, never a literal
// white. The card is the bar opening, and a card lit in a white the bar does
// not use reads as a different program's window.
Item {
    id: root

    readonly property var player: Media.player
    readonly property bool hasMedia: Media.present
    readonly property bool playing: Media.playing
    // The position poll runs off this, so a closed card polls nothing.
    readonly property bool live: Media.open

    // Empty unless the URL passed Theme.localArt, and false until the image
    // has actually decoded: a host on the allowlist is not a promise that the
    // fetch succeeded.
    readonly property string artSource: Theme.localArt(root.player?.trackArtUrl ?? "")
    readonly property bool hasArt: root.artSource !== "" && cover.status === Image.Ready

    readonly property bool seekable: root.hasMedia
                                     && (root.player?.lengthSupported ?? false)
                                     && (root.player?.positionSupported ?? false)
                                     && (root.player?.length ?? 0) > 0

    // Mpris answers with a position when asked rather than announcing one, so
    // a progress bar has to ask. Once a second, and only while the card is
    // open.
    property real position: 0

    // Whether the fill glides to its next value or is simply put there. It
    // glides for the one-second steps of ordinary playback and jumps for
    // everything else -- a track change, a seek, and above all the card being
    // reopened, where the poll had been stopped and the stored position
    // was a minute stale. Without this the bar slid across from wherever it
    // had been left every time the island opened, which is the wrong thing
    // twice: it animates a value that did not change gradually, and it shows
    // a position that is not the track's.
    property bool glide: false

    // Whether the player will take a new position, and whether one is being
    // dragged right now. While scrubbing the bar follows the pointer rather
    // than the poll: the player answers a seek a beat late, and a bar that
    // waited for it lagged the finger doing the dragging.
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

    // One frame is enough for the jump to be applied without the Behavior;
    // the interval is a little longer so a slow frame cannot beat it.
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

    // What the card sizes itself to. Equal margins on all four sides follow
    // from this: the card is this plus its pad, and the pad is the same
    // number horizontally and vertically.
    implicitHeight: root.hasMedia ? content.implicitHeight : idle.implicitHeight

    Column {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.mediaGap
        visible: root.hasMedia

        // Row one: art, what is playing, and a mark at the far right that the
        // reference puts there too -- it is the only thing on this surface
        // that says which of several players is the one being shown.
        Row {
            width: parent.width
            spacing: Theme.px(13)

            // No placeholder. A player whose art is somewhere this shell will
            // not fetch from -- and there are plenty -- would otherwise leave
            // a grey square sitting there for the length of the track, which
            // says less than the space it takes. The row simply closes up.
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
                    // Title and artist come from the player, and for a browser
                    // that means from the page. Nothing here wanted markup.
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

            // The level meter, in the space the row has left. It was a player
            // icon here, which said which application was playing and nothing
            // else; the meter says the same thing -- only one player is ever
            // driving it -- and says it while moving.
            //
            // Hidden rather than left flat when cava has nothing to give: an
            // empty level list draws the same row of stubs a silent passage
            // does, and a still meter beside a playing track reads as broken.
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

        // Row two: where the track is. Hidden rather than drawn empty when the
        // player cannot say -- a bar stuck at zero claims it has not started.
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

                    // Matches the poll, so the fill moves at the rate the
                    // number beside it does instead of stepping once a second.
                    // Off while scrubbing, where it has to track the pointer.
                    Behavior on width {
                        enabled: root.glide && !root.scrubbing

                        NumberAnimation {
                            duration: 950
                            easing.type: Easing.Linear
                        }
                    }
                }

                // The grab handle, shown while the pointer is on the bar or
                // dragging it. A track with no handle does not look draggable,
                // and one with a permanent handle is a second thing to read.
                Rectangle {
                    x: Math.round(fill.width - width / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.px(9)
                    height: width
                    radius: width / 2
                    color: Theme.surfaceText
                    visible: root.canScrub && (scrub.containsMouse || root.scrubbing)
                }

                // Taller than the track it drives: a 5-pixel target is not one.
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
                        // Written straight to the player, which is what MPRIS
                        // exposes for an absolute move; seek() is relative and
                        // would need a position that is already stale.
                        if (root.player)
                            root.player.position = target;
                        // Put the local value there too and stop the glide, so
                        // the fill stays where it was dropped instead of
                        // sliding back and then forward when the poll catches
                        // up a second later.
                        root.glide = false;
                        root.position = target;
                        settle.restart();
                    }

                    onCanceled: root.scrubbing = false
                }
            }
        }

        // Row three: the transport. Graded the way the reference grades it --
        // play-pause largest, skip either side, shuffle and repeat at the ends
        // -- and spread across the whole width rather than huddled in the
        // middle, which is the other half of what makes it read as a player.
        // One cell per control, so the spacing is the width divided rather
        // than a number that has to be re-guessed when the width changes.
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

                    // Mpris publishes whether each of these is available, and a
                    // control that is drawn but does nothing is worse than one
                    // that is visibly unavailable.
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

                    // Shuffle and repeat are the two that hold a state rather
                    // than perform an action, so they are lit when on and dim
                    // when off, like every toggle on the bar.
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
                        // The whole cell, so there is no dead space between
                        // one control and the next.
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
                                // Three states, cycled in the order a listener
                                // wants them: off, the whole list, this track.
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

    // Nothing playing, said once and quietly rather than with a dead player.
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
