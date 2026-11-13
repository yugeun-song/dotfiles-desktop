pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.services

// The desktop widgets (services/Widgets.qml has their rules): one
// WidgetScreen per screen, the settings and a widget's options panels, and
// the keys. A screen's widgets tell tiled windows from floating ones by the
// windows' IPC objects, which quickshell reads only when asked: asked here
// once at the start and after each window event, a moment later, and only
// while there is a widget to hide.
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        WidgetScreen {
            required property ShellScreen modelData

            screen: modelData
        }
    }

    WidgetSettings {}

    WidgetOptions {}

    readonly property bool anyPlaced: Mirror.running || Widgets.layout.length > 0 || Object.keys(Widgets.screens).length > 0

    Component.onCompleted: {
        if (root.anyPlaced)
            Hyprland.refreshToplevels();
    }

    readonly property var windowEvents: ["openwindow", "closewindow", "changefloatingmode", "movewindowv2", "fullscreen"]

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (root.anyPlaced && !KeyFeed.desktopHidden && root.windowEvents.indexOf(event.name) !== -1)
                refresh.restart();
        }
    }

    // Not asked while the lock hides the desktop (the see-through lock does
    // not), so a window opened meanwhile has no IPC object yet and would read
    // as tiled, hiding the widgets until the next window event.
    Connections {
        target: KeyFeed

        function onDesktopHiddenChanged() {
            if (root.anyPlaced && !KeyFeed.desktopHidden)
                refresh.restart();
        }
    }

    Timer {
        id: refresh

        interval: 120
        onTriggered: Hyprland.refreshToplevels()
    }

    // What the keys and a click do, for scripts and the end-to-end tests:
    // qs ipc call widgets options <screen> <id>.
    IpcHandler {
        target: "widgets"

        function edit(): void {
            Widgets.toggleEditing();
        }

        function settings(): void {
            Widgets.toggleSettings();
        }

        function options(screen: string, id: string): void {
            Widgets.openOptions(screen, id);
        }

        function close(): void {
            Widgets.closeOptions();
            Widgets.settingsOpen = false;
            Widgets.editing = false;
        }
    }

    GlobalShortcut {
        name: "widgetEdit"
        description: "Edit the desktop widgets"
        onPressed: Widgets.toggleEditing()
    }

    GlobalShortcut {
        name: "widgetSettings"
        description: "Desktop widget settings"
        onPressed: Widgets.toggleSettings()
    }
}
