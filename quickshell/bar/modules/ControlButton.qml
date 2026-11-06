import QtQuick
import qs.services

// A round button of the control centre's top row, as GNOME's quick settings
// set theirs: a glyph alone on the raised face, each naming what it opens
// (a capture, the display panel, the lock, the session dialog).
Item {
    id: root

    property string icon: ""

    signal clicked

    implicitWidth: Theme.controlButtonSize
    implicitHeight: Theme.controlButtonSize

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: area.containsMouse ? Theme.surfaceRaisedHover : Theme.surfaceRaised

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
    }

    Text {
        anchors.centerIn: parent
        text: root.icon
        font.family: Theme.iconFont
        font.pixelSize: Theme.menuIconSize
        color: Theme.fg
    }

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
