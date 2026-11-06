import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// The bar's own menu, on a right click anywhere the bar's parts do not take it
// themselves (the tray's icons have their applications' menus); services/
// BarOptions.qml says what it offers. First among the bar's parts, so that it lies
// under them all, and it takes the right button alone. It hangs under the pointer.
//
// The keys are read as it opens, as the cheatsheet reads them, and it opens once
// they are there, so that it does not widen under the pointer; nothing runs while
// it is shut.
Item {
    id: root

    // shell.qml's: a panel is a sibling a bar cannot reach.
    property var actions: ({})
    property var keys: ({})
    property bool asked: false

    function show(): void {
        if (!root.asked)
            return;
        root.asked = false;
        menu.toggle();
    }

    anchors.fill: parent

    Item {
        id: place

        width: 1
        height: parent.height
    }

    PopupMenu {
        id: menu

        anchorItem: place
        entries: BarOptions.entries(root.keys, root.actions, { island: Media.islandOn, keyOverlay: KeyFeed.enabled })
    }

    Process {
        id: binds

        command: ["hyprctl", "-j", "binds"]
        onRunningChanged: {
            if (!binds.running)
                root.show();
        }

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.keys = BarOptions.keysOf(JSON.parse(this.text));
                } catch (e) {
                    console.warn("[bar menu] could not read the key bindings:", e);
                }
                root.show();
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: mouse => {
            place.x = mouse.x;
            root.asked = true;
            binds.running = true;
        }
    }
}
