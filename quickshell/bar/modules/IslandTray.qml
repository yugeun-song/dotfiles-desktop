pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.services

// The tray: the StatusNotifierItem icons applications register.
//
// This bar has never had one. That was defensible while the bar was a row of
// readouts it owned -- a tray is a place other programs write into, and every
// item in it is drawn by whoever registered it -- but it also meant fcitx5's
// icon, and every application that only exposes itself through a tray icon,
// had nowhere to be. The island is the right place for it: a tray is something
// you go and look at, not something that should occupy the bar at all times.
//
// Left click activates, right click opens the item's own menu. Both are what
// the protocol says and what every other tray does; an item that provides only
// a menu (onlyMenu) gets the menu on a left click too, because for those there
// is nothing else a click could mean.
Item {
    id: root

    // display() takes a window, not an item: the menu it opens is a surface of
    // its own and needs something to be positioned against. Passed down from
    // Island rather than looked up, because there is exactly one island window
    // and nothing here should be guessing which surface it is inside.
    property var parentWindow: null

    readonly property var items: SystemTray.items?.values ?? []

    Flow {
        anchors.centerIn: parent
        width: parent.width
        spacing: Theme.px(10)
        visible: root.items.length > 0

        Repeater {
            model: root.items

            Item {
                id: entry

                required property var modelData

                implicitWidth: Theme.px(30)
                implicitHeight: Theme.px(30)

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.px(7)
                    color: entryHover.hovered ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: 90
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Image {
                    anchors.centerIn: parent
                    width: Theme.px(18)
                    height: Theme.px(18)
                    // The icon comes from the application, by whatever route
                    // it chose: a theme name, a path, or pixels over the bus.
                    // Quickshell resolves all three into this one property.
                    source: entry.modelData.icon
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                }

                HoverHandler {
                    id: entryHover
                }

                Tooltip {
                    anchorItem: entry
                    active: entryHover.hovered
                    text: {
                        const lines = [];
                        const title = entry.modelData.tooltipTitle || entry.modelData.title || entry.modelData.id;
                        if (title)
                            lines.push(Theme.shorten(title, 40));
                        const body = entry.modelData.tooltipDescription ?? "";
                        if (body !== "")
                            lines.push(Theme.shorten(body, 60));
                        lines.push(entry.modelData.onlyMenu ? "Click for its menu" : "Click to activate, right click for its menu");
                        return lines.join("\n");
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton && !entry.modelData.onlyMenu) {
                            entry.modelData.activate();
                            return;
                        }
                        if (!entry.modelData.hasMenu || !root.parentWindow)
                            return;
                        // Positioned under this icon, in the island window's
                        // coordinates: display() measures from the window it
                        // is given, not from the item that was clicked.
                        const at = entry.mapToItem(null, entry.width / 2, entry.height);
                        entry.modelData.display(root.parentWindow, Math.round(at.x), Math.round(at.y));
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.items.length === 0
        text: "No tray items"
        font.family: Theme.uiFont
        font.pixelSize: Theme.islandSubSize
        color: Qt.rgba(1, 1, 1, 0.40)
    }
}
