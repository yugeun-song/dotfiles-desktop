pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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
// would bury the 112 worth reading.
Scope {
    id: root

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

    // Hyprland reports the modifiers as a bitmask. These are the four that
    // appear on this machine; the mask is a sum, so 69 is SUPER+CTRL+SHIFT.
    readonly property var modNames: [
        { bit: 64, name: "Super" },
        { bit: 4,  name: "Ctrl"  },
        { bit: 8,  name: "Alt"   },
        { bit: 1,  name: "Shift" }
    ]

    function modLabel(mask) {
        const parts = [];
        for (const m of root.modNames)
            if (mask & m.bit)
                parts.push(m.name);
        return parts.length ? parts.join(" + ") : "No modifier";
    }

    // Longer combinations last, so the plain Super block a reader is most
    // likely to want is at the top rather than buried under the three-modifier
    // ones. Ties break on the mask so the order is stable between openings.
    function modRank(mask) {
        let bits = 0;
        for (const m of root.modNames)
            if (mask & m.bit)
                bits++;
        return bits * 1000 + mask;
    }

    // A key name as it is typed, not as X11 spells it.
    function keyLabel(bind) {
        const k = bind.key || "";
        const map = {
            "Return": "Enter", "slash": "/", "comma": ",", "period": ".",
            "semicolon": ";", "apostrophe": "'", "grave": "`", "minus": "-",
            "equal": "=", "bracketleft": "[", "bracketright": "]",
            "backslash": "\\", "Print": "PrtSc", "Escape": "Esc",
            "mouse_up": "Wheel up", "mouse_down": "Wheel down",
            "Page_Up": "PgUp", "Page_Down": "PgDn"
        };
        if (map[k] !== undefined)
            return map[k];
        // mouse:272 and friends read as nothing at all.
        if (k.startsWith("mouse:"))
            return "Mouse " + k.slice(6);
        return k.length === 1 ? k.toUpperCase() : k;
    }

    Process {
        id: binds

        command: ["hyprctl", "-j", "binds"]

        stdout: StdioCollector {
            onStreamFinished: {
                let parsed;
                try {
                    parsed = JSON.parse(this.text);
                } catch (e) {
                    // A shell that cannot read the bindings should say so once
                    // rather than open an empty window that looks like there
                    // are none.
                    console.warn("[cheatsheet] could not parse hyprctl binds:", e);
                    root.groups = [];
                    return;
                }

                const byMask = {};
                for (const b of parsed) {
                    if (!b.description)
                        continue;
                    const mask = b.modmask || 0;
                    if (byMask[mask] === undefined)
                        byMask[mask] = [];
                    byMask[mask].push({
                        keys: root.keyLabel(b),
                        what: b.description
                    });
                }

                const out = [];
                for (const mask of Object.keys(byMask)) {
                    const m = parseInt(mask);
                    byMask[mask].sort((a, b) => a.what.localeCompare(b.what));
                    out.push({
                        title: root.modLabel(m),
                        rank: root.modRank(m),
                        items: byMask[mask]
                    });
                }
                out.sort((a, b) => a.rank - b.rank);
                root.groups = out;
            }
        }
    }

    readonly property int total: {
        let n = 0;
        for (const g of root.groups)
            n += g.items.length;
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

            // The dim behind it, and the click target that closes it. A dialog
            // that can only be dismissed from the keyboard is a dialog someone
            // will fight with the mouse first.
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.72)

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape || event.key === Qt.Key_Slash) {
                    root.close();
                    event.accepted = true;
                }
            }
            Component.onCompleted: win.forceActiveFocus()

            Rectangle {
                id: card

                anchors.centerIn: parent
                width: Math.min(parent.width - Theme.px(80), Theme.px(1180))
                height: Math.min(parent.height - Theme.px(80), content.implicitHeight + Theme.px(56))
                radius: Theme.px(18)
                color: Theme.bgAlt
                border.width: 1
                border.color: Theme.accentQuiet

                // Clicks on the card must not reach the dimmer behind it, or
                // reading the sheet would close it.
                MouseArea {
                    anchors.fill: parent
                }

                ColumnLayout {
                    id: content

                    anchors.fill: parent
                    anchors.margins: Theme.px(28)
                    spacing: Theme.px(16)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(10)

                        Text {
                            text: "Key bindings"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(19)
                            font.weight: Font.DemiBold
                            color: Theme.fg
                        }

                        Item { Layout.fillWidth: true }

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

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: columns.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        // Three columns rather than one: 112 entries in a single
                        // list is a scroll, and the point of a cheatsheet is to
                        // be read at a glance.
                        RowLayout {
                            id: columns

                            width: parent.width
                            spacing: Theme.px(26)

                            Repeater {
                                model: 3

                                ColumnLayout {
                                    required property int index

                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    spacing: Theme.px(14)

                                    Repeater {
                                        model: root.groups.filter((g, i) => i % 3 === parent.index)

                                        ColumnLayout {
                                            required property var modelData

                                            Layout.fillWidth: true
                                            spacing: Theme.px(4)

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

                                                RowLayout {
                                                    required property var modelData

                                                    Layout.fillWidth: true
                                                    spacing: Theme.px(8)

                                                    Rectangle {
                                                        Layout.preferredWidth: Math.max(keyText.implicitWidth + Theme.px(12), Theme.px(52))
                                                        Layout.preferredHeight: keyText.implicitHeight + Theme.px(5)
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
                                                        Layout.fillWidth: true
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
