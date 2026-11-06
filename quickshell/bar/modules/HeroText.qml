import QtQuick
import qs.services

// A widget's one large figure, after the user's rule for the desktop widgets
// (2026-11-05): what a widget stresses is drawn huge, everything else small,
// nothing in between. Sized so `probe`, the widest text the figure usually
// takes, fills the box, measured on the figures' own outline rather than the
// line's height, so the box's edges are where the ink is; the size holds from
// one value to the next, and a wider value shrinks to the box. Tabular
// figures for one that ticks, so it does not jitter; proportional ones for
// one that stands still, its ink set flush with the box's left edge, where
// the small text above or below it starts.
Item {
    id: root

    property string text: ""
    property string probe: "00"
    // "left", "center" or "right"; "top", "center" or "bottom".
    property string horizontal: "left"
    property string vertical: "center"
    property bool tabular: false
    property color color: Theme.fg
    // Regular: DemiBold read too heavy at these sizes (the user, 2026-11-05).
    property int weight: Font.Normal

    // The figures' baseline from the box's top, for small text set on it.
    readonly property real figureBaseline: root.inkTop + root.rise
    readonly property real inkHeight: root.figureH
    // Where the drawn text ends, from the box's left: a unit set after it.
    readonly property real advanceRight: drawn.x + drawn.implicitWidth

    // At 100 px: a zero's outline (the tallest figure, round at both ends),
    // the left bearing of the text's ink, and the advances as drawn.
    TextMetrics {
        id: zero

        font.family: Theme.uiFont
        font.weight: root.weight
        font.pixelSize: 100
        text: "0"
    }

    TextMetrics {
        id: ink

        font.family: Theme.uiFont
        font.weight: root.weight
        font.pixelSize: 100
        text: root.text
    }

    Text {
        id: probeAdvance

        visible: false
        text: root.probe
        font.family: Theme.uiFont
        font.weight: root.weight
        font.pixelSize: 100
        font.features: root.tabular ? ({ "tnum": 1 }) : ({})
    }

    Text {
        id: textAdvance

        visible: false
        text: root.text
        font.family: Theme.uiFont
        font.weight: root.weight
        font.pixelSize: 100
        font.features: root.tabular ? ({ "tnum": 1 }) : ({})
    }

    readonly property real fitSize: {
        const h = zero.tightBoundingRect.height;
        const pw = probeAdvance.implicitWidth;
        const tw = textAdvance.implicitWidth;
        if (!(h > 0) || !(pw > 0) || root.width <= 0 || root.height <= 0)
            return 0;
        const k = Math.min(root.height / h, root.width / pw, tw > 0 ? root.width / tw : Infinity);
        return Math.max(1, Math.floor(100 * k));
    }
    readonly property real scaleK: root.fitSize / 100
    readonly property real figureH: zero.tightBoundingRect.height * root.scaleK
    // From the ink's top to the baseline.
    readonly property real rise: -zero.tightBoundingRect.y * root.scaleK
    readonly property real inkTop: root.vertical === "top" ? 0
        : root.vertical === "bottom" ? root.height - root.figureH
        : (root.height - root.figureH) / 2
    readonly property real bearing: root.tabular ? 0 : ink.tightBoundingRect.x * root.scaleK

    Text {
        id: drawn

        visible: root.fitSize > 0
        x: root.horizontal === "right" ? root.width - drawn.implicitWidth
            : root.horizontal === "center" ? (root.width - drawn.implicitWidth) / 2
            : -root.bearing
        anchors.baseline: parent.top
        anchors.baselineOffset: root.figureBaseline
        text: root.text
        font.family: Theme.uiFont
        font.weight: root.weight
        font.pixelSize: Math.max(1, root.fitSize)
        font.features: root.tabular ? ({ "tnum": 1 }) : ({})
        color: root.color
    }
}
