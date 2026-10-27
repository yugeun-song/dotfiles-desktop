pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs.services

// The island in the bar's middle, after the user's models (NotchNook, then
// a menu-bar pill): a black pill set in the bar, in the colours of the
// user's mockups (Theme.island*). It comes out of a point on a spring and
// goes back into it, sinking and then drawn in (the user, 2026-10-26: a
// black hole). With what plays on it, it is as wide as that needs, between a
// least and a most that are shares of the bar's idle width
// (Theme.islandLeastShare, islandIdleShare), the same for every track;
// everything else keeps the widths it had (Theme.mediaChipWidth at most,
// islandMinWidth alone). Less only where the centred island would meet a
// group. A hover grows it into the player, on this screen only
// (MediaPopup.qml).
//
// Its parts (IslandPart.qml), side by side as a phone sets activities:
//   what plays: cover, title and artist, the meter at the right in the
//     cover's colour; paused, it stays until the player closes, the meter at
//     rest in that colour's companion (the user, 2026-10-26);
//   a call (Calls.qml) and OBS (Obs.qml), asked for with Zoom and Discord;
//   a screen share (ScreenShare.qml);
//   a system event (Island.qml), alone while it lasts.
// Super+M (Media.islandOn) hides it all, events included (the user,
// 2026-10-26: all or nothing).
Item {
    id: root

    // ---- what shows --------------------------------------------------------

    // By the values Media holds through a seek or a change of track, which
    // pass through Paused or a blank title.
    readonly property bool musicShown: Media.islandOn && Media.steadyPresent
    readonly property bool shareShown: Media.islandOn && ScreenShare.active
    readonly property bool callShown: Media.islandOn && Calls.active
    readonly property bool obsShown: Media.islandOn && Obs.active

    // This bar's screen (Bar.qml): events show on the screen in use only.
    property string screenName: ""
    // Never while grown under the pointer: a hover holds the island still
    // (the user, 2026-10-26).
    readonly property bool eventShown: Media.islandOn && Island.kind !== "" && Island.screen === root.screenName
        && !card.shown && !card.holding
    readonly property bool eventWanted: root.eventShown && root.rowRoom >= Theme.islandArtSize

    // Each part only where it fits: an event alone; then the share, OBS and
    // a call, what goes out before what is heard; what plays in what is left.
    readonly property bool shareWanted: root.shareShown && !root.eventWanted && root.rowRoom >= sharePart.floor
    readonly property int afterShare: root.rowRoom - (root.shareWanted ? sharePart.compact + Theme.shareGap : 0)
    readonly property bool obsWanted: root.obsShown && !root.eventWanted && root.afterShare >= obsPart.floor
    readonly property int afterObs: root.afterShare - (root.obsWanted ? obsPart.compact + Theme.shareGap : 0)
    readonly property bool callWanted: root.callShown && !root.eventWanted && root.afterObs >= callPart.floor
    readonly property int afterCall: root.afterObs - (root.callWanted ? callPart.floor + Theme.shareGap : 0)
    readonly property bool musicWanted: root.musicShown && !root.eventWanted && root.afterCall >= Theme.islandArtSize
    readonly property int wantedCount: Number(root.musicWanted) + Number(root.callWanted) + Number(root.obsWanted)
                                       + Number(root.shareWanted) + Number(root.eventWanted)
    readonly property bool wanted: root.wantedCount > 0
    // One thing on it: laid out to the one width, an activity naming itself.
    readonly property bool single: root.wantedCount === 1

    // Up until the island has shut, so it is seen going.
    property bool up: false

    // 0 a point, Theme.islandDotAt a dot the pill's height, 1 the pill; past
    // 1 for a moment as it opens.
    property real openness: 0
    readonly property real roundness: Math.max(0, Math.min(1, root.openness / Theme.islandDotAt))
    readonly property real stretch: Math.max(0, (root.openness - Theme.islandDotAt) / (1 - Theme.islandDotAt))
    // Where the sink before the plunge goes, from where the island was.
    property real sinkTo: Theme.islandSink

    readonly property var parts: [musicPart, callPart, obsPart, sharePart, eventPart]

    function follow(): void {
        if (root.wanted) {
            if (!root.up) {
                // Opened from nothing, the island's own opening carries them.
                for (const part of root.parts)
                    part.snap();
                root.up = true;
            } else {
                const swap = root.parts.some(p => p.closing);
                for (const part of root.parts) {
                    part.ease(swap);
                    part.move();
                }
            }
            if (shutting.running || (!opening.running && root.openness !== 1)) {
                shutting.stop();
                opening.restart();
            }
        } else if (root.up && !shutting.running) {
            // The parts stay as they are while the whole island shuts.
            opening.stop();
            root.sinkTo = Math.min(1, root.openness) * Theme.islandSink;
            shutting.restart();
        }
    }

    // From wherever the shut left it, so coming back halfway does not jump.
    NumberAnimation {
        id: opening

        target: root
        property: "openness"
        to: 1
        duration: Theme.islandOpenMs
        easing.type: Easing.OutBack
        easing.overshoot: Theme.islandOvershoot
    }

    // Sunk a little at once, then drawn into the point: the sink ends at
    // rest and the plunge starts from rest, which leaves a beat between.
    SequentialAnimation {
        id: shutting

        NumberAnimation {
            target: root
            property: "openness"
            to: root.sinkTo
            duration: Theme.islandSinkMs
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "openness"
            to: 0
            duration: Theme.islandPlungeMs
            easing.type: Easing.InQuart
        }
        ScriptAction {
            script: root.up = false
        }
    }

    // After every binding has settled: read in a source's change handler,
    // `wanted` was stale (measured), and a part shut early drew the pill
    // into a dot ahead of the island's own motion.
    onWantedChanged: Qt.callLater(root.follow)
    onMusicWantedChanged: Qt.callLater(root.follow)
    onCallWantedChanged: Qt.callLater(root.follow)
    onObsWantedChanged: Qt.callLater(root.follow)
    onShareWantedChanged: Qt.callLater(root.follow)
    onEventWantedChanged: Qt.callLater(root.follow)
    Component.onCompleted: root.follow()

    // ---- what each part shows, held while it goes -------------------------

    // The event as it was last shown here, held while its part goes after
    // the event has ended (RestoreNone keeps the last value).
    property string eventGlyph: ""
    property string eventText: ""
    property string eventValue: ""
    property real eventLevel: -1
    property real eventBattery: -1
    property color eventTone: Theme.islandText

    Binding on eventGlyph {
        when: root.eventShown
        value: Island.glyph
        restoreMode: Binding.RestoreNone
    }
    Binding on eventText {
        when: root.eventShown
        value: Island.text
        restoreMode: Binding.RestoreNone
    }
    Binding on eventValue {
        when: root.eventShown
        value: Island.value
        restoreMode: Binding.RestoreNone
    }
    Binding on eventLevel {
        when: root.eventShown
        value: Island.level
        restoreMode: Binding.RestoreNone
    }
    Binding on eventBattery {
        when: root.eventShown
        value: Island.battery
        restoreMode: Binding.RestoreNone
    }
    Binding on eventTone {
        when: root.eventShown
        value: Island.tone
        restoreMode: Binding.RestoreNone
    }

    // The share, held from its last second while the part goes.
    property var shareApps: []
    property string shareKind: ""
    property string shareClock: "0:00"

    function readShare(): void {
        if (!ScreenShare.active)
            return;
        root.shareApps = ScreenShare.apps.filter(a => a.icon !== "").slice(0, 2);
        root.shareKind = ScreenShare.kind;
        root.shareClock = Theme.clockText(ScreenShare.now - ScreenShare.since);
    }

    // On `lasting`, which ScreenShare sets after what goes with it.
    Connections {
        target: ScreenShare

        function onLastingChanged(): void {
            root.readShare();
        }
        function onNowChanged(): void {
            root.readShare();
        }
        function onAppsChanged(): void {
            root.readShare();
        }
    }

    // The call, held the same way: its first program's icon and name, and
    // how long the longest has gone on.
    property string callIcon: ""
    property string callName: ""
    property string callClock: "0:00"

    Binding on callIcon {
        when: Calls.active
        value: Calls.apps[0]?.icon ?? ""
        restoreMode: Binding.RestoreNone
    }
    Binding on callName {
        when: Calls.active
        value: Calls.apps[0]?.name ?? ""
        restoreMode: Binding.RestoreNone
    }
    Binding on callClock {
        when: Calls.active
        value: Theme.clockText(Calls.now - Calls.since)
        restoreMode: Binding.RestoreNone
    }

    // OBS, held the same way: recording (and paused), or only live.
    property bool obsRecording: false
    property bool obsPaused: false
    property bool obsStreaming: false
    property string obsClock: "0:00"

    Binding on obsRecording {
        when: Obs.active
        value: Obs.recording
        restoreMode: Binding.RestoreNone
    }
    Binding on obsPaused {
        when: Obs.active
        value: Obs.paused
        restoreMode: Binding.RestoreNone
    }
    Binding on obsStreaming {
        when: Obs.active
        value: Obs.streaming
        restoreMode: Binding.RestoreNone
    }
    Binding on obsClock {
        when: Obs.active
        value: Theme.clockText(Obs.recording ? Obs.recordElapsed : Obs.streamElapsed)
        restoreMode: Binding.RestoreNone
    }

    // ---- widths ------------------------------------------------------------

    readonly property int itemGap: Theme.islandItemGap

    // Set by Bar.qml. room: the outer width the island, centred on the
    // screen, has before it meets a group. idle: what the groups leave of the
    // bar, the app's name and the clock taken at their widest, so it holds
    // still as focus moves and the minutes turn. Shares of it, not lengths:
    // on the 1920 panel the status group takes far more of the bar than on
    // the desk.
    property int room: 0
    property real idle: 0

    // The music island's most and least, never under the floor: within them
    // what plays is as wide as it needs, not stretched past it (the user,
    // 2026-10-26). The room wins over both, off the groups.
    readonly property int musicWidest: Math.min(root.room, Math.max(Theme.islandFloorWidth,
                                                                   Math.round(Theme.islandIdleShare * root.idle)))
    readonly property int musicLeast: Math.min(root.musicWidest, Math.max(Theme.islandFloorWidth,
                                                                          Math.round(Theme.islandLeastShare * root.idle)))
    // Everything else keeps the widths it had (the user, 2026-10-26).
    readonly property int otherWidest: Math.min(root.room, Theme.mediaChipWidth + Theme.islandPadX * 2)

    // The island's most, the music island's while what plays is on it, and
    // the rows, less the side padding: several parts share the row, what
    // plays giving way; what plays alone is spread to its least, another
    // part alone to the one width it had. An event is as wide as it holds,
    // over what plays as alone (the user, 2026-10-26: the volume taking what
    // plays' width, then the one width, was too wide).
    readonly property int widest: root.musicShown ? root.musicWidest : root.otherWidest
    readonly property int rowRoom: Math.max(0, root.widest - Theme.islandPadX * 2)
    readonly property int musicLeastRow: Math.max(0, root.musicLeast - Theme.islandPadX * 2)
    readonly property int oneRow: Math.max(0, Math.min(root.otherWidest, Theme.islandMinWidth) - Theme.islandPadX * 2)

    // What the others leave to what plays, as far as each has opened: the
    // title gives way while they come in, rather than the island jumping.
    readonly property int musicRoom: Math.max(0, root.rowRoom
        - Math.round((callPart.full + Theme.shareGap) * Math.min(1, callPart.open))
        - Math.round((obsPart.full + Theme.shareGap) * Math.min(1, obsPart.open))
        - Math.round((sharePart.full + Theme.shareGap) * Math.min(1, sharePart.open)))

    // Below this the title is dropped rather than elided to nothing.
    readonly property int titleFloor: Theme.px(56)

    // The meter goes first when room runs out: the cover already says that
    // something plays. With no title there is nothing to leave room for.
    // Kept at rest while paused, so the island keeps its size; gone once
    // cava is given up as missing.
    function meterFits(room: int): bool {
        const words = Media.shownTitle !== "" ? root.itemGap + root.titleFloor : 0;
        return !Cava.givenUp && room - Theme.islandArtSize - root.itemGap - meter.implicitWidth - words >= 0;
    }

    readonly property bool meterShown: root.meterFits(root.musicRoom)
    readonly property int meterWidth: root.meterShown ? meter.implicitWidth + root.itemGap : 0
    readonly property int textRoom: Math.max(0, root.musicRoom - Theme.islandArtSize - root.meterWidth - root.itemGap)
    // What the title and the artist need, read off Texts set as the drawn
    // ones are but given no width: TextMetrics fell short of a Text by a
    // pixel or more, and a name cut with room to spare lost its last letters
    // to an ellipsis (the user's captures, 2026-10-26: "ZENE THE ZIL...",
    // "Street Bab..."); the drawn Text's own, held to its width, read 0 for
    // a title that came after it and kept the title from showing at all.
    readonly property int titleNeed: Media.shownTitle !== "" ? Math.ceil(titleProbe.implicitWidth) : 0
    readonly property int artistNeed: Media.shownTitle !== "" && Media.shownArtist !== ""
                                      ? Math.ceil(artistProbe.implicitWidth) : 0

    Text {
        id: titleProbe

        visible: false
        text: Media.shownTitle
        textFormat: Text.PlainText
        font.family: Theme.uiFont
        font.pixelSize: Theme.menuBarTextSize
    }

    Text {
        id: artistProbe

        visible: false
        text: `  ·  ${Media.shownArtist}`
        textFormat: Text.PlainText
        font.family: Theme.uiFont
        font.pixelSize: Theme.menuBarTextSize
    }
    readonly property int textWidth: root.textRoom < root.titleFloor ? 0
                                   : Math.min(root.titleNeed + root.artistNeed, root.textRoom)
    readonly property int titleWidth: Math.min(root.titleNeed, root.textWidth)

    // The meter's share of the row's most, as in the user's capture
    // (2026-10-26: 22 bars of a 558 px row), so a long title and the meter
    // keep their proportions on any screen.
    readonly property int meterBars: Math.max(Theme.islandMeterFewest, Math.floor((Theme.islandMeterShare * root.rowRoom + Theme.vizBarSpacing)
                                                              / (Theme.vizBarWidth + Theme.vizBarSpacing)))

    // Between neighbours, as far as both are open.
    function gapBetween(open: real, before: real): int {
        return Math.round(Theme.shareGap * Math.max(0, Math.min(open, before)));
    }

    readonly property int callGap: root.gapBetween(callPart.open, musicPart.open)
    readonly property int obsGap: root.gapBetween(obsPart.open, Math.max(musicPart.open, callPart.open))
    readonly property int shareGapNow: root.gapBetween(sharePart.open,
        Math.max(musicPart.open, callPart.open, obsPart.open))
    readonly property int eventGap: root.gapBetween(eventPart.open,
        Math.max(musicPart.open, callPart.open, obsPart.open, sharePart.open))

    readonly property int rowWidth: musicPart.span + root.callGap + callPart.span + root.obsGap + obsPart.span
                                    + root.shareGapNow + sharePart.span + root.eventGap + eventPart.span

    // cava holds a capture stream, so it runs only while what plays shows and
    // plays. A Binding with RestoreNone, so a bar copy torn down on a monitor
    // change cannot switch it off under a surviving one.
    Binding {
        target: Cava
        property: "active"
        value: Media.steadyPlaying && Media.islandOn
        restoreMode: Binding.RestoreNone
    }

    visible: root.up
    // Even, so its middle is a whole pixel: the player it grows into
    // (MediaPopup.qml) is placed by it and must meet it exactly.
    implicitWidth: 2 * Math.ceil((root.rowWidth + Theme.islandPadX * 2) / 2)
    implicitHeight: Theme.barHeight

    // What the pill holds fades before the player takes the island over and
    // after it gives it back: the two surfaces hand over an empty pill.
    property real handFade: card.shown || card.alive ? 0 : 1

    Behavior on handFade {
        NumberAnimation {
            duration: Theme.islandHandMs
            easing.type: Easing.InOutQuad
        }
    }

    TextMetrics {
        id: shareMetrics

        font.family: Theme.uiFont
        font.pixelSize: Theme.menuBarTextSize
        text: shareLabel.text
    }

    TextMetrics {
        id: callMetrics

        font.family: Theme.uiFont
        font.pixelSize: Theme.menuBarTextSize
        text: root.callName
    }

    TextMetrics {
        id: obsMetrics

        font.family: Theme.uiFont
        font.pixelSize: Theme.menuBarTextSize
        text: obsLabel.text
    }

    // ---- the pill ----------------------------------------------------------

    // A dot, then stretched, round at its ends at every size; what it holds
    // shrinks and fades toward the same point, gone before the dot. As far
    // from the bar's top as from its bottom (Theme.islandHeight).
    readonly property int pillTop: Theme.islandInset

    Item {
        id: body

        x: Math.round((root.width - body.width) / 2)
        y: root.pillTop + (Theme.islandHeight - body.height) / 2
        height: Math.round(Theme.islandHeight * root.roundness)
        width: Math.round(body.height + Math.max(0, root.width - Theme.islandHeight) * root.stretch)
        // The player draws the island while it holds it.
        visible: !card.holding

        IslandShape {
            bodyWidth: body.width
            bodyHeight: body.height
            round: body.height / 2
            bottomRound: body.height / 2
        }

        Item {
            anchors.fill: parent
            clip: true

            // The pill's full size and place, so what it holds is centred
            // on the pill, not on the bar.
            Item {
                x: -body.x
                y: root.pillTop - body.y
                width: root.width
                height: Theme.islandHeight
                opacity: Math.max(0, Math.min(1, (root.openness - 0.55) / 0.35)) * root.handFade
                scale: 0.6 + 0.4 * Math.min(1, root.stretch)

                Row {
                    anchors.centerIn: parent

                    // What plays: the cover, the title and artist, the meter
                    // at the right end.
                    IslandPart {
                        id: musicPart

                        readonly property int natural: Theme.islandArtSize + root.meterWidth
                                                       + (root.textWidth > 0 ? root.itemGap + root.textWidth : 0)

                        wanted: root.musicWanted
                        spread: root.single && root.musicWanted ? Math.max(0, root.musicLeastRow - musicPart.natural) : 0
                        full: musicPart.natural + Math.round(musicPart.extra)

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter

                            // The cover, or a note where the player gives none
                            // (Theme.localArt filters the URL).
                            ClippingRectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.islandArtSize
                                height: Theme.islandArtSize
                                radius: Theme.islandArtRadius
                                color: Theme.islandFill

                                Image {
                                    id: art

                                    anchors.fill: parent
                                    source: Theme.localArt(Media.shownArtUrl)
                                    // Three times its size: at the bar's own it came out
                                    // soft on a fractionally scaled output.
                                    sourceSize.width: Theme.islandArtSize * 3
                                    sourceSize.height: Theme.islandArtSize * 3
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true
                                    mipmap: true
                                    visible: art.status === Image.Ready

                                    onStatusChanged: {
                                        if (art.status === Image.Ready)
                                            artBefore.source = art.source;
                                    }
                                }

                                // The cover before, kept until the next has
                                // loaded: a change of track flashed the note
                                // between the two.
                                Image {
                                    id: artBefore

                                    anchors.fill: parent
                                    sourceSize.width: Theme.islandArtSize * 3
                                    sourceSize.height: Theme.islandArtSize * 3
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true
                                    mipmap: true
                                    visible: !art.visible && art.source.toString() !== ""
                                             && artBefore.status === Image.Ready
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !art.visible && !artBefore.visible
                                    text: Theme.iconMusic
                                    font.family: Theme.iconFont
                                    font.pixelSize: Math.round(Theme.islandArtSize * 0.5)
                                    color: Theme.islandSubtext
                                }
                            }

                            Item {
                                width: root.textWidth > 0 ? root.itemGap : 0
                                height: 1
                            }

                            // Title white, artist grey after it, the artist
                            // cut first. Player metadata (a browser's comes
                            // from the page): never markup.
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.textWidth > 0

                                Text {
                                    width: root.titleWidth
                                    height: Theme.barLineHeight
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    text: Media.shownTitle
                                    textFormat: Text.PlainText
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.menuBarTextSize
                                    color: Theme.islandText
                                }

                                Text {
                                    width: Math.max(0, root.textWidth - root.titleWidth)
                                    height: Theme.barLineHeight
                                    visible: width > 0 && Media.shownArtist !== ""
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    text: `  ·  ${Media.shownArtist}`
                                    textFormat: Text.PlainText
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.menuBarTextSize
                                    color: Theme.islandSubtext
                                }
                            }

                            Item {
                                width: Math.round(musicPart.extra)
                                height: 1
                            }

                            Item {
                                width: root.meterShown ? root.itemGap : 0
                                height: 1
                            }

                            Visualizer {
                                id: meter

                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.meterShown
                                bars: root.meterBars
                                levelHeight: Theme.islandArtSize
                                live: Media.steadyPlaying
                                barColor: Media.steadyPlaying ? Media.artColor : Media.artDim
                            }
                        }
                    }

                    Item {
                        width: root.callGap
                        height: 1
                    }

                    // A call: the program, its name alone, and how long.
                    IslandPart {
                        id: callPart

                        // The least it shows: the icon and the clock; the name
                        // only shows alone.
                        readonly property int floor: Theme.shareIconSize + root.itemGap + callClock.implicitWidth
                        readonly property bool named: root.single && root.callWanted
                        readonly property int nameWidth: callPart.named
                            ? Math.max(0, Math.min(Math.ceil(callMetrics.width) + Theme.px(2),
                                                   root.rowRoom - callPart.floor - root.itemGap))
                            : 0
                        // A short name shows whole; one cut is dropped
                        // below the floor rather than cut to nothing.
                        readonly property bool nameShown: callPart.nameWidth > 0
                            && callPart.nameWidth >= Math.min(root.titleFloor, Math.ceil(callMetrics.width) + Theme.px(2))
                        readonly property int natural: callPart.floor
                            + (callPart.nameShown ? root.itemGap + callPart.nameWidth : 0)

                        wanted: root.callWanted
                        spread: callPart.named ? Math.max(0, root.oneRow - callPart.natural) : 0
                        full: callPart.natural + Math.round(callPart.extra)

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.itemGap

                            // Three times its size, as the tray's icons.
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.shareIconSize
                                height: Theme.shareIconSize
                                source: root.callIcon
                                sourceSize.width: Theme.shareIconSize * 3
                                sourceSize.height: Theme.shareIconSize * 3
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                smooth: true
                                mipmap: true
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: callPart.nameShown
                                width: callPart.nameWidth
                                height: Theme.barLineHeight
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                text: root.callName
                                textFormat: Text.PlainText
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.menuBarTextSize
                                color: Theme.islandText
                            }

                            Item {
                                width: Math.max(0, Math.round(callPart.extra) - parent.spacing)
                                height: 1
                                visible: callPart.extra >= 1
                            }

                            // Figures of one width, so the island holds still
                            // as the seconds turn.
                            Text {
                                id: callClock

                                anchors.verticalCenter: parent.verticalCenter
                                height: Theme.barLineHeight
                                verticalAlignment: Text.AlignVCenter
                                text: root.callClock
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.menuBarTextSize
                                font.features: ({ "tnum": 1 })
                                color: Theme.islandGreen
                            }
                        }
                    }

                    Item {
                        width: root.obsGap
                        height: 1
                    }

                    // OBS: a red dot while it records, the pause sign in grey
                    // while paused, the broadcast sign while only live; what,
                    // alone; how long.
                    IslandPart {
                        id: obsPart

                        readonly property int floor: Theme.statusIconSize + root.itemGap + obsClock.implicitWidth
                        readonly property int compact: obsPart.floor
                        readonly property bool named: root.single && root.obsWanted
                        readonly property int nameWidth: obsPart.named
                            ? Math.max(0, Math.min(Math.ceil(obsMetrics.width) + Theme.px(2),
                                                   root.rowRoom - obsPart.compact - root.itemGap))
                            : 0
                        readonly property bool nameShown: obsPart.nameWidth > 0
                            && obsPart.nameWidth >= Math.min(root.titleFloor, Math.ceil(obsMetrics.width) + Theme.px(2))
                        readonly property int natural: obsPart.compact
                            + (obsPart.nameShown ? root.itemGap + obsPart.nameWidth : 0)
                        // Grey while paused: nothing is being recorded, and
                        // the red's companion was too dark to read as text.
                        readonly property color tone: root.obsPaused ? Theme.islandSubtext : Theme.islandRed

                        wanted: root.obsWanted
                        spread: obsPart.named ? Math.max(0, root.oneRow - obsPart.natural) : 0
                        full: obsPart.natural + Math.round(obsPart.extra)

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.itemGap

                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.statusIconSize
                                height: Theme.statusIconSize

                                Rectangle {
                                    anchors.centerIn: parent
                                    visible: root.obsRecording && !root.obsPaused
                                    width: Theme.shareDotSize
                                    height: Theme.shareDotSize
                                    radius: Theme.shareDotSize / 2
                                    color: Theme.islandRed
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !root.obsRecording || root.obsPaused
                                    text: root.obsPaused ? Theme.iconPauseMd : Theme.iconBroadcast
                                    font.family: Theme.iconFont
                                    font.pixelSize: Theme.statusIconSize
                                    color: obsPart.tone
                                }
                            }

                            Text {
                                id: obsLabel

                                anchors.verticalCenter: parent.verticalCenter
                                visible: obsPart.nameShown
                                width: obsPart.nameWidth
                                height: Theme.barLineHeight
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                text: root.obsPaused ? "Paused"
                                    : root.obsRecording && root.obsStreaming ? "Recording, live"
                                    : root.obsRecording ? "Recording" : "Live"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.menuBarTextSize
                                color: Theme.islandText
                            }

                            Item {
                                width: Math.max(0, Math.round(obsPart.extra) - parent.spacing)
                                height: 1
                                visible: obsPart.extra >= 1
                            }

                            Text {
                                id: obsClock

                                anchors.verticalCenter: parent.verticalCenter
                                height: Theme.barLineHeight
                                verticalAlignment: Text.AlignVCenter
                                text: root.obsClock
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.menuBarTextSize
                                font.features: ({ "tnum": 1 })
                                color: obsPart.tone
                            }
                        }
                    }

                    Item {
                        width: root.shareGapNow
                        height: 1
                    }

                    // The share: the dot, who shares, what (alone), how long.
                    IslandPart {
                        id: sharePart

                        // The least it shows (the dot and the clock), and all
                        // but what is shared, which only fills a part alone.
                        readonly property int floor: dot.width + root.itemGap + shareClock.implicitWidth
                        readonly property int compact: sharePart.floor
                            + root.shareApps.length * (Theme.shareIconSize + root.itemGap)
                        readonly property bool named: root.single && root.shareWanted
                        readonly property int nameWidth: sharePart.named
                            ? Math.max(0, Math.min(Math.ceil(shareMetrics.width) + Theme.px(2),
                                                   root.rowRoom - sharePart.compact - root.itemGap))
                            : 0
                        readonly property bool nameShown: sharePart.nameWidth > 0
                            && sharePart.nameWidth >= Math.min(root.titleFloor, Math.ceil(shareMetrics.width) + Theme.px(2))
                        readonly property int natural: sharePart.compact
                            + (sharePart.nameShown ? root.itemGap + sharePart.nameWidth : 0)

                        wanted: root.shareWanted
                        spread: sharePart.named ? Math.max(0, root.oneRow - sharePart.natural) : 0
                        full: sharePart.natural + Math.round(sharePart.extra)

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: root.itemGap

                            Rectangle {
                                id: dot

                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.shareDotSize
                                height: Theme.shareDotSize
                                radius: Theme.shareDotSize / 2
                                color: Theme.islandRed
                            }

                            // Three times their size, as the tray's icons.
                            Repeater {
                                model: root.shareApps

                                Image {
                                    required property var modelData

                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.shareIconSize
                                    height: Theme.shareIconSize
                                    source: modelData.icon
                                    sourceSize.width: Theme.shareIconSize * 3
                                    sourceSize.height: Theme.shareIconSize * 3
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                    mipmap: true
                                }
                            }

                            Text {
                                id: shareLabel

                                anchors.verticalCenter: parent.verticalCenter
                                visible: sharePart.nameShown
                                width: sharePart.nameWidth
                                height: Theme.barLineHeight
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                text: root.shareKind === "window" ? "Sharing a window" : "Sharing screen"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.menuBarTextSize
                                color: Theme.islandText
                            }

                            Item {
                                width: Math.max(0, Math.round(sharePart.extra) - parent.spacing)
                                height: 1
                                visible: sharePart.extra >= 1
                            }

                            // Figures of one width, so the island holds still
                            // as the seconds turn; red, as the recording
                            // reference's time.
                            Text {
                                id: shareClock

                                anchors.verticalCenter: parent.verticalCenter
                                height: Theme.barLineHeight
                                verticalAlignment: Text.AlignVCenter
                                text: root.shareClock
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.menuBarTextSize
                                font.features: ({ "tnum": 1 })
                                color: Theme.islandRed
                            }
                        }
                    }

                    Item {
                        width: root.eventGap
                        height: 1
                    }

                    // A system event (Island.qml), made only while one shows
                    // or goes; words at the left, value at the right end.
                    IslandPart {
                        id: eventPart

                        readonly property int natural: Math.min(eventLoader.item?.natural ?? 0, root.rowRoom)

                        wanted: root.eventWanted
                        full: eventPart.natural

                        Loader {
                            id: eventLoader

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            active: root.eventWanted || eventPart.open > 0

                            sourceComponent: IslandEvent {
                                glyph: root.eventGlyph
                                text: root.eventText
                                value: root.eventValue
                                level: root.eventLevel
                                battery: root.eventBattery
                                tone: root.eventTone
                            }
                        }
                    }
                }
            }
        }
    }

    // A hand, as over all the pointer acts on. Grows only for what has more
    // to show and control (what plays, a call, OBS; the user, 2026-10-26),
    // and only with the pill out and still: the player takes it over at rest.
    HoverHandler {
        id: hover

        enabled: (root.musicWanted || root.callWanted || root.obsWanted) && !opening.running && !shutting.running
        cursorShape: Qt.PointingHandCursor
    }

    MediaPopup {
        id: card

        anchorItem: root
        anchorHovered: hover.hovered
        islandBare: root.handFade < 0.02
        showPlayer: root.musicShown
        showCalls: root.callShown
        showObs: root.obsShown
    }
}
