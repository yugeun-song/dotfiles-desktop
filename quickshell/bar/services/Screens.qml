pragma Singleton

// QtQuick is not used here, but without the import quickshell 0.3.1 leaves
// this file out of the generated qs.services module (see Paths.qml).
import QtQuick
import Quickshell
import Quickshell.Hyprland

// The screen a surface belongs on, in one place for every overlay. Two
// answers, since Hyprland keeps two kinds of focus apart: the focused monitor
// follows the pointer onto another screen, while the keyboard stays with its
// window until a window there takes it. Properties, not functions: a
// singleton's functions are not always callable at a window's first binding.
Singleton {
    id: root

    // The compositor's focused monitor, where summoned surfaces open.
    // quickshell's default pick for a window can be a disabled, parked
    // output, so every overlay names a screen instead.
    readonly property var focused: {
        const name = Hyprland.focusedMonitor?.name ?? "";
        const match = Quickshell.screens.find(s => s.name === name);
        return match ?? Quickshell.screens[0] ?? null;
    }

    // What the events below have said, kept across reloads: a reset lost the
    // focused window until focus next moved.
    PersistentProperties {
        id: focus

        reloadableId: "screensFocus"

        property bool windowFocused: true
        property bool eventSeen: false
        property int panelsOpen: 0
    }

    // The window taking the keys, or null. quickshell 0.3.1 drops the empty
    // activewindowv2 that Hyprland sends when focus goes to nothing, so
    // activeToplevel keeps the last window; the event is caught here. Until
    // the first event, the last active window stands in while its workspace
    // is on screen: activeToplevel after a reload, and after a start (where
    // quickshell leaves it null) the client Hyprland lists as focused last.
    readonly property var focusedWindow: {
        if (focus.eventSeen)
            return focus.windowFocused ? Hyprland.activeToplevel : null;
        const last = Hyprland.activeToplevel
                     ?? (Hyprland.toplevels?.values ?? []).find(t => t.lastIpcObject?.focusHistoryID === 0)
                     ?? null;
        return last?.workspace?.active ? last : null;
    }

    // The screen holding the focused window, else the focused monitor. The
    // bars mark it as the screen in use.
    readonly property var windowScreen: {
        const name = root.focusedWindow?.monitor?.name ?? "";
        const match = name !== "" ? Quickshell.screens.find(s => s.name === name) : null;
        return match ?? root.focused;
    }

    // The shell's panels that take the keyboard while open, by their
    // WlrLayershell.namespace (a new such panel belongs here). They open on
    // the focused monitor, so while one is up the keys go there. Counted from
    // Hyprland's layer events: Qt's application state stayed active after the
    // launcher had closed (nested session).
    readonly property var keyboardPanels: ["quickshell:launcher", "quickshell:powermenu",
        "quickshell:notification-centre", "quickshell:cheatsheet", "quickshell:displays"]

    // The screen the keys go to.
    readonly property var keyboard: focus.panelsOpen > 0 ? root.focused : root.windowScreen

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            switch (event.name) {
            case "activewindowv2":
                focus.eventSeen = true;
                focus.windowFocused = event.data !== "";
                break;
            // A panel that changes screen is closed and reopened, so the count
            // holds through the move.
            case "openlayer":
                if (root.keyboardPanels.indexOf(event.data) !== -1)
                    focus.panelsOpen += 1;
                break;
            case "closelayer":
                if (root.keyboardPanels.indexOf(event.data) !== -1)
                    focus.panelsOpen = Math.max(0, focus.panelsOpen - 1);
                break;
            // quickshell 0.3.1 puts a workspacev2 on whichever monitor it last
            // saw focused. Switching workspace with the pointer on the other
            // screen, Hyprland sends that screen's focusedmon first, so the
            // panel's bar marked the external's workspace (nested session).
            // Rereading the monitors puts every workspace back on its screen
            // within milliseconds, before the misplaced mark visibly moves.
            case "workspacev2":
                Hyprland.refreshMonitors();
                break;
            }
        }
    }
}
