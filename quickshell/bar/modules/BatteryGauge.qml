import QtQuick
import qs.services

// Drawn rather than taken from the font: the Nerd Font battery ladder only
// has eleven steps, so the level moves in visible jumps. This fills smoothly
// and can show a charge bolt over the same shape.
Item {
    id: root

    property int percent: 0
    property bool charging: false
    property color strokeColor: Theme.ink

    readonly property int bodyHeight: Math.round(Theme.iconSize * 0.78)
    readonly property int bodyWidth: Math.round(root.bodyHeight * 0.58)
    readonly property int stroke: Math.max(1, Math.round(root.bodyHeight / 9))
    readonly property real level: Math.max(0, Math.min(100, root.percent)) / 100

    implicitWidth: root.bodyWidth
    implicitHeight: root.bodyHeight

    Rectangle {
        id: body

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: root.bodyWidth
        height: root.bodyHeight
        radius: Math.max(2, root.stroke * 2)
        color: "transparent"
        border.width: root.stroke
        border.color: root.strokeColor

        Rectangle {
            id: fill

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: root.stroke + 1
            height: Math.max(root.level > 0 ? 1 : 0, (body.height - (root.stroke + 1) * 2) * root.level)
            radius: Math.max(1, root.stroke)
            color: root.strokeColor

            Behavior on height {
                NumberAnimation {
                    duration: 420
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    Text {
        anchors.centerIn: body
        visible: root.charging
        text: String.fromCodePoint(0xF0E7)
        font.family: Theme.iconFont
        font.pixelSize: Math.round(Theme.iconSize * 0.62)
        color: root.strokeColor
        style: Text.Outline
        styleColor: Theme.batteryColor(root.percent)
    }
}
