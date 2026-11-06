import QtQuick
import qs.services

// The tablet mirror on the desktop while it runs (Widgets.drawnFor), in WidgetCard's
// reference pixels: the tablet's glyph and where it stands. A click opens the panel,
// its own control (WidgetCard), as the weather's does. While it is drawn the service
// asks after the mirror, and that is how it leaves once the mirror's window has
// closed; it holds nothing when its window goes (Mirror.watchers).
Item {
    id: root

    required property string size
    required property var options

    readonly property bool wide: root.size !== "small"

    Component.onCompleted: Mirror.watchers += 1
    Component.onDestruction: Mirror.watchers -= 1

    Text {
        x: Theme.widgetPad
        y: Theme.widgetPad
        text: Theme.iconTablet
        font.family: Theme.iconFont
        font.pixelSize: 54
        color: Mirror.state === "running" ? Theme.accentGreen : Mirror.state === "ready" ? Theme.fg : Theme.muted
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.widgetPad
        spacing: 4

        Text {
            width: parent.width
            elide: Text.ElideRight
            text: "Tablet"
            font.family: Theme.uiFont
            font.pixelSize: 15
            color: Theme.muted
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            text: Mirror.title(Mirror.state)
            font.family: Theme.uiFont
            font.pixelSize: 26
            font.weight: Font.Medium
            color: Theme.fg
        }

        Text {
            width: parent.width
            visible: root.wide
            elide: Text.ElideRight
            // A device's name and scrcpy's words: never markup.
            textFormat: Text.PlainText
            text: Mirror.hint(Mirror.state, Mirror.error, Mirror.name)
            font.family: Theme.uiFont
            font.pixelSize: 15
            color: Theme.muted
        }
    }
}
