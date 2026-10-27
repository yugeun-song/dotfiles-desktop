pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.services

// Applications running with no window on show (services/Tray.qml), between
// the workspaces and the focused app's name, as the user placed them; there
// only while one runs. A tray item opens its application on a click and its
// own menu, Exit or Quit among the entries, on a right click. A process found
// by name has no menu of its own: one with a desktop entry is opened by a
// click, which runs that entry, and gets Open and Quit on a right click; one
// with none, or one quitting, gets Quit on any click.
Row {
    id: root

    spacing: Theme.trayIconGap
    visible: Tray.items.length + Tray.running.length > 0

    Repeater {
        model: Tray.items

        delegate: Cell {
            id: sni

            required property var modelData

            source: sni.modelData.icon
            entries: Tray.menuEntries(opener.children?.values ?? [])

            onClicked: button => {
                if (button === Qt.LeftButton && !sni.modelData.onlyMenu)
                    sni.modelData.activate();
                else if (sni.modelData.hasMenu)
                    sni.toggleMenu();
            }

            // Bound for as long as the icon is there, not only while the menu
            // is open: PopupMenu closes before it runs an entry, and the entry
            // must still exist then.
            QsMenuOpener {
                id: opener

                menu: sni.modelData.hasMenu ? sni.modelData.menu : null
            }
        }
    }

    Repeater {
        model: Tray.running

        delegate: Cell {
            id: proc

            required property var modelData

            source: proc.modelData.icon
            entries: Tray.processEntries(proc.modelData)

            onClicked: button => {
                if (button === Qt.LeftButton && Tray.canOpen(proc.modelData))
                    Tray.open(proc.modelData.entry);
                else
                    proc.toggleMenu();
            }
        }
    }

    component Cell: Item {
        id: cell

        property string source: ""
        property var entries: []

        signal clicked(int button)

        function toggleMenu() {
            menu.toggle();
        }

        implicitWidth: Theme.trayIconSize + Theme.trayIconPad * 2
        implicitHeight: Theme.barHeight

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: Theme.barInset
            anchors.bottomMargin: Theme.barInset
            radius: Theme.menuItemRadius
            color: menu.open ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.20)
                             : hover.hovered ? Theme.menuHover : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: 90
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Read at three times its size: the bar is drawn scaled (FittedStage)
        // on a fractionally scaled output, and a texture made at the bar's
        // own size came out soft.
        Image {
            id: icon

            readonly property int texture: Theme.trayIconSize * 3

            anchors.centerIn: parent
            width: Theme.trayIconSize
            height: Theme.trayIconSize
            source: cell.source
            sourceSize.width: icon.texture
            sourceSize.height: icon.texture
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            asynchronous: true
            visible: icon.status === Image.Ready

            layer.enabled: Theme.trayIconSaturation !== 0
            layer.textureSize: Qt.size(icon.texture, icon.texture)
            layer.smooth: true
            layer.effect: MultiEffect {
                saturation: Theme.trayIconSaturation
            }
        }

        // An application that gives no icon, or one not found in the theme.
        Text {
            anchors.centerIn: parent
            height: Theme.barLineHeight
            verticalAlignment: Text.AlignVCenter
            visible: !icon.visible
            text: Theme.iconApps
            font.family: Theme.iconFont
            font.pixelSize: Theme.trayIconSize
            color: Theme.fg
        }

        HoverHandler {
            id: hover
        }

        PopupMenu {
            id: menu

            anchorItem: cell
            entries: cell.entries
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => cell.clicked(mouse.button)
        }
    }
}
