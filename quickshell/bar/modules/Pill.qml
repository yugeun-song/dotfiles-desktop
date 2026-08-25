import QtQuick
import Quickshell
import qs.services

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property color fill: Theme.muted
    property color textColor: Theme.ink
    property int horizontalPadding: Theme.pillPadding
    property string tooltip: ""
    property int iconPixelSize: Theme.iconSize
    property Component iconComponent: null
    property var menuEntries: []
    property var command: null

    signal activated

    implicitHeight: Theme.pillHeight
    implicitWidth: content.implicitWidth + root.horizontalPadding * 2
    radius: Theme.pillRadius
    color: root.fill

    HoverHandler {
        id: hover
    }

    Tooltip {
        anchorItem: root
        active: hover.hovered && !menu.open
        text: root.tooltip
    }

    PopupMenu {
        id: menu

        anchorItem: root
        entries: root.menuEntries
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: root.command !== null || root.menuEntries.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.menuEntries.length > 0) {
                menu.toggle();
                return;
            }
            root.activated();
            if (root.command !== null)
                Quickshell.execDetached(root.command);
        }
    }

    Row {
        id: content

        anchors.centerIn: parent
        spacing: Theme.pillGlyphGap

        Loader {
            anchors.verticalCenter: parent.verticalCenter
            active: root.iconComponent !== null
            visible: active
            sourceComponent: root.iconComponent
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.iconComponent === null && root.icon !== ""
            text: root.icon
            font.family: Theme.iconFont
            font.pixelSize: root.iconPixelSize
            color: root.textColor
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.label !== ""
            text: root.label
            font.family: Theme.uiFont
            font.pixelSize: Theme.textSize
            font.weight: Font.Medium
            color: root.textColor
        }
    }
}
