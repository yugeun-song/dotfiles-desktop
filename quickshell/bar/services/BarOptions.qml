pragma Singleton
// QtQuick is not used here; see Paths.qml for why the import stays.
import QtQuick
import Quickshell

// What a right click on the bar offers (modules/BarMenu.qml; the user,
// 2026-11-06, after the menu bars they sent, opaque as this desktop's menus
// are): whatever the shell can open or switch, in groups with a rule between,
// a key at the right end of a row that has one. Plain values in and out, so
// that the rows are tested without a window (tests/unit/qml/shell.qml).
//
// A row's `what` is how keybinds.lua describes the same thing, so that the key
// shown is the live one (hyprctl binds), never a copy that drifts. No row runs
// anything by itself that cannot be taken back: what ends the session goes
// through the session dialog, whose name ends in dots for that.
Singleton {
    id: root

    readonly property var groups: [
        [
            { id: "launcher", label: "Applications", what: "Application launcher" },
            { id: "controls", label: "Control centre" },
            { id: "notifications", label: "Notifications", what: "Show the notification history" },
            { id: "weather", label: "Weather" }
        ],
        [
            { id: "displays", label: "Displays…", what: "Display settings" },
            { id: "mirror", label: "Tablet mirror…" },
            { id: "wallpaper", label: "Wallpaper…", what: "Pick the wallpaper" },
            { id: "appearance", label: "Appearance…", what: "Colours of the bar and panels" },
            { id: "widgetEdit", label: "Edit desktop widgets", what: "Edit the desktop widgets" },
            { id: "widgetSettings", label: "Desktop widget settings…", what: "Desktop widget settings" }
        ],
        [
            { id: "island", label: "Island", what: "Show or hide the island at the top", checkable: true },
            { id: "keyOverlay", label: "Key overlay", what: "Show the keys being pressed", checkable: true },
            { id: "cheatsheet", label: "Key bindings…", what: "Show every key binding" }
        ],
        [
            { id: "lock", label: "Lock screen", what: "Lock" },
            { id: "sleep", label: "Sleep" },
            { id: "session", label: "Session…", what: "Session dialog" }
        ]
    ]

    // { description: its key } from `hyprctl -j binds`. A chord with a modifier
    // before a key of its own (Super+O before the laptop's display key), since
    // that is the one a keyboard without such keys has too.
    function keysOf(binds: var): var {
        const out = {};
        for (const bind of binds ?? []) {
            if (!bind || !bind.description)
                continue;
            const caps = Shortcuts.chord(bind.modmask || 0, bind.key || "").caps;
            if (caps.length === 0)
                continue;
            const text = caps.join("+");
            const had = out[bind.description];
            if (had === undefined || (had.indexOf("+") === -1 && text.indexOf("+") !== -1 && (bind.modmask || 0) !== 0))
                out[bind.description] = text;
        }
        return out;
    }

    // PopupMenu's entries. `run` holds a function for each row's id, `state` a
    // bool for each that can be on.
    function entries(keys: var, run: var, state: var): var {
        const out = [];
        root.groups.forEach((group, at) => {
            if (at > 0)
                out.push({ separator: true });
            group.forEach(row => {
                out.push({
                    label: row.label,
                    detail: row.what ? (keys[row.what] ?? "") : "",
                    checkable: row.checkable === true,
                    checked: row.checkable === true && state[row.id] === true,
                    action: () => {
                        const act = run[row.id];
                        if (typeof act === "function")
                            act();
                    }
                });
            });
        });
        return out;
    }
}
