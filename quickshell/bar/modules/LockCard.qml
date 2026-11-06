pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.services
import "../services/artcolour.js" as ArtColour

// The playing track on the lock screen (lock.qml): the bar's player card at
// 1.6 times, laid out as the island's (the user, 2026-10-26), in the box
// hyprlock.conf's card picture takes, 864 x 259 of the design's units, here
// scaled to its height: cover, title and artist, the transport with
// play-pause on a disc, the position. hypr/scripts/lock-media.py draws the
// same card for hyprlock as a picture; keep the two in step. Live here, from
// MPRIS, so the transport answers at once. Nothing while nothing plays.
//
// Coloured per pixel from what lies under it (the user, 2026-11-06): the
// pane and its edge a LockSurface, the words and the transport one layer of
// ink (LockInk), the cover over both as it is. The cover's colour, for the
// notch's bars, is sampled here from the cover as drawn.
Item {
    id: root

    required property var under
    required property Item screenItem
    // The design's units: lock-media.py's, the bar's card times 1.6.
    readonly property real k: root.height / 259

    // The bar's rule (services/Media.qml): the playing player, else one with
    // a track loaded.
    readonly property var player: {
        const players = Mpris.players?.values ?? [];
        return players.find(p => p.isPlaying) ?? players.find(p => (p.trackTitle ?? "") !== "") ?? null;
    }
    readonly property bool present: root.player !== null && (root.player.trackTitle ?? "") !== ""
    readonly property bool playing: root.player?.isPlaying ?? false

    visible: root.player !== null && ((root.player.trackTitle ?? "") !== "" || root.player.isPlaying)

    // Drawn in the beige inside the ink's layer, whose shader keeps only how
    // much of each pixel is covered.
    readonly property color ink: Theme.beige
    readonly property color soft: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0xB8 / 255)

    function clock(seconds: real): string {
        const s = Math.max(0, Math.floor(seconds));
        const h = Math.floor(s / 3600);
        const m = Math.floor(s / 60) % 60;
        const ss = String(s % 60).padStart(2, "0");
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
    }

    // MPRIS announces no position: read every second while a track plays.
    property real position: 0
    readonly property real length: root.player?.length ?? 0

    Timer {
        running: root.visible && (root.player?.isPlaying ?? false)
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.position = root.player?.position ?? 0
    }

    LockSurface {
        anchors.fill: parent
        under: root.under
        screenItem: root.screenItem
        radius: 22 * 1.6 * root.k
        edgeWidth: Math.max(1, root.k)
    }

    // Where the cover goes: its place, the ink faint in it until it comes.
    Item {
        id: art

        x: 28.8 * root.k
        y: 28.8 * root.k
        width: 83.2 * root.k
        height: art.width
    }

    Item {
        id: inkLayer

        anchors.fill: parent
        // Sampled smoothly, as LockLabel's.
        layer.enabled: true
        layer.smooth: true
        layer.effect: LockInk {
            target: inkLayer
            under: root.under
            screenItem: root.screenItem
        }

        Rectangle {
            x: art.x
            y: art.y
            width: art.width
            height: art.height
            visible: cover.status !== Image.Ready
            radius: 17.6 * root.k
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 40 / 255)
        }

        Column {
            x: 132.8 * root.k
            width: root.width - 132.8 * root.k - 28.8 * root.k
            y: art.y + (art.height - height) / 2
            spacing: 3.2 * root.k

            Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: root.player?.trackTitle ?? ""
                color: root.ink
                font.family: Theme.uiFont
                font.weight: Font.DemiBold
                font.pixelSize: Math.max(1, 24 * root.k)
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: root.player?.trackArtist ?? ""
                color: root.soft
                font.family: Theme.uiFont
                font.weight: Font.Medium
                font.pixelSize: Math.max(1, 19.2 * root.k)
            }
        }

        // The transport, round the card's middle: shuffle and repeat quieter
        // than the skips; play-pause a disc in the ink with its mark cut out.
        Repeater {
            model: [
                { name: "shuffle", x: -163.2, glyph: Theme.iconShuffle, size: 33.6, quiet: true },
                { name: "prev", x: -83.2, glyph: Theme.iconPrev, size: 38.4, quiet: false },
                { name: "toggle", x: 0, glyph: "", size: 0, quiet: false },
                { name: "next", x: 83.2, glyph: Theme.iconNext, size: 38.4, quiet: false },
                { name: "loop", x: 163.2, glyph: Theme.iconRepeat, size: 33.6, quiet: true }
            ]

            Item {
                id: control

                required property var modelData

                width: 51.2 * root.k
                height: control.width
                x: root.width / 2 + control.modelData.x * root.k - control.width / 2
                y: 163.2 * root.k - control.height / 2

                Text {
                    anchors.centerIn: parent
                    visible: control.modelData.glyph !== ""
                    text: control.modelData.glyph
                    color: control.modelData.quiet ? root.soft : root.ink
                    font.family: Theme.iconFont
                    font.pixelSize: Math.max(1, control.modelData.size * root.k)
                }

                Shape {
                    id: disc

                    readonly property real side: 57.6 * root.k
                    readonly property real g: 20.8 * root.k
                    readonly property real mid: disc.side / 2
                    readonly property bool playing: root.player?.isPlaying ?? false

                    visible: control.modelData.name === "toggle"
                    anchors.centerIn: parent
                    width: disc.side
                    height: disc.side
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: root.ink
                        strokeColor: "transparent"
                        fillRule: ShapePath.OddEvenFill

                        PathAngleArc {
                            centerX: disc.mid
                            centerY: disc.mid
                            radiusX: disc.mid
                            radiusY: disc.mid
                            startAngle: 0
                            sweepAngle: 360
                        }

                        // Pause's two bars, or play's triangle a sixth of its
                        // width right of the middle, where its weight sits.
                        PathRectangle {
                            x: disc.playing ? disc.mid - 0.26 * disc.g * 1.5 : disc.mid
                            y: disc.playing ? disc.mid - 0.43 * disc.g : disc.mid
                            width: disc.playing ? 0.26 * disc.g : 0
                            height: disc.playing ? 0.86 * disc.g : 0
                            radius: 0.26 * disc.g / 4
                        }

                        PathRectangle {
                            x: disc.playing ? disc.mid + 0.26 * disc.g * 0.5 : disc.mid
                            y: disc.playing ? disc.mid - 0.43 * disc.g : disc.mid
                            width: disc.playing ? 0.26 * disc.g : 0
                            height: disc.playing ? 0.86 * disc.g : 0
                            radius: 0.26 * disc.g / 4
                        }

                        PathMove {
                            x: disc.playing ? disc.mid : disc.mid - 0.42 * disc.g + 0.14 * disc.g
                            y: disc.playing ? disc.mid : disc.mid - 0.5 * disc.g
                        }

                        PathLine {
                            x: disc.playing ? disc.mid : disc.mid + 0.42 * disc.g + 0.14 * disc.g
                            y: disc.mid
                        }

                        PathLine {
                            x: disc.playing ? disc.mid : disc.mid - 0.42 * disc.g + 0.14 * disc.g
                            y: disc.playing ? disc.mid : disc.mid + 0.5 * disc.g
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const p = root.player;
                        if (!p)
                            return;
                        switch (control.modelData.name) {
                        case "shuffle":
                            if (p.shuffleSupported)
                                p.shuffle = !p.shuffle;
                            break;
                        case "prev":
                            if (p.canGoPrevious)
                                p.previous();
                            break;
                        case "toggle":
                            if (p.canTogglePlaying)
                                p.togglePlaying();
                            break;
                        case "next":
                            if (p.canGoNext)
                                p.next();
                            break;
                        case "loop":
                            // Off, the playlist, the track, as the island's.
                            if (p.loopSupported)
                                p.loopState = p.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                                            : p.loopState === MprisLoopState.Playlist ? MprisLoopState.Track
                                            : MprisLoopState.None;
                            break;
                        }
                    }
                }
            }
        }

        // The position: each time in the whole time's width, the elapsed one to
        // its right, so the track keeps its length as the seconds turn.
        TextMetrics {
            id: reach

            font.family: Theme.iconFont
            font.pixelSize: Math.max(1, 17.6 * root.k)
            text: root.clock(root.length)
        }

        Item {
            id: positionRow

            readonly property real y0: 219.2 * root.k
            readonly property real x0: 28.8 * root.k + reach.advanceWidth + 16 * root.k
            readonly property real x1: root.width - 28.8 * root.k - reach.advanceWidth - 16 * root.k
            readonly property real share: root.length > 0 ? Math.max(0, Math.min(1, root.position / root.length)) : 0

            visible: root.length > 0
            anchors.fill: parent

            Text {
                x: 28.8 * root.k + reach.advanceWidth - implicitWidth
                y: positionRow.y0 - implicitHeight / 2
                text: root.clock(root.position)
                color: root.soft
                font: reach.font
            }

            Text {
                x: root.width - 28.8 * root.k - reach.advanceWidth
                y: positionRow.y0 - implicitHeight / 2
                text: root.clock(root.length)
                color: root.soft
                font: reach.font
            }

            Rectangle {
                x: positionRow.x0
                y: positionRow.y0 - height / 2
                width: Math.max(0, positionRow.x1 - positionRow.x0)
                height: 6.4 * root.k
                radius: height / 2
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.40)

                Rectangle {
                    width: Math.max(parent.height, parent.width * positionRow.share)
                    height: parent.height
                    radius: parent.radius
                    color: root.ink
                }
            }
        }
    }

    // ---- the cover, over the ink as it is ------------------------------------
    Image {
        id: cover

        x: art.x
        y: art.y
        width: art.width
        height: art.height
        visible: false
        source: Theme.localArt(root.player?.trackArtUrl ?? "")
        sourceSize: Qt.size(Math.round(art.width * 2), Math.round(art.height * 2))
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false

        onStatusChanged: {
            if (cover.status === Image.Ready)
                sampling.restart();
        }
    }

    Rectangle {
        id: coverMask

        x: art.x
        y: art.y
        width: art.width
        height: art.height
        visible: false
        radius: 17.6 * root.k
        layer.enabled: true
    }

    MultiEffect {
        id: coverShown

        x: art.x
        y: art.y
        width: art.width
        height: art.height
        visible: cover.status === Image.Ready
        source: cover
        maskEnabled: true
        maskSource: coverMask
    }

    // ---- the cover's colour, for the notch's bars ------------------------
    // From the cover as drawn, saved to the lock's own runtime directory
    // (lock.sh makes it and removes it), so nothing is fetched twice and
    // none of the bar's files is touched; two names in turn, so the
    // quantizer sees a new file each time.
    readonly property string runDir: (Quickshell.env("LOCK_RUN") || Quickshell.env("XDG_RUNTIME_DIR") || "") + "/quickshell-lock"
    property int turn: 0
    property string sample: ""

    ColorQuantizer {
        id: quantizer

        depth: 3
        rescaleSize: 64
    }

    Binding {
        target: quantizer
        property: "source"
        when: root.sample !== ""
        value: root.sample
        restoreMode: Binding.RestoreNone
    }

    readonly property var hues: [Theme.islandRed, Theme.islandYellow, Theme.islandGreen, Theme.islandMint, Theme.islandBlue]
        .map(c => ArtColour.lch(c)).sort((a, b) => a.h - b.h)
    readonly property color tone: root.sample !== "" && cover.status === Image.Ready
        ? ArtColour.vivid(quantizer.colors, root.hues, Theme.islandText) : Theme.islandText

    function takeSample(): void {
        if (cover.status !== Image.Ready || !coverShown.visible)
            return;
        coverShown.grabToImage(result => {
            root.turn = 1 - root.turn;
            const path = `${root.runDir}/cover-${root.turn}.png`;
            if (result.saveToFile(path))
                root.sample = `file://${path}`;
        });
    }

    // A moment after the cover is drawn, so the grab has its pixels.
    Timer {
        id: sampling

        interval: 120
        onTriggered: root.takeSample()
    }
}
