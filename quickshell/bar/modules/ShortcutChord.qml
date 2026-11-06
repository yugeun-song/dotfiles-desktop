pragma ComponentBehavior: Bound
import QtQuick
import qs.services

// One chord of the cheatsheet (modules/Cheatsheet.qml): its caps, then what
// is not a key ("tap", "Lid closed"). A file of its own, as ShortcutGroup.qml
// is: as two inline components of the sheet, one used inside the other, the
// bar refused the sheet ("Group is not a type", quickshell 0.3.2).
Row {
    id: chord

    required property var keys
    property string to: ""

    spacing: Theme.px(4)

    Repeater {
        model: chord.keys.caps

        // Caps are all one height, so a row needs no centring; the
        // Repeater's caps have no parent yet when they are made.
        KeyCap {
            required property string modelData

            size: Theme.shortcutCapSize
            text: modelData
        }
    }

    // A numbered action's last key: "1 – 0" across the number row.
    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: chord.to !== ""
        text: "–"
        font.family: Theme.uiFont
        font.pixelSize: Theme.menuItemTextSize
        color: Theme.muted
    }

    KeyCap {
        anchors.verticalCenter: parent.verticalCenter
        visible: chord.to !== ""
        size: Theme.shortcutCapSize
        text: chord.to
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: chord.keys.note !== ""
        text: chord.keys.note
        font.family: Theme.uiFont
        font.pixelSize: Theme.menuItemTextSize
        color: Theme.muted
    }
}
