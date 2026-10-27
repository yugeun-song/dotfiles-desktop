pragma Singleton

// QtQuick is not used here; see Paths.qml for why the import stays.
import QtQuick
import Quickshell

// Whether the session dialog (modules/PowerMenu.qml) is up. Here, not in
// the dialog: the power key and the button on every bar open the same one
// dialog, and sibling modules cannot reach each other's properties.
Singleton {
    id: root

    property bool menuOpen: false

    function toggleMenu() {
        root.menuOpen = !root.menuOpen;
    }
}
