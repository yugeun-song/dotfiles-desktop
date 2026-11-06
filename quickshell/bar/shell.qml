import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import "modules"
import qs.services

ShellRoot {
    id: shell

    // No reload on a file's write: install.sh writes file by file and reloads
    // once at the end (below). A reload per write met a half-copied tree and,
    // while reloads still restarted the key overlay's reader, asked for its
    // password once per write (2026-10-25).
    Component.onCompleted: Quickshell.watchFiles = false

    // One bar per screen, one of everything else: a second copy would register
    // the same global shortcut names twice.
    Variants {
        model: Quickshell.screens

        Bar {
            menuActions: shell.menuActions
        }
    }

    // What a right click on the bar runs (services/BarOptions.qml names the rows):
    // the panels are siblings a bar cannot reach. Lock and Sleep as the session
    // dialog's own rows do them, which say why they go the way they go.
    readonly property var menuActions: ({
        launcher: () => launcher.toggle(),
        controls: () => Controls.toggle(null),
        notifications: () => notificationCentre.toggle(),
        weather: () => Weather.togglePanel(Screens.focused),
        displays: () => displays.show(),
        wallpaper: () => wallpaperPicker.show(),
        widgetEdit: () => Widgets.toggleEditing(),
        widgetSettings: () => Widgets.toggleSettings(),
        island: () => Media.toggleIsland(),
        keyOverlay: () => KeyFeed.toggle(),
        cheatsheet: () => cheatsheet.toggle(),
        lock: () => powerMenu.run(powerMenu.entries.find(e => e.id === "lock")),
        sleep: () => powerMenu.run(powerMenu.entries.find(e => e.id === "suspend")),
        session: () => powerMenu.toggle()
    })

    // The lock screen swept up at the unlock, on each screen.
    Variants {
        model: Quickshell.screens

        UnlockSweep {
            required property ShellScreen modelData

            screen: modelData
        }
    }

    Launcher {
        id: launcher
    }

    PowerMenu {
        id: powerMenu
    }

    Cheatsheet {
        id: cheatsheet
    }

    Displays {
        id: displays
    }

    WallpaperPicker {
        id: wallpaperPicker
    }

    // The power button's panel; its buttons open the two panels above,
    // which it cannot reach itself.
    ControlCentre {
        id: controlCentre

        onDisplaysAsked: displays.show()
        onWallpaperAsked: wallpaperPicker.show()
    }

    WeatherPanel {
        id: weatherPanel
    }

    // The desktop widgets: windows only on a screen whose desktop is in view.
    WidgetDesk {}

    // A video wallpaper where wallpaper.sh linked one; nothing without it.
    VideoWallpaper {}

    // Inert until a display is given a time in the Displays panel, and held
    // off while that panel is open.
    ScreensaverDpms {
        paused: displays.open
    }

    // Instantiating these starts the notification daemon: a singleton is only
    // created on first reference, otherwise the bus name stays unowned.
    NotificationToasts {}

    NotificationCentre {
        id: notificationCentre
    }

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

    // Whether a program is linked to a screen's stream, for ScreenShare: a
    // share's frames pause while the screen holds still, Hyprland then says
    // its screencast stopped, and the share is over only once the link goes.
    // Read here so that ScreenShare's unit tests need no PipeWire. A screen's
    // stream is a video source no device backs, told from a camera as
    // scripts/share-apps.py tells it; device.id reads only once bound.
    readonly property var videoSources: Pipewire.linkGroups.values
        .map(g => g?.source)
        .filter(s => s && (s.type & PwNodeType.VideoSource) === PwNodeType.VideoSource && !s.isStream)

    PwObjectTracker {
        objects: shell.videoSources
    }

    Binding {
        target: ScreenShare
        property: "streamed"
        value: shell.videoSources.some(s => s.ready && s.properties["device.id"] === undefined)
    }

    // The island's event on the lock screen as well (services/LockIsland.qml):
    // a singleton exists only once something names it.
    readonly property bool lockIsland: LockIsland.active

    // Audio devices plugged in and pulled out: the default output and input
    // follow them (services/AudioPolicy.qml), and the island tells of the
    // wired ones.
    Connections {
        target: AudioDevices

        function onSettled(state) {
            Island.outputsSettle(state);
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
