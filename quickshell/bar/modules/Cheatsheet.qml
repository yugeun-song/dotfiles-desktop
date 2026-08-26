pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import qs.services

// Every key binding, read from the compositor rather than written down here.
//
// The obvious way to build this is a list in the file, which is wrong for the
// same reason a second copy of anything is wrong: it is right on the day it is
// written and drifts every time a binding changes, and nothing reports the
// drift. `hyprctl binds` already knows, because hypr/config/keybinds.lua gives
// almost every bind a description and Hyprland keeps it. So this asks.
//
// It follows that a binding with no description does not appear. That is the
// intended behaviour and not an omission to work around: the ones without a
// description are the duplicate wheel and arrow-key variants of bindings that
// are already listed under their primary key, and printing all 156 of them
// would bury the 113 worth reading.
Scope {
    id: root

    readonly property int columnCount: 3

    property bool open: false

    function toggle() {
        if (!root.open)
            binds.running = true;   // reread on every open; bindings can change
        root.open = !root.open;
    }

    function close() {
        root.open = false;
    }

    // ---- reading the bindings -------------------------------------------

    property var groups: []

    // Hyprland reports the modifiers as a bitmask. The mask is a sum, so 69 is
    // SUPER+CTRL+SHIFT.
    readonly property var modNames: [
        { bit: 64, name: "Super" },
        { bit: 4,  name: "Ctrl"  },
        { bit: 8,  name: "Alt"   },
        { bit: 1,  name: "Shift" }
    ]

    function modLabel(mask) {
        const parts = [];
        for (let i = 0; i < root.modNames.length; i++)
            if (mask & root.modNames[i].bit)
                parts.push(root.modNames[i].name);
        return parts.length ? parts.join(" + ") : "No modifier";
    }

    // Fewer modifiers first, so the plain Super block a reader is most likely
    // to want is at the top rather than under the three-modifier ones. Ties
    // break on the mask so the order is the same every time it opens.
    function modRank(mask) {
        let bits = 0;
        for (let i = 0; i < root.modNames.length; i++)
            if (mask & root.modNames[i].bit)
                bits++;
        return bits * 1000 + mask;
    }

    // A key name as it is typed, not as X11 spells it.
    function keyLabel(k) {
        const map = {
            "Return": "Enter", "slash": "/", "comma": ",", "period": ".",
            "semicolon": ";", "apostrophe": "'", "grave": "`", "minus": "-",
            "equal": "=", "bracketleft": "[", "bracketright": "]",
            "backslash": "\\", "Print": "PrtSc", "Escape": "Esc",
            "mouse_up": "Wheel up", "mouse_down": "Wheel down",
            "Page_Up": "PgUp", "Page_Down": "PgDn", "space": "Space"
        };
        if (map[k] !== undefined)
            return map[k];
        if (k.indexOf("mouse:") === 0)
            return "Mouse " + k.slice(6);
        // The media and laptop function keys arrive as their X11 names, which
        // are long enough to push the description off the row and tell a reader
        // nothing they did not already know from the key's printed icon.
        if (k.indexOf("XF86") === 0) {
            const t = k.slice(4)
                .replace("MonBrightness", "Brightness ")
                .replace("Audio", "")
                .replace(/([a-z])([A-Z])/g, "$1 $2");
            return t.charAt(0).toUpperCase() + t.slice(1);
        }
        if (k.indexOf("switch:") === 0)
            return k.indexOf("switch:on:") === 0 ? "Lid closed" : "Lid opened";
        if (k === "SUPER_L" || k === "SUPER_R")
            return k === "SUPER_L" ? "Super (left)" : "Super (right)";
        return k.length === 1 ? k.toUpperCase() : k;
    }

    Process {
        id: binds

        command: ["hyprctl", "-j", "binds"]

        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = [];
                try {
                    parsed = JSON.parse(this.text);
                } catch (e) {
                    // Say so once rather than open an empty window that looks
                    // like there are no bindings at all.
                    console.warn("[cheatsheet] could not parse hyprctl binds:", e);
                    root.groups = [];
                    return;
                }

                const byMask = {};
                for (let i = 0; i < parsed.length; i++) {
                    const b = parsed[i];
                    if (!b.description)
                        continue;
                    const mask = b.modmask || 0;
                    if (byMask[mask] === undefined)
                        byMask[mask] = [];
                    byMask[mask].push({
                        keys: root.keyLabel(b.key || ""),
                        what: b.description
                    });
                }

                const flat = [];
                const masks = Object.keys(byMask);
                for (let i = 0; i < masks.length; i++) {
                    const m = parseInt(masks[i]);
                    byMask[masks[i]].sort((a, b) => a.what.localeCompare(b.what));
                    flat.push({
                        title: root.modLabel(m),
                        rank: root.modRank(m),
                        items: byMask[masks[i]]
                    });
                }
                flat.sort((a, b) => a.rank - b.rank);

                // Split into columns here rather than in a binding, because a
                // Repeater nested inside a Repeater cannot see the outer index
                // reliably and quietly renders nothing when it cannot.
                const cols = [];
                for (let c = 0; c < root.columnCount; c++)
                    cols.push([]);
                for (let i = 0; i < flat.length; i++)
                    cols[i % root.columnCount].push(flat[i]);
                root.groups = cols;
            }
        }
    }

    readonly property int total: {
        let n = 0;
        for (let c = 0; c < root.groups.length; c++)
            for (let g = 0; g < root.groups[c].length; g++)
                n += root.groups[c][g].items.length;
        return n;
    }

    GlobalShortcut {
        name: "cheatsheet"
        description: "Show every key binding"

        onPressed: root.toggle()
    }

    // ---- the window ------------------------------------------------------

    LazyLoader {
        active: root.open

        PanelWindow {
            id: win

            color: "transparent"
            focusable: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:cheatsheet"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Keys go to an item inside the window, not to the window. A
            // PanelWindow does not take focus itself, so a Keys handler on it
            // is never reached and Escape does nothing.
            Item {
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape
                        || event.key === Qt.Key_Slash
                        || event.key === Qt.Key_Q) {
                        root.close();
                        event.accepted = true;
                    }
                }

                // The dim behind the card, and the click target that closes it.
                // A dialog dismissable only from the keyboard is one someone
                // will fight with the mouse first.
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.78)

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.close()
                    }
                }

                Rectangle {
                    id: card

                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.px(72), Theme.px(1220))
                    height: Math.min(parent.height - Theme.px(72), Theme.px(760))
                    radius: Theme.px(18)
                    color: Theme.bgAlt
                    border.width: 1
                    border.color: Theme.accentQuiet

                    // Clicks on the card must not reach the dimmer behind it,
                    // or reading the sheet would close it.
                    MouseArea {
                        anchors.fill: parent
                    }

                    Item {
                        id: header

                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: Theme.px(24)
                        height: title.implicitHeight

                        Text {
                            id: title

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Key bindings"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(19)
                            font.weight: Font.DemiBold
                            color: Theme.fg
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.px(14)

                            Text {
                                text: root.total + " bound"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.textSize
                                color: Theme.muted
                            }

                            Text {
                                text: "Esc to close"
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.textSize
                                color: Theme.accentQuiet
                            }
                        }
                    }

                    Flickable {
                        anchors.top: header.bottom
                        anchors.topMargin: Theme.px(16)
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: Theme.px(24)
                        anchors.rightMargin: Theme.px(24)
                        anchors.bottomMargin: Theme.px(20)

                        contentHeight: columns.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        // Three columns, because 113 entries in one list is a
                        // scroll and a cheatsheet that has to be scrolled is a
                        // worse manual.
                        Row {
                            id: columns

                            width: parent.width
                            spacing: Theme.px(24)

                            Repeater {
                                model: root.groups

                                Column {
                                    required property var modelData

                                    width: (columns.width - Theme.px(24) * (root.columnCount - 1)) / root.columnCount
                                    spacing: Theme.px(13)

                                    Repeater {
                                        model: parent.modelData

                                        Column {
                                            required property var modelData

                                            width: parent.width
                                            spacing: Theme.px(3)

                                            Text {
                                                text: modelData.title
                                                font.family: Theme.uiFont
                                                font.pixelSize: Theme.textSize
                                                font.weight: Font.DemiBold
                                                color: Theme.accentTeal
                                                bottomPadding: Theme.px(2)
                                            }

                                            Repeater {
                                                model: modelData.items

                                                Row {
                                                    required property var modelData

                                                    width: parent.width
                                                    spacing: Theme.px(8)

                                                    Rectangle {
                                                        width: Math.max(keyText.implicitWidth + Theme.px(12), Theme.px(54))
                                                        height: keyText.implicitHeight + Theme.px(5)
                                                        radius: Theme.px(5)
                                                        color: Theme.bg
                                                        border.width: 1
                                                        border.color: Theme.accentQuiet

                                                        Text {
                                                            id: keyText

                                                            anchors.centerIn: parent
                                                            text: modelData.keys
                                                            font.family: Theme.uiFont
                                                            font.pixelSize: Theme.px(12)
                                                            color: Theme.beige
                                                        }
                                                    }

                                                    Text {
                                                        width: parent.width - Math.max(keyText.implicitWidth + Theme.px(12), Theme.px(54)) - Theme.px(8)
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: modelData.what
                                                        font.family: Theme.uiFont
                                                        font.pixelSize: Theme.px(12)
                                                        color: Theme.fg
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
