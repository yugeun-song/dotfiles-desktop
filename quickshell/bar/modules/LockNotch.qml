pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.services

// The lock screen's island as a notch (the user, 2026-11-06, after a
// phone's: grown out of the screen's top edge, its upper corners curving out
// into the edge, its lower ones round). Its size is hyprlock.conf's island,
// fitted to each screen as everything there is, so it keeps one share of
// every monitor (its size and the glyphs' with it: hyprlock.conf says why).
// The part above the edge, which hyprlock (the fallback) draws off the
// screen to square its top, is left out here.
//
// What it holds is what the floating island held, without growing: the
// lock at its left end, or the bar's event's glyph while one lasts (the
// event's number or mark at the right end); while music plays and no event
// does, only a small square of moving bars at the right end, in the cover's
// colour (the user: music must not widen it). Nothing else of the track:
// the card below the clock has it.
Item {
    id: root

    required property var screenRoot
    required property var lockRoot
    // The track card (LockCard): whether something plays, and its cover's
    // colour.
    property var card: null
    // The way in, 0 to 1 (LockScreen): the notch comes down out of the edge.
    property real enter: 1

    readonly property var block: root.screenRoot.o.island ?? ({})
    readonly property real notchW: root.screenRoot.wide(root.block.size?.[0] ?? 0, root.block.even ?? false)
    // hyprlock.conf pushes its shape above the edge by its corner's radius
    // (position y above 0, from the top); what shows is the rest.
    readonly property real notchH: root.screenRoot.tall((root.block.size?.[1] ?? 0) - Math.max(0, root.block.position?.[1] ?? 0))
    readonly property real foot: Math.min(root.notchH / 2, root.screenRoot.tall(root.block.rounding ?? 0))
    // The curve into the edge: half the foot's, as the picture's.
    readonly property real fillet: root.foot * 0.5
    readonly property real notchX: (root.width - root.notchW) / 2 + root.screenRoot.wide(root.block.position?.[0] ?? 0, root.block.even ?? false)
    // A glyph's middle, as far in from each end as from the top and foot.
    readonly property real inset: root.notchH / 2

    readonly property var parts: root.lockRoot.island
    readonly property bool eventOn: root.parts.trail !== "" || root.parts.mark !== "" || root.parts.lead !== Theme.iconLock
    readonly property bool musicOn: (root.card?.present ?? false) && !root.eventOn
    readonly property bool playing: root.card?.playing ?? false
    readonly property color tone: root.parts.tone !== "" ? root.parts.tone : (root.screenRoot.o.lead?.color ?? Theme.fg)

    readonly property alias offset: shift

    transform: Translate {
        id: shift
    }

    Item {
        id: body

        anchors.fill: parent
        // Down out of the edge on the way in.
        y: -(1 - root.enter) * (root.notchH + root.fillet + 4)

        Shape {
            id: shape

            x: root.notchX
            width: root.notchW
            height: root.notchH
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: root.block.color ?? "#000000"
                strokeWidth: -1

                // From above the edge, so no seam shows along it.
                startX: -root.fillet
                startY: -1

                PathLine { x: -root.fillet; y: 0 }
                PathArc { x: 0; y: root.fillet; radiusX: root.fillet; radiusY: root.fillet; direction: PathArc.Clockwise }
                PathLine { x: 0; y: root.notchH - root.foot }
                PathArc { x: root.foot; y: root.notchH; radiusX: root.foot; radiusY: root.foot; direction: PathArc.Counterclockwise }
                PathLine { x: root.notchW - root.foot; y: root.notchH }
                PathArc { x: root.notchW; y: root.notchH - root.foot; radiusX: root.foot; radiusY: root.foot; direction: PathArc.Counterclockwise }
                PathLine { x: root.notchW; y: root.fillet }
                PathArc { x: root.notchW + root.fillet; y: 0; radiusX: root.fillet; radiusY: root.fillet; direction: PathArc.Clockwise }
                PathLine { x: root.notchW + root.fillet; y: -1 }
                PathLine { x: -root.fillet; y: -1 }
            }
        }

        // ---- the left end: the lock, or the event's glyph -----------------
        Glyph {
            id: lead

            cx: root.notchX + root.inset
            cy: root.notchH / 2
            text: root.eventOn ? root.parts.lead : Theme.iconLock
            color: root.eventOn ? root.tone : (root.screenRoot.o.lead?.color ?? Theme.fg)
            family: root.screenRoot.family(root.screenRoot.o.lead?.font_family ?? Theme.iconFont)
            size: root.screenRoot.points(root.screenRoot.o.lead?.font_size ?? 16)
        }

        // ---- the right end: the event's mark and number --------------------
        Glyph {
            id: mark

            cx: root.notchX + root.notchW - root.inset
            cy: root.notchH / 2
            text: root.parts.mark
            color: root.tone
            family: root.screenRoot.family(root.screenRoot.o.mark?.font_family ?? Theme.iconFont)
            size: root.screenRoot.points(root.screenRoot.o.mark?.font_size ?? 16)
            opacity: root.eventOn ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }

        // The number ends where the mark's glyph would: as far in from the
        // right end as the lock from the left.
        Text {
            id: trail

            readonly property var spec: root.screenRoot.o.trail ?? ({})

            visible: root.parts.trail !== ""
            opacity: root.eventOn ? 1 : 0
            x: mark.cx + markProbe.advanceWidth / 2 - trail.implicitWidth
            y: root.notchH / 2 - (trail.baselineOffset - trailInk.inkHeight / 2)
            text: root.parts.trail
            color: root.tone
            textFormat: Text.PlainText
            font.family: root.screenRoot.family(trail.spec.font_family ?? Theme.uiFont)
            font.weight: Font.DemiBold
            font.pixelSize: Math.max(1, root.screenRoot.points(trail.spec.font_size ?? 14))
            font.features: { "tnum": 1 }

            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }

        // The digits' height, to set the number's middle on the notch's.
        TextMetrics {
            id: trailInk

            readonly property real inkHeight: trailInk.tightBoundingRect.height

            font: trail.font
            text: "0"
        }

        TextMetrics {
            id: markProbe

            font.family: mark.family
            font.pixelSize: Math.max(1, mark.size)
            text: Theme.iconCheckCircle
        }

        // ---- the music: a small square of bars -----------------------------
        // cava's levels, its few bands spread over the spectrum, square: as
        // wide as tall, a little smaller than the lock beside it. Runs only
        // while something plays and this shows it.
        Visualizer {
            id: wave

            readonly property int side: Math.max(8, Math.round(root.notchH * 0.42))

            x: mark.cx - wave.side / 2
            y: (root.notchH - wave.side) / 2
            width: wave.side
            height: wave.side
            bars: 4
            barWidth: Math.max(2, Math.round(wave.side * 0.16))
            barSpacing: Math.max(1, Math.round((wave.side - 4 * Math.max(2, Math.round(wave.side * 0.16))) / 3))
            levelHeight: wave.side
            live: root.playing
            barColor: root.playing ? (root.card?.tone ?? Theme.islandText) : Theme.islandDim(root.card?.tone ?? Theme.islandText)
            opacity: root.musicOn ? 1 : 0
            visible: wave.opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
        }

        Binding {
            target: Cava
            property: "active"
            value: root.musicOn && root.playing && root.visible
        }
    }

    // A glyph set by its ink's middle, not its box's: icons sit unevenly in
    // their em boxes.
    component Glyph: Text {
        id: glyph

        property real cx: 0
        property real cy: 0
        property string family: Theme.iconFont
        property real size: 16

        x: glyph.cx - (ink.tightBoundingRect.x + ink.tightBoundingRect.width / 2)
        y: glyph.cy - (glyph.baselineOffset + ink.tightBoundingRect.y + ink.tightBoundingRect.height / 2)
        textFormat: Text.PlainText
        font.family: glyph.family
        font.pixelSize: Math.max(1, glyph.size)

        TextMetrics {
            id: ink

            font: glyph.font
            text: glyph.text
        }
    }
}
