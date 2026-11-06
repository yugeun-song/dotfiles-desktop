pragma Singleton
// QtQuick is not used here; see Paths.qml for why the import stays.
import QtQuick
import Quickshell
import Quickshell.Io

// Whether the control centre (modules/ControlCentre.qml) is up, on which
// screen, and which of its sections is open in place. Here, not in the
// panel: the power button sits on every bar, and sibling modules cannot
// reach each other's properties (Session.qml keeps the session dialog's
// state the same way).
Singleton {
    id: root

    property bool open: false
    // The screen whose bar was clicked; null opens it on the focused one.
    property var screen: null
    // "wifi", "bluetooth", "sound", "power" or "": one section at a time, as
    // GNOME's quick settings open one menu at a time (the user's reference,
    // 2026-11-04).
    property string expanded: ""

    function toggle(screen): void {
        if (root.open) {
            root.close();
            return;
        }
        if (!Surfaces.mayOpen("controls"))
            return;
        root.screen = screen ?? null;
        root.expanded = "";
        root.askProfiles();
        root.open = true;
    }

    // The section first: what it turned on (the Wi-Fi scan) is let go while
    // the panel is still there to let go of it.
    function close(): void {
        root.expanded = "";
        root.open = false;
    }

    function expand(section: string): void {
        root.expanded = root.expanded === section ? "" : section;
    }

    // Transient, one panel at a time (Surfaces.qml).
    onOpenChanged: Surfaces.report("controls", root.open)

    Connections {
        target: Surfaces

        function onShut(name) {
            if (name === "controls")
                root.close();
        }
    }

    // power-profiles-daemon. quickshell's PowerProfiles reads Balanced whether
    // or not anything answers on the bus, so the power mode is offered only
    // once powerprofilesctl has answered. Asked at the first opening, never at
    // login, and once: a daemon that is installed stays installed.
    property bool profilesAnswered: false
    property bool profilesAsked: false

    function askProfiles(): void {
        if (root.profilesAsked)
            return;
        root.profilesAsked = true;
        profiles.running = true;
    }

    Process {
        id: profiles

        command: ["powerprofilesctl", "get"]
        onExited: code => root.profilesAnswered = code === 0
    }

    // The Wi-Fi section's rows, from plain values ({ name, connected, known,
    // signal 0..1, secured }): the network in use, then those with a saved
    // connection, then the rest, each group strongest first. One row per
    // name, since a network on two bands can be listed twice; hidden networks
    // have no name to show and are left out. At most `most` rows.
    function networkOrder(list: var, most: int): var {
        const rank = n => n.connected ? 0 : n.known ? 1 : 2;
        const sorted = (list ?? []).filter(n => n && n.name)
            .slice()
            .sort((a, b) => rank(a) - rank(b) || b.signal - a.signal || a.name.localeCompare(b.name));
        const seen = new Set();
        const out = [];
        for (const n of sorted) {
            if (seen.has(n.name))
                continue;
            seen.add(n.name);
            out.push(n);
            if (out.length >= most)
                break;
        }
        return out;
    }

    // A signal of 0..1 as the font's four steps, the lock where a password is
    // asked. Glyphs by name from the font's cmap (Theme.controlWifi*).
    function wifiGlyph(signal: real, secured: bool): string {
        const step = signal >= 0.75 ? 3 : signal >= 0.5 ? 2 : signal >= 0.25 ? 1 : 0;
        return (secured ? Theme.controlWifiLockGlyphs : Theme.controlWifiGlyphs)[step];
    }
}
