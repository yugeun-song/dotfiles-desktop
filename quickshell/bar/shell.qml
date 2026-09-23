import QtQuick
import Quickshell
import Quickshell.Hyprland
import "modules"
import qs.services

ShellRoot {
    // One bar per screen, one of everything else: a second copy would register
    // the same global shortcut names twice.
    Variants {
        model: Quickshell.screens

        Bar {}
    }

    Launcher {}

    PowerMenu {}

    Cheatsheet {}

    // Instantiating these starts the notification daemon: a singleton is only
    // created on first reference, otherwise the bus name stays unowned.
    NotificationToasts {}

    NotificationCentre {}

    // Inert until KeyFeed.enabled is toggled, since it reads input devices.
    KeyOverlay {}

    Osd {
        id: osd
    }

    // OSDs follow the services, not the keys, so outside changes show too.
    // Volume watches Pipewire; Brightness only reports its own writes.
    Connections {
        target: Brightness

        function onChanged() {
            osd.show(Brightness.percent, Theme.iconBrightness);
        }
    }

    Connections {
        target: Volume

        function onChanged() {
            osd.show(Volume.percent, Theme.volumeIcon(Volume.percent, Volume.muted));
        }
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
}
