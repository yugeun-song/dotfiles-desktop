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
// The shadow is a second rectangle offset down and to the right, not a blur.
// Qt Quick has no cheap drop shadow without the effects module, and a hard
// offset reads as a card lifted off the screen in a way a soft one does not at
// this size. It takes the palette's yellow rather than a darker shade of the
// face: against a dark desktop a dark shadow disappears into it, and the point
// of the offset is that the edge is visible.
Item {
    id: root

    // The modifier symbols, already assembled: "" or "\u2303\u21E7".
    property string mods: ""
    property string text: ""

    // Set when the glyph came from the icon font rather than from Inter.
    property bool iconGlyph: false

    readonly property color face: Theme.beige
    readonly property color shadow: Theme.yellow
    readonly property color ink: Theme.readableOn(root.face)

    // How far the shadow sits behind the face, on both axes.
    readonly property int drop: Theme.px(5)

    implicitWidth: Math.max(label.implicitWidth + Theme.px(20), Theme.px(42)) + root.drop
    implicitHeight: label.implicitHeight + Theme.px(16) + root.drop

    Rectangle {
        x: root.drop
        y: root.drop
        width: parent.width - root.drop
        height: parent.height - root.drop
        radius: Theme.px(8)
        color: root.shadow
    }

    Rectangle {
        width: parent.width - root.drop
        height: parent.height - root.drop
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
                font.family: root.iconGlyph ? Theme.iconFont : Theme.uiFont
                // Nerd Font glyphs sit well inside their em box, so asking for
                // the same number gives a smaller drawing than Inter does.
                font.pixelSize: root.iconGlyph ? Theme.px(20) : Theme.px(17)
                font.weight: Font.DemiBold
                color: root.ink
            }
        }
    }
}
