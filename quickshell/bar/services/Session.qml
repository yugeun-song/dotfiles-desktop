pragma Singleton

// QtQuick is not used here; see Paths.qml for why the import stays.
import QtQuick
import Quickshell

// Whether the session dialog (modules/PowerMenu.qml) is up. Here, not in
// the dialog: the keys and the control centre's button open the same one
// dialog, and sibling modules cannot reach each other's properties.
Singleton {
    id: root

    property bool menuOpen: false

    function toggleMenu() {
        root.menuOpen = !root.menuOpen;
    }

    // The system modal: it shuts every other panel (Surfaces.qml).
    onMenuOpenChanged: Surfaces.report("session", root.menuOpen)
}
