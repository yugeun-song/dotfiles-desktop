import QtQuick
import QtQuick.Shapes
import qs.services

// A reading's recent past drawn as a stock chart on a dark theme draws a
// day (the user, 2026-11-05): a line over a fill fading to nothing, green
// where it ended higher than it began, red where lower, grey where level;
// the first reading dotted across, as the previous close is, and a dot on
// the last. The readings there are spread over the whole width it is given,
// so the line always reaches both ends (the user, the same day), and scaled
// to their own range, at least `minSpan` tall, so a level reading lies flat
// instead of magnifying noise. One Shape: a Canvas keeps a texture of its own.
Item {
    id: root

    property var values: []
    property real minSpan: 0.02
    property real lineWidth: 1.5

    readonly property color green: "#089981"
    readonly property color red: "#f23645"
    readonly property color grey: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.45)

    readonly property real first: root.values.length > 0 ? root.values[0] : 0
    readonly property real last: root.values.length > 0 ? root.values[root.values.length - 1] : 0
    readonly property color color: {
        const d = root.last - root.first;
        const still = root.minSpan * 0.05;
        return d > still ? root.green : d < -still ? root.red : root.grey;
    }

    readonly property var range: {
        let lo = Infinity;
        let hi = -Infinity;
        for (const v of root.values) {
            lo = Math.min(lo, v);
            hi = Math.max(hi, v);
        }
        if (!Number.isFinite(lo))
            return { lo: 0, hi: 1 };
        if (hi - lo < root.minSpan) {
            const mid = (lo + hi) / 2;
            lo = mid - root.minSpan / 2;
            hi = mid + root.minSpan / 2;
        }
        return { lo: lo, hi: hi };
    }

    function yOf(v: real): real {
        const room = root.height - root.lineWidth * 2;
        return root.lineWidth + (1 - (v - root.range.lo) / (root.range.hi - root.range.lo)) * room;
    }

    readonly property var line: {
        const n = root.values.length;
        if (n < 2 || root.width <= 0)
            return [];
        const step = root.width / (n - 1);
        return root.values.map((v, i) => Qt.point(i * step, root.yOf(v)));
    }

    Shape {
        anchors.fill: parent
        visible: root.line.length > 1
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: 0
                y2: root.height

                GradientStop {
                    position: 0
                    color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.28)
                }

                GradientStop {
                    position: 1
                    color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0)
                }
            }

            PathPolyline {
                path: root.line.length > 1
                    ? [Qt.point(root.line[0].x, root.height)].concat(root.line, [Qt.point(root.width, root.height)]) : []
            }
        }

        ShapePath {
            strokeColor: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.22)
            strokeWidth: 1
            strokeStyle: ShapePath.DashLine
            dashPattern: [2, 3]
            fillColor: "transparent"
            startX: root.line.length > 1 ? root.line[0].x : 0
            startY: root.line.length > 1 ? root.line[0].y : 0

            PathLine {
                x: root.width
                y: root.line.length > 1 ? root.line[0].y : 0
            }
        }

        ShapePath {
            strokeColor: root.color
            strokeWidth: root.lineWidth
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap

            PathPolyline {
                path: root.line
            }
        }
    }

    Rectangle {
        readonly property point end: root.line.length > 1 ? root.line[root.line.length - 1] : Qt.point(0, 0)

        visible: root.line.length > 1
        width: root.lineWidth * 3
        height: width
        radius: width / 2
        x: end.x - width / 2
        y: end.y - height / 2
        color: root.color
    }

    // Before two readings: where the chart will be, faint.
    Rectangle {
        visible: root.line.length < 2
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 1
        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.10)
    }
}
