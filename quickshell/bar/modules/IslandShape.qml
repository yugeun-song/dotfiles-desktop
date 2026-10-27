import QtQuick
import QtQuick.Shapes
import qs.services

// The island's shape, drawn alike by the pill in the bar (MediaChip.qml) and
// the player it grows into (MediaPopup.qml) from the same numbers, so the
// hand-over moves nothing: one shape throughout, as the user asked
// (2026-10-26), the pill rising to the screen's top edge and growing down.
//
// Top corners round (`round`, the pill's) or flared into the screen's top
// edge (`ear`, the grown island's, as a notch flares into the bezel), never
// both; lower corners `bottomRound`. Black to its edge with no rim, as in the
// user's references (Theme.islandShadow sets it off). Laid out in the
// parent's coordinates, the flares outside the body; turned over for a bar at
// the bottom.
Shape {
    id: root

    property real bodyX: 0
    property real bodyTop: 0
    property real bodyWidth: 0
    property real bodyHeight: 0
    property real round: 0
    property real ear: 0
    property real bottomRound: 0

    readonly property real w: Math.max(0, root.bodyWidth)
    readonly property real h: Math.max(0, root.bodyHeight)
    readonly property real rc: Math.max(0, Math.min(root.round, root.w / 2, root.h / 2))
    readonly property real re: root.rc > 0 ? 0 : Math.max(0, Math.min(root.ear, root.h / 2))
    readonly property real corner: Math.max(root.rc, root.re)
    readonly property real rb: Math.max(0, Math.min(root.bottomRound, root.w / 2, root.h - root.corner))
    // Not `left`/`right`/`top`/`bottom`: every Item has final anchor lines
    // by those names.
    readonly property real x0: root.bodyX
    readonly property real x1: root.bodyX + root.w
    readonly property real y0: root.bodyTop
    readonly property real y1: root.bodyTop + root.h
    // Round corners turn the way a rectangle's do; flares the other way.
    readonly property int topTurn: root.re > 0 ? PathArc.Clockwise : PathArc.Counterclockwise

    anchors.fill: parent
    visible: root.w > 0 && root.h > 0
    preferredRendererType: Shape.CurveRenderer

    transform: Scale {
        origin.y: root.height / 2
        yScale: Theme.barAtBottom ? -1 : 1
    }

    ShapePath {
        fillColor: Theme.islandColor
        strokeWidth: -1
        startX: root.x0
        startY: root.y0 + root.corner

        PathLine {
            x: root.x0
            y: root.y1 - root.rb
        }
        PathArc {
            x: root.x0 + root.rb
            y: root.y1
            radiusX: root.rb
            radiusY: root.rb
            direction: PathArc.Counterclockwise
        }
        PathLine {
            x: root.x1 - root.rb
            y: root.y1
        }
        PathArc {
            x: root.x1
            y: root.y1 - root.rb
            radiusX: root.rb
            radiusY: root.rb
            direction: PathArc.Counterclockwise
        }
        PathLine {
            x: root.x1
            y: root.y0 + root.corner
        }
        PathArc {
            x: root.x1 + root.re - root.rc
            y: root.y0
            radiusX: root.corner
            radiusY: root.corner
            direction: root.topTurn
        }
        PathLine {
            x: root.x0 - root.re + root.rc
            y: root.y0
        }
        PathArc {
            x: root.x0
            y: root.y0 + root.corner
            radiusX: root.corner
            radiusY: root.corner
            direction: root.topTurn
        }
    }
}
