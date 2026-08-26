import QtQuick
import qs.services

// One key press, drawn as a cap.
//
// Modifiers do not get caps of their own. Shift and D pressed together are one
// event, not two, and two caps side by side say the opposite: that something
// happened twice. The modifiers are drawn as their symbols, in front of the key
// and inside the same cap, which is the convention every keyboard shortcut in
// print has used for decades.
//
// The shape is two rectangles rather than one with a shadow. The lower one is
// the side of the key and the upper one its face, offset up by a few pixels.
// Qt Quick has no cheap drop shadow without the effects module, and this reads
// as a physical key in a way a flat chip does not.
Item {
    id: root

    // The modifier symbols, already assembled: "" or "⌃⇧".
    property string mods: ""
    property string text: ""

    readonly property color face: Theme.beige
    readonly property color side: Theme.accentQuiet
    readonly property color ink: Theme.readableOn(root.face)

    readonly property int lift: Theme.px(3)

    implicitWidth: Math.max(label.implicitWidth + Theme.px(20), Theme.px(42))
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
        border.color: Theme.bg

        Row {
            id: label

            anchors.centerIn: parent
            spacing: Theme.px(2)

            // Dimmer than the key it modifies, because it is the qualifier and
            // not the thing that happened. Same family, same size and the same
            // weight: opacity alone carries that difference, and letting the
            // weight carry it too made the symbol read as a different typeface
            // sitting next to the letter.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.mods !== ""
                text: root.mods
                font.family: Theme.uiFont
                font.pixelSize: Theme.px(17)
                font.weight: Font.DemiBold
                color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.55)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.text
                font.family: Theme.uiFont
                font.pixelSize: Theme.px(17)
                font.weight: Font.DemiBold
                color: root.ink
            }
        }
    }
}
