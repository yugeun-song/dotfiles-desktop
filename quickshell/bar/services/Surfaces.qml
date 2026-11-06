pragma Singleton
// QtQuick is not used here; see Paths.qml for why the import stays.
import QtQuick
import Quickshell

// Which of the shell's panels may stand together, each as its kind does on
// the two desktops the user named (the user, 2026-11-04: each its own way,
// not one rule for all six):
//   session, the session dialog: a system modal, as an end-session dialog
//     is. Opening it shuts every other panel, and nothing opens over it.
//   displays: a settings window, as a system settings app's display page
//     is. What opens after it stands over it and takes the keys, and they
//     come back when that shuts; only the session dialog shuts it, and a
//     change not yet kept still reverts at its deadline.
//   widgetEditor, the widgets' edit mode: a window as displays is, so its
//     settings can open over it and give it the keys back.
//   launcher, controls, notifications, weather, cheatsheet, wallpaper,
//   widgetSettings, widgetOptions: transient, as a menu bar's menus and a
//     search overlay are: one at a time, each opening shuts whichever of
//     them was up.
// One holder of the keyboard at a time, the newest panel: two exclusive
// layers on one screen take the keys from each other.
Singleton {
    id: root

    // Open panels by name, oldest first.
    property var shown: []
    readonly property string top: root.shown.length > 0 ? root.shown[root.shown.length - 1] : ""
    readonly property bool modal: root.shown.indexOf("session") !== -1

    // Asks the panel named to close.
    signal shut(string name)

    // Asked before a panel opens.
    function mayOpen(name: string): bool {
        return name === "session" || !root.modal;
    }

    // Told as a panel opens or closes.
    function report(name: string, open: bool): void {
        const rest = root.shown.filter(n => n !== name);
        if (!open) {
            root.shown = rest;
            return;
        }
        root.shown = rest.concat([name]);
        for (const other of rest) {
            if (name === "session" || (other !== "displays" && other !== "widgetEditor"))
                root.shut(other);
        }
    }
}
