import QtQuick
import qs.services

// One key, drawn as a cap rather than as a label.
//
// The shape is two rectangles, not one with a shadow: the lower one is the
// side of the key and the upper one its face, offset up by a couple of pixels.
// Qt Quick has no cheap drop shadow without pulling in the effects module, and
// this reads as a physical key in a way a flat chip does not.
Item {
    id: root

    property string text: ""
    property bool modifier: false

    readonly property color face: root.modifier ? Theme.surface : Theme.beige
    readonly property color side: root.modifier ? Theme.bg : Theme.accentQuiet
    readonly property color ink: Theme.readableOn(root.face)

    readonly property int lift: Theme.px(3)

    implicitWidth: Math.max(label.implicitWidth + Theme.px(18), Theme.px(38))
    implicitHeight: label.implicitHeight + Theme.px(16) + root.lift

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height - root.lift
        radius: Theme.px(8)
        color: root.side
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: parent.height - root.lift
        radius: Theme.px(8)
        color: root.face
        border.width: 1
        border.color: root.modifier ? Theme.accentQuiet : Theme.bg

        Text {
            id: label

            anchors.centerIn: parent
            text: root.text
            font.family: Theme.uiFont
            font.pixelSize: root.modifier ? Theme.px(13) : Theme.px(16)
            font.weight: Font.DemiBold
            color: root.ink
        }
    }
}
