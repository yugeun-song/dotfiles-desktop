import QtQuick
import qs.services

// A label, a line under it, and the Displays panel's pill switch at the
// right (the knob at the lit end): the widgets' option panels.
Item {
    id: row

    required property string label
    property string detail: ""
    required property bool on

    signal toggled(bool on)

    width: parent?.width ?? 0
    height: Math.max(Theme.px(44), words.implicitHeight + Theme.px(16))

    Column {
        id: words

        anchors.left: parent.left
        anchors.right: pill.left
        anchors.rightMargin: Theme.px(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.px(2)

        Text {
            width: parent.width
            text: row.label
            font.family: Theme.uiFont
            font.pixelSize: Theme.px(14)
            color: Theme.fg
        }

        Text {
            width: parent.width
            visible: row.detail !== ""
            wrapMode: Text.WordWrap
            text: row.detail
            font.family: Theme.uiFont
            font.pixelSize: Theme.px(12)
            color: Theme.muted
        }
    }

    Rectangle {
        id: pill

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.px(46)
        height: Theme.px(24)
        radius: height / 2
        color: row.on ? Theme.accentIndigo : Theme.surfaceRaised

        Rectangle {
            width: parent.height - Theme.px(6)
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: row.on ? pill.width - width - Theme.px(3) : Theme.px(3)
            color: row.on ? Theme.ink : Theme.fg

            Behavior on x {
                NumberAnimation {
                    duration: 110
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: row.toggled(!row.on)
    }
}
