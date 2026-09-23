pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import qs.services

// Key bindings read live from `hyprctl -j binds`, so the sheet never drifts
// from hypr/config/keybinds.lua. Binds without a description are left out on
// purpose. Flat table, one full chord per row.
Scope {
    id: root

    // Three columns leave too little room for chord plus description.
    readonly property int columnCount: 2

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

    property var columns: []
    property int total: 0


    // Hyprland modmask bits; 69 = Super+Ctrl+Shift.
    readonly property var modNames: [
        { bit: 64, name: "Super" },
        { bit: 4,  name: "Ctrl"  },
        { bit: 8,  name: "Alt"   },
        { bit: 1,  name: "Shift" }
    ]

    // Fewer modifiers first; ties break on the mask for a stable order.
    function modRank(mask) {
        let bits = 0;
        for (let i = 0; i < root.modNames.length; i++)
            if (mask & root.modNames[i].bit)
                bits++;
        return bits * 1000 + mask;
    }

    // Modifier names as words, not the key overlay's symbols: this page is
    // for readers who do not know the bindings yet.
    function chordLabel(mask, key) {
        const parts = [];
        for (let i = 0; i < root.modNames.length; i++)
            if (mask & root.modNames[i].bit)
                parts.push(root.modNames[i].name);
        parts.push(root.keyLabel(key));
        return parts.join(" + ");
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
        // Shorten XF86 keysyms so they do not push the description off the row.
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
                    console.warn("[cheatsheet] could not parse hyprctl binds:", e);
                    root.columns = [];
                    root.total = 0;
                    return;
                }

                const rows = [];
                for (let i = 0; i < parsed.length; i++) {
                    const b = parsed[i];
                    if (!b.description)
                        continue;
                    const mask = b.modmask || 0;
                    rows.push({
                        rank: root.modRank(mask),
                        chord: root.chordLabel(mask, b.key || ""),
                        what: b.description
                    });
                }

                rows.sort((a, b) => a.rank - b.rank || a.what.localeCompare(b.what));

                // Contiguous halves so the table reads down each column. Split
                // here, not in a binding: a nested Repeater cannot see the outer
                // index reliably and then renders nothing.
                const per = Math.ceil(rows.length / root.columnCount);
                const cols = [];
                for (let c = 0; c < root.columnCount; c++)
                    cols.push(rows.slice(c * per, (c + 1) * per));

                root.total = rows.length;
                root.columns = cols;
            }
        }
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

            // Exclusive zone 0 would place this clear of the bar's zone and
            // shift the centred card; Ignore covers the whole output.
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:cheatsheet"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // A PanelWindow never takes focus itself; Keys must live on a child.
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

                // Dim backdrop; clicking it closes the sheet.
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.82)

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.close()
                    }
                }

                Rectangle {
                    id: card

                    // Uniform so the alternating stripes stay equal.
                    readonly property int rowHeight: Theme.px(34)
                    readonly property int gutter: Theme.px(26)

                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.px(64), Theme.px(1560))
                    height: Math.min(parent.height - Theme.px(64), Theme.px(960))
                    radius: Theme.px(18)
                    color: Theme.surfaceBg
                    border.width: 1
                    border.color: Theme.surfaceLine

                    // Swallow clicks so they do not reach the backdrop.
                    MouseArea {
                        anchors.fill: parent
                    }

                    Text {
                        id: title

                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.topMargin: card.gutter
                        anchors.leftMargin: card.gutter
                        text: "Key bindings"
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.px(28)
                        font.weight: Font.DemiBold
                        color: Theme.fg
                    }

                    Text {
                        anchors.verticalCenter: title.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: card.gutter
                        text: "Esc to close"
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.px(14)
                        color: Theme.surfaceFaint
                    }

                    // Header row and rule.
                    Item {
                        id: head

                        anchors.top: title.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(40)
                        anchors.leftMargin: card.gutter
                        anchors.rightMargin: card.gutter
                        height: Theme.px(36)

                        Row {
                            anchors.fill: parent
                            spacing: card.gutter

                            Repeater {
                                model: root.columnCount

                                Item {
                                    width: (head.width - card.gutter * (root.columnCount - 1))
                                           / root.columnCount
                                    height: head.height

                                    Text {
                                        anchors.left: parent.left
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: Theme.px(10)
                                        text: "KEYS"
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(13)
                                        font.letterSpacing: Theme.px(2)
                                        color: Theme.surfaceText
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: card.chordWidth + Theme.px(18)
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: Theme.px(10)
                                        text: "ACTION"
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(13)
                                        font.letterSpacing: Theme.px(2)
                                        color: Theme.surfaceText
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: Theme.surfaceDim
                        }
                    }

                    // Fixed so the action column lines up without measuring
                    // every row. Fits "Super + Ctrl + Alt + Shift + Delete"
                    // (~260 px in Inter at this size).
                    readonly property int chordWidth: Theme.px(300)

                    Flickable {
                        id: body

                        anchors.top: head.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: card.gutter
                        anchors.rightMargin: card.gutter
                        anchors.topMargin: Theme.px(14)
                        anchors.bottomMargin: Theme.px(22)

                        contentHeight: table.height
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Row {
                            id: table

                            width: parent.width
                            spacing: card.gutter

                            Repeater {
                                model: root.columns

                                Column {
                                    id: column

                                    required property var modelData

                                    width: (table.width - card.gutter * (root.columnCount - 1))
                                           / root.columnCount

                                    Repeater {
                                        model: column.modelData

                                        Item {
                                            id: row

                                            required property var modelData
                                            required property int index

                                            width: column.width
                                            height: card.rowHeight

                                            // Stripe on every other row.
                                            Rectangle {
                                                anchors.fill: parent
                                                visible: row.index % 2 === 0
                                                color: Theme.bg
                                                opacity: 0.55
                                            }

                                            Text {
                                                anchors.left: parent.left
                                                anchors.leftMargin: Theme.px(4)
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: card.chordWidth
                                                text: row.modelData.chord
                                                font.family: Theme.uiFont
                                                font.pixelSize: Theme.px(15)
                                                color: Theme.surfaceText
                                                elide: Text.ElideRight
                                                // Never parse a key label as markup.
                                                textFormat: Text.PlainText
                                            }

                                            Text {
                                                anchors.left: parent.left
                                                anchors.leftMargin: card.chordWidth + Theme.px(18)
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: row.modelData.what
                                                font.family: Theme.uiFont
                                                font.pixelSize: Theme.px(15)
                                                color: Theme.fg
                                                elide: Text.ElideRight
                                            }

                                            // Hairline under every row.
                                            Rectangle {
                                                anchors.bottom: parent.bottom
                                                width: parent.width
                                                height: 1
                                                color: Theme.surfaceFaint
                                                opacity: 0.28
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
