pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// A label and a row of pills, the one kept lit: the tablet mirror's settings
// (MirrorPanel.qml). Choices: { label, value }.
Item {
    id: root

    required property string label
    required property var choices
    required property var value

    signal picked(var value)

    width: parent?.width ?? 0
    height: Math.max(Theme.px(44), pills.height + Theme.px(8))

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.family: Theme.uiFont
        font.pixelSize: Theme.px(14)
        color: Theme.fg
    }

    Row {
        id: pills

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.px(6)

        Repeater {
            model: root.choices

            PillButton {
                required property var modelData

                label: modelData.label
                primary: modelData.value === root.value
                onClicked: root.picked(modelData.value)
            }
        }
    }
}
