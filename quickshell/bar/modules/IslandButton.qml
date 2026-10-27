import QtQuick
import qs.services

// A round button on the grown island (IslandActivities.qml), drawn as the
// user's references draw theirs (2026-10-26): a glyph on a disc of their grey
// or of the glyph's colour deepened (Theme.islandTint); the recorder's stop
// is theirs too, a red square in a white ring. Lit, with a hand, under the
// pointer, as everything a click acts on.
Item {
    id: root

    property string glyph: ""
    property color glyphColor: Theme.islandText
    property color fill: Theme.islandFillHigh
    // The recorder's stop instead of a glyph.
    property bool stop: false
    property bool usable: true

    signal clicked

    implicitWidth: Theme.islandButtonSize
    implicitHeight: Theme.islandButtonSize

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        visible: !root.stop
        color: area.containsMouse && root.usable ? Qt.lighter(root.fill, 1.35) : root.fill

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !root.stop
        text: root.glyph
        font.family: Theme.iconFont
        font.pixelSize: Math.round(root.height * 0.5)
        color: root.usable ? root.glyphColor : Theme.islandFillHigh
    }

    // The ring and the square in the reference's proportions (measured).
    Rectangle {
        anchors.fill: parent
        visible: root.stop
        radius: width / 2
        color: "transparent"
        border.width: Math.max(2, Math.round(root.width * 0.05))
        border.color: area.containsMouse ? Theme.islandText : Qt.rgba(1, 1, 1, 0.85)

        Rectangle {
            anchors.centerIn: parent
            width: Math.round(parent.width * 0.44)
            height: width
            radius: Math.max(1, Math.round(width * 0.08))
            color: Theme.islandRed
        }
    }

    MouseArea {
        id: area

        anchors.fill: parent
        enabled: root.usable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
