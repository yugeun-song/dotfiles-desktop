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
// are already listed under their primary key.
//
// Laid out as a table rather than as headed groups. Grouping put the modifiers
// in a heading and the key in the row, so a row read on its own said "R" and
// the reader had to look up the column to find out that it meant Super+Ctrl+R.
// Every row now carries its whole chord, which makes the headings redundant and
// the rows sortable, and a flat table of equal rows is what that wants to be.
Scope {
    id: root

    // Two, not three. Every row is now as wide as its longest chord plus a
    // description, and three columns of that leaves neither enough room.
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

    // Only the symbols this machine's bindings actually use. A legend that
    // lists glyphs which are not on the page is a second thing to keep true.
    property var legend: []

    // Hyprland reports the modifiers as a bitmask. The mask is a sum, so 69 is
    // SUPER+CTRL+SHIFT.
    readonly property var modNames: [
        { bit: 64, name: "Super" },
        { bit: 4,  name: "Ctrl"  },
        { bit: 8,  name: "Alt"   },
        { bit: 1,  name: "Shift" }
    ]

    // Fewer modifiers first, so the plain Super bindings a reader is most
    // likely to want come before the three-modifier ones. Ties break on the
    // mask so the order is the same every time it opens.
    function modRank(mask) {
        let bits = 0;
        for (let i = 0; i < root.modNames.length; i++)
            if (mask & root.modNames[i].bit)
                bits++;
        return bits * 1000 + mask;
    }

    // The whole chord, written the way the caps in the key overlay write it:
    // the modifiers as their printed symbols, run together because they are one
    // hand shape, then the key.
    //
    // "Super + Ctrl + Alt + Shift + Delete" is thirty-four characters of mostly
    // the same four words repeated down the column, and a reader scanning for
    // one binding has to read all of it to rule each row out. The symbols are
    // four glyphs, and the shape of them is recognised without being read.
    //
    // The cost is that a symbol has to be learned once, which is what the
    // legend along the bottom is for.
    function chordLabel(mask, key) {
        let mods = "";
        for (let i = 0; i < root.modNames.length; i++)
            if (mask & root.modNames[i].bit)
                mods += Theme.modSymbol[root.modNames[i].name];
        const k = root.keyLabel(key);
        const sym = Theme.keySymbol[k];
        return mods + (mods ? "  " : "") + (sym !== undefined ? sym : k);
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

                // Modifier count first, then alphabetical inside it, so the
                // chords of one hand shape stay together and the order is
                // stable between openings.
                rows.sort((a, b) => a.rank - b.rank || a.what.localeCompare(b.what));

                // Split down the middle rather than dealt alternately: a table
                // is read down a column, and dealing would put consecutive rows
                // side by side instead of one under the other.
                //
                // Done here rather than in a binding because a Repeater nested
                // inside a Repeater cannot see the outer index reliably and
                // renders nothing at all when it cannot.
                const per = Math.ceil(rows.length / root.columnCount);
                const cols = [];
                for (let c = 0; c < root.columnCount; c++)
                    cols.push(rows.slice(c * per, (c + 1) * per));

                // Everything the chords ended up drawing, in the order the
                // legend should read: modifiers first, then keys.
                const seen = {};
                for (let i = 0; i < rows.length; i++) {
                    const c = rows[i].chord;
                    for (let j = 0; j < c.length; j++)
                        if (Theme.symbolName[c[j]] !== undefined)
                            seen[c[j]] = Theme.symbolName[c[j]];
                }
                const order = Object.keys(Theme.modSymbol)
                                    .map(n => Theme.modSymbol[n])
                                    .concat(Object.keys(Theme.keySymbol)
                                                  .map(n => Theme.keySymbol[n]));
                const key = [];
                for (let i = 0; i < order.length; i++)
                    if (seen[order[i]] !== undefined)
                        key.push({ sym: order[i], name: seen[order[i]] });

                root.legend = key;
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
                    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.82)

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.close()
                    }
                }

                Rectangle {
                    id: card

                    // One row of the table, and the only height in here that
                    // other things are measured against. Uniform on purpose:
                    // the alternating tint that makes a long table readable
                    // only reads as stripes when the stripes are equal.
                    readonly property int rowHeight: Theme.px(34)
                    readonly property int gutter: Theme.px(26)

                    anchors.centerIn: parent
                    width: Math.min(parent.width - Theme.px(64), Theme.px(1560))
                    height: Math.min(parent.height - Theme.px(64), Theme.px(960))
                    radius: Theme.px(18)
                    color: Theme.bgAlt
                    border.width: 1
                    border.color: Theme.accentQuiet

                    // Clicks on the card must not reach the dimmer behind it,
                    // or reading the sheet would close it.
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
                        color: Theme.muted
                    }

                    // The header row, and the rule under it. Uppercase mono,
                    // spaced out: it has to read as a label for the column and
                    // not as the first entry in it.
                    Item {
                        id: head

                        anchors.top: title.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(22)
                        anchors.leftMargin: card.gutter
                        anchors.rightMargin: card.gutter
                        height: Theme.px(30)

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
                                        anchors.bottomMargin: Theme.px(6)
                                        text: "KEYS"
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(13)
                                        font.letterSpacing: Theme.px(2)
                                        color: Theme.accentTeal
                                    }

                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: card.chordWidth + Theme.px(18)
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: Theme.px(6)
                                        text: "ACTION"
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(13)
                                        font.letterSpacing: Theme.px(2)
                                        color: Theme.accentTeal
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: Theme.accentQuiet
                        }
                    }

                    // How much of a column the chord takes. Fixed rather than
                    // fitted to the longest one: measuring every row to find
                    // the widest means building every row, and the point of a
                    // table is that the second column starts in the same place
                    // on every line whether or not the first one filled it.
                    //
                    // Narrower than it was, because the chords are symbols now.
                    // What sets it is no longer the modifiers but the handful of
                    // keys that keep their words: "Brightness Down" and
                    // "Super (right)" are the longest, and they sit under four
                    // modifier glyphs at worst.
                    readonly property int chordWidth: Theme.px(215)

                    Flickable {
                        id: body

                        anchors.top: head.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: foot.top
                        anchors.leftMargin: card.gutter
                        anchors.rightMargin: card.gutter
                        anchors.bottomMargin: Theme.px(6)

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

                                            // Every other row, and nothing on
                                            // the ones between: a stripe that
                                            // is a shade of the card reads as
                                            // one table, where two full colours
                                            // read as two.
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
                                                color: Theme.beige
                                                elide: Text.ElideRight
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

                                            // Hairline, and under every row
                                            // including the striped ones, so
                                            // the eye has a ruler to follow
                                            // across to the description.
                                            Rectangle {
                                                anchors.bottom: parent.bottom
                                                width: parent.width
                                                height: 1
                                                color: Theme.muted
                                                opacity: 0.28
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // The legend, which is the only thing under the table.
                    Item {
                        id: foot

                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: card.gutter
                        anchors.rightMargin: card.gutter
                        anchors.bottomMargin: Theme.px(16)
                        height: Theme.px(30)

                        Rectangle {
                            anchors.top: parent.top
                            width: parent.width
                            height: 1
                            color: Theme.accentQuiet
                            opacity: 0.5
                        }

                        // What each glyph in the chords stands for. This is the
                        // whole price of writing them as symbols, and it is paid
                        // once, here, where the eye lands after the table.
                        Flow {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            spacing: Theme.px(20)

                            Repeater {
                                model: root.legend

                                Row {
                                    required property var modelData

                                    spacing: Theme.px(6)

                                    Text {
                                        text: parent.modelData.sym
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(15)
                                        color: Theme.beige
                                    }

                                    Text {
                                        text: parent.modelData.name
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(14)
                                        color: Theme.muted
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
