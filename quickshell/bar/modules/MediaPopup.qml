pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.services

// The island grown by a hover (MediaChip.qml) into the player
// (MediaPlayer.qml), with the calls and OBS under it (IslandActivities.qml),
// those alone when nothing plays. One island, as the user asked (2026-10-26:
// the pill gives way to the larger island and comes back, nothing overlapping
// between): this popup takes the pill over from the bar as an empty pill
// drawn alike (IslandShape.qml), grows it and gives it back. Grown, it hangs
// from the screen's top edge as a screen notch grown into its player (the
// user's references): the pill rises to the edge, flares into it and grows
// down past the bar as the notification panel opens (Theme.islandGrowMs),
// with no rim and a soft shadow as the references have (Theme.islandShadow).
//
// The hand-over never shows both or neither: the pill's content fades first
// (MediaChip.handFade); this pill shows over the bar's, which then goes
// (holding); back, the bar's shows again before this surface goes.
//
// The open state is this bar's own, so it opens on the screen the pointer
// is on. A PopupWindow anchored to the island: a layer surface is placed
// after other exclusive zones whatever its mode (measured) and could not lie
// over the bar.
Item {
    id: root

    property Item anchorItem: root.parent

    // Open while either the island in the bar or the grown one is hovered.
    property bool anchorHovered: false
    property bool cardHovered: false

    // Open as far as the user is concerned; the surface outlives it by its
    // way back into the pill (alive).
    property bool shown: false
    property bool alive: false

    // Set by MediaChip once what its pill holds has gone.
    property bool islandBare: false
    // What the grown island holds, as MediaChip shows them.
    property bool showPlayer: false
    property bool showCalls: false
    property bool showObs: false
    // While this surface draws the island in the bar's place.
    property bool holding: false

    // Hung from the bottom edge for a bar at the bottom.
    readonly property bool up: Theme.barAtBottom

    // The pointer gone from the grown island, it shuts within a frame or two
    // (the user, 2026-10-26: it lingered). Gone from the bar's pill, it waits
    // longer: the grown island taking the pointer from the pill leaves the
    // bar's surface a frame before it enters its own.
    onAnchorHoveredChanged: root.hovered(200)
    onCardHoveredChanged: root.hovered(40)

    function hovered(grace: int): void {
        if (root.anchorHovered || root.cardHovered) {
            hide.stop();
            root.shown = true;
        } else {
            hide.interval = grace;
            hide.restart();
        }
    }

    // With nothing to show there is no way back to wait for.
    onShownChanged: {
        if (root.shown)
            root.alive = true;
        else if (!cardLoader.active)
            root.alive = false;
    }

    Timer {
        id: hide

        onTriggered: root.shown = false
    }

    // Gone with what it shows, Super+M included, even under the pointer.
    Loader {
        id: cardLoader

        active: root.alive && (root.showPlayer || root.showCalls || root.showObs)

        // Torn down under the pointer it reports no exit; a hover left set
        // would reopen it later with the pointer gone.
        onActiveChanged: {
            if (!active) {
                root.cardHovered = false;
                root.holding = false;
            }
        }

        sourceComponent: PopupWindow {
            id: popup

            // The island's share of the bar's screen, as on the reference output.
            readonly property real fit: Theme.fit(root.QsWindow.window?.screen)
            // One size throughout: a surface resized as it animates is placed
            // again by Hyprland at every size and trembles. The growth has no
            // overshoot to leave room for.
            readonly property real reach: 1

            // The card, in reference pixels, which the grown island is: from
            // the screen's edge, padded alike on all four sides. The bar's
            // height left above it read as empty space (the user, 2026-10-26).
            readonly property int cardWidth: Theme.mediaCardWidth
            readonly property int cardHeight: content.implicitHeight + Theme.popupPad * 2
            // Room for the shadow beside and below.
            readonly property int shade: Theme.islandShadowBlur + Theme.islandShadowOffset

            // Even, as the island's width is (MediaChip), so the island's
            // left edge falls on a whole pixel here.
            readonly property int stageWidth: 2 * Math.ceil((popup.cardWidth * popup.reach + Theme.islandEarRadius * 2
                                                             + popup.shade * 2) / 2)
            readonly property int stageHeight: Math.ceil(popup.cardHeight * popup.reach) + popup.shade
            readonly property real islandWidth: root.anchorItem?.width ?? 0
            readonly property real islandLeft: (popup.stageWidth - popup.islandWidth) / 2

            visible: true
            color: "transparent"
            grabFocus: false
            implicitWidth: Math.ceil(popup.stageWidth * popup.fit)
            implicitHeight: Math.ceil(popup.stageHeight * popup.fit)

            // Its corner at the screen's edge, as far left of the island as
            // centres the two: by a corner, so no half pixel rounds one way
            // here and another in the bar. Not moved to fit: Hyprland slid
            // it 4 px down from the edge (measured).
            anchor {
                window: root.QsWindow.window
                item: root.anchorItem
                rect.x: -popup.islandLeft
                rect.y: root.up ? (root.anchorItem?.height ?? 0) : 0
                rect.width: 1
                rect.height: 1
                edges: (root.up ? Edges.Bottom : Edges.Top) | Edges.Left
                gravity: (root.up ? Edges.Top : Edges.Bottom) | Edges.Right
                adjustment: PopupAdjustment.None
            }

            // Only the grown island at rest takes the pointer, all of it from
            // the start: a region following the moving shape let the pointer
            // through over the transport.
            mask: Region {
                item: hit
            }

            // Reference pixels, scaled by the screen's factor.
            Item {
                id: stage

                // 0 the pill, 1 the grown island.
                property real openness: 0

                // Until the surface's first frame: started with the window,
                // most of the growth was over before the popup showed
                // (measured). afterAnimating comes on this thread.
                property bool waiting: true

                // Drawn once the bar's pill is bare and this surface is up.
                property bool revealed: false

                function clamp01(v: real): real {
                    return Math.max(0, Math.min(1, v));
                }

                // How far the pill has risen to the screen's edge, eased at
                // both ends, and how far its corners have flared since.
                readonly property real attach: {
                    const a = stage.clamp01(stage.openness / Theme.islandAttachAt);
                    return a * a * (3 - 2 * a);
                }
                readonly property real flare: stage.clamp01((stage.openness - Theme.islandAttachAt) / (1 - Theme.islandAttachAt))

                function reveal(): void {
                    if (stage.revealed || stage.waiting || !root.islandBare || !root.shown)
                        return;
                    stage.revealed = true;
                    stage.open();
                }

                function open(): void {
                    shutting.stop();
                    give.stop();
                    opening.restart();
                    take.restart();
                }

                function shut(): void {
                    opening.stop();
                    take.stop();
                    shutting.restart();
                }

                width: popup.stageWidth
                height: popup.stageHeight
                scale: popup.fit
                transformOrigin: Item.TopLeft
                opacity: stage.revealed ? 1 : 0

                Connections {
                    target: stage.Window.window
                    enabled: stage.waiting

                    function onAfterAnimating(): void {
                        stage.waiting = false;
                        if (root.shown)
                            stage.reveal();
                        else
                            root.alive = false;
                    }
                }

                Connections {
                    target: root

                    function onIslandBareChanged(): void {
                        stage.reveal();
                    }

                    function onShownChanged(): void {
                        if (stage.waiting)
                            return;
                        if (root.shown) {
                            if (stage.revealed)
                                stage.open();
                            else
                                stage.reveal();
                        } else if (stage.revealed) {
                            stage.shut();
                        } else {
                            root.alive = false;
                        }
                    }
                }

                // The bar's pill goes a moment after this one is drawn, so no
                // frame shows neither.
                Timer {
                    id: take

                    interval: 50
                    onTriggered: root.holding = true
                }

                // Back: the bar's pill first, this surface a moment after.
                Timer {
                    id: give

                    interval: 50
                    onTriggered: {
                        if (!root.shown)
                            root.alive = false;
                    }
                }

                // From wherever the other left it, both ways on the
                // notification panel's opening (Theme.islandGrowMs): quick at
                // once and easing to rest.
                NumberAnimation {
                    id: opening

                    target: stage
                    property: "openness"
                    to: 1
                    duration: Theme.islandGrowMs
                    easing.type: Easing.OutCubic
                }

                SequentialAnimation {
                    id: shutting

                    NumberAnimation {
                        target: stage
                        property: "openness"
                        to: 0
                        duration: Theme.islandGrowMs
                        easing.type: Easing.OutCubic
                    }
                    ScriptAction {
                        script: {
                            root.holding = false;
                            give.restart();
                        }
                    }
                }

                // The grown island at rest: the pointer's region and where the
                // hover is read. Parent of all drawn, since hover reaches a
                // control's ancestors only: read beside the shape it missed a
                // pointer that came straight onto the play-pause (measured).
                Item {
                    id: hit

                    // The pill and the grown island, here: the pill where the
                    // bar has it, the grown island from the screen's edge.
                    readonly property real pillX: popup.islandLeft - hit.x
                    readonly property real pillTop: Theme.islandInset
                    readonly property real pillHeight: Theme.islandHeight
                    readonly property real t: stage.openness

                    readonly property real bodyX: hit.pillX * (1 - hit.t)
                    readonly property real bodyWidth: popup.islandWidth + (popup.cardWidth - popup.islandWidth) * hit.t
                    readonly property real bodyTop: hit.pillTop * (1 - stage.attach)
                    readonly property real bodyBottom: hit.pillTop + hit.pillHeight
                        + (popup.cardHeight - hit.pillTop - hit.pillHeight) * hit.t
                    // The body as seen from here (the shape is turned over for
                    // a bar at the bottom).
                    readonly property real seenTop: root.up ? hit.height - hit.bodyBottom : hit.bodyTop

                    x: Math.round((stage.width - popup.cardWidth) / 2)
                    y: root.up ? stage.height - popup.cardHeight : 0
                    width: popup.cardWidth
                    height: popup.cardHeight

                    HoverHandler {
                        onHoveredChanged: root.cardHovered = hovered
                    }

                    // Under the body as it grows, none on the pill (the bar's
                    // pill casts none); downward either way, as from a light
                    // above; square where it meets the screen's edge.
                    RectangularShadow {
                        readonly property real foot: Math.min(hit.bodyBottom - hit.bodyTop, Theme.islandPanelRadius)
                                                     * stage.clamp01(hit.t)

                        x: hit.bodyX
                        y: hit.seenTop
                        width: Math.max(0, hit.bodyWidth)
                        height: Math.max(0, hit.bodyBottom - hit.bodyTop)
                        visible: hit.t > 0.02
                        opacity: stage.clamp01(hit.t)
                        bottomLeftRadius: root.up ? 0 : foot
                        bottomRightRadius: root.up ? 0 : foot
                        topLeftRadius: root.up ? foot : 0
                        topRightRadius: root.up ? foot : 0
                        blur: Theme.islandShadowBlur
                        offset: Qt.vector2d(0, Theme.islandShadowOffset)
                        color: Theme.islandShadow
                    }

                    IslandShape {
                        bodyX: hit.bodyX
                        bodyTop: hit.bodyTop
                        bodyWidth: hit.bodyWidth
                        bodyHeight: hit.bodyBottom - hit.bodyTop
                        round: hit.pillHeight / 2 * (1 - stage.attach)
                        ear: Theme.islandEarRadius * stage.flare
                        bottomRound: hit.pillHeight / 2
                            + (Theme.islandPanelRadius - hit.pillHeight / 2) * stage.clamp01(hit.t)
                    }

                    // The card at its own size, uncovered as the island grows
                    // round it.
                    Item {
                        x: hit.bodyX
                        y: hit.seenTop
                        width: Math.max(0, hit.bodyWidth)
                        height: Math.max(0, hit.bodyBottom - hit.bodyTop)
                        clip: true

                        Item {
                            x: -hit.bodyX
                            y: -hit.seenTop
                            width: popup.cardWidth
                            height: popup.cardHeight
                            opacity: stage.clamp01((stage.openness - 0.5) / 0.4)

                            Column {
                                id: content

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Theme.popupPad
                                anchors.rightMargin: Theme.popupPad
                                spacing: Theme.islandRowGap

                                MediaPlayer {
                                    width: parent.width
                                    visible: root.showPlayer
                                }

                                IslandActivities {
                                    width: parent.width
                                    visible: root.showCalls || root.showObs
                                    showCalls: root.showCalls
                                    showObs: root.showObs
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
