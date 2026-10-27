import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "modules"
import qs.services

ShellRoot {
    // No reload on a file's write: install.sh writes file by file and reloads
    // once at the end (below). A reload per write met a half-copied tree and,
    // while reloads still restarted the key overlay's reader, asked for its
    // password once per write (2026-10-25).
    Component.onCompleted: Quickshell.watchFiles = false

    // One bar per screen, one of everything else: a second copy would register
    // the same global shortcut names twice.
    Variants {
        model: Quickshell.screens

        Bar {}
    }

    // The lock screen swept up at the unlock, on each screen.
    Variants {
        model: Quickshell.screens

        UnlockSweep {
            required property ShellScreen modelData

            screen: modelData
        }
    }

    Launcher {}

    PowerMenu {}

    Cheatsheet {}

    Displays {
        id: displays
    }

    WeatherPanel {
        id: weatherPanel
    }

    // Inert until a display is given a time in the Displays panel, and held
    // off while that panel is open.
    ScreensaverDpms {
        paused: displays.open
    }

    // Instantiating these starts the notification daemon: a singleton is only
    // created on first reference, otherwise the bus name stays unowned.
    NotificationToasts {}

    NotificationCentre {}

    // Inert until Super+Y switches it on, since it reads input devices; its
    // reader then outlives reloads and restarts (services/KeyFeed.qml).
    KeyOverlay {}

    // Volume and brightness show on the island (services/Island.qml) as the
    // services change, not the keys, so outside changes show too. Volume
    // watches Pipewire; Brightness reports only its own writes.
    Connections {
        target: Brightness

        function onChanged() {
            Island.brightnessChanged();
        }
    }

    Connections {
        target: Volume

        function onChanged() {
            Island.volumeChanged();
        }
    }

    // Here, not in the bar: one per screen would register the name twice.
    GlobalShortcut {
        name: "island"
        description: "Show or hide the island at the top"

        onPressed: Media.toggleIsland()
    }

    GlobalShortcut {
        name: "brightnessUp"
        description: "Screen brightness up"

        onPressed: Brightness.step(5)
    }

    GlobalShortcut {
        name: "brightnessDown"
        description: "Screen brightness down"

        onPressed: Brightness.step(-5)
    }

    // install.sh asks for this once every file is in place, the only reload
    // with the watch off: reloads on write had missed files (install.sh),
    // and modules changed with a singleton met the old singleton. Deferred
    // so the call returns before the shell it runs in is replaced.
    IpcHandler {
        target: "shell"

        function reload(): void {
            Qt.callLater(() => Quickshell.reload(false));
        }
    }
}
