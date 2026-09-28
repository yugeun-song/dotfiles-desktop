pragma Singleton

// QtQuick is not used here, but without the import quickshell 0.3.1 leaves
// this file out of the generated qs.services module (see Paths.qml).
import QtQuick
import Quickshell
import Quickshell.Hyprland

// The screen a summoned surface belongs on. quickshell's default pick for a
// window can be a disabled, parked output, so every overlay follows the
// compositor's focused monitor instead; one binding here rather than a copy
// in each of them. A property, not a function: a singleton's functions are
// not always callable when a window's first binding runs at start.
Singleton {
    id: root

    readonly property var focused: {
        const name = Hyprland.focusedMonitor?.name ?? "";
        const match = Quickshell.screens.find(s => s.name === name);
        return match ?? Quickshell.screens[0] ?? null;
    }
}
