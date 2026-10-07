pragma Singleton

// QtQuick is not used here, but without the import quickshell 0.3.1 leaves
// this file out of the generated qs.services module and every user sees
// "Paths is not defined".
import QtQuick
import Quickshell

// Where the Hyprland scripts live, resolved once. Three modules had their own
// copy of the XDG_CONFIG_HOME-or-HOME/.config rule and treated a missing HOME
// differently ("undefined/.config" in one of them).
Singleton {
    id: root

    readonly property string configHome: {
        const configured = Quickshell.env("XDG_CONFIG_HOME");
        if (configured)
            return configured;
        const home = Quickshell.env("HOME");
        return (home ? home : "") + "/.config";
    }

    readonly property string hyprScripts: root.configHome + "/hypr/scripts"

    // The bar's own state (the screensaver times, the key overlay switch):
    // what the user chose on this machine, so neither installed nor tracked.
    // bin/bar creates the directory, which quickshell cannot do.
    readonly property string stateDir: {
        const configured = Quickshell.env("XDG_STATE_HOME");
        if (configured)
            return configured + "/quickshell/bar";
        const home = Quickshell.env("HOME");
        return (home ? home : "") + "/.local/state/quickshell/bar";
    }
}
