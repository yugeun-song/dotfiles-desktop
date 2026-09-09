import QtQuick
import Quickshell
import Quickshell.Hyprland
import "modules"
import qs.services

ShellRoot {
    // One bar per screen, and exactly one of everything else. The overlays
    // register global shortcuts, which Hyprland binds by name; a second copy
    // would register the same name twice.
    Variants {
        model: Quickshell.screens

        Bar {}
    }

    Launcher {}

    PowerMenu {}

    Cheatsheet {}

    // These two are what start the notification daemon. A QML singleton is
    // created on first reference, so with nothing instantiating them the
    // NotificationServer inside Notifications never runs and the bus name stays
    // unowned -- which is exactly the state this machine was in.
    NotificationToasts {}

    NotificationCentre {}

    // Off until asked for. See Keys.enabled: a visualiser nobody switched on
    // is a keylogger, and this one holds device descriptors to do it.
    KeyOverlay {}

    Osd {
        id: osd
    }

    // Both readouts are driven by their service rather than by the key, so a
    // change made anywhere else still shows. Wiring them the other way round
    // would mean the OSD only appears when this shell owns the key.
    //
    // That holds for volume, which watches Pipewire. Brightness has nothing
    // watching the backlight device, so it still only reports its own writes.
    Connections {
        target: Brightness

        function onChanged() {
            osd.show(Brightness.percent, Theme.iconBrightness, Theme.accentAmber);
        }
    }

    Connections {
        target: Volume

        function onChanged() {
            osd.show(Volume.percent,
                     Theme.volumeIcon(Volume.percent, Volume.muted),
                     Volume.muted ? Theme.muted : Theme.accentTeal);
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
