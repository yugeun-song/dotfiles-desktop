pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services

// Application launcher. One instance, toggled by a global shortcut.
Scope {
    id: root

    property bool open: false
    property string query: ""
    property int selected: 0

    readonly property int maxRows: 8

    function toggle() {
        if (root.open) {
            root.close();
        } else {
            root.query = "";
            root.selected = 0;
            root.open = true;
        }
    }

    function close() {
        root.open = false;
    }

    readonly property var allEntries: {
        const list = DesktopEntries.applications?.values ?? [];
        return list.filter(e => e && !e.noDisplay);
    }

    // .desktop fields are not always strings: keywords arrives as a list.
    function lower(value) {
        if (value === undefined || value === null)
            return "";
        if (Array.isArray(value))
            return value.join(" ").toLowerCase();
        return String(value).toLowerCase();
    }

    function initials(text) {
        let out = "";
        for (const word of text.split(/[^a-z0-9]+/)) {
            if (word !== "")
                out += word[0];
        }
        return out;
    }

    // Needle letters in order, not necessarily adjacent ("vscd").
    function subsequence(haystack, needle) {
        let at = 0;
        for (const ch of needle) {
            at = haystack.indexOf(ch, at);
            if (at < 0)
                return false;
            at += 1;
        }
        return true;
    }

    // Lower is better: name prefix, initials, name substring, then
    // genericName/keywords/startupClass, then comment/exec, then subsequence.
    // Keywords catch names absent from the tile ("vscode").
    function score(entry, needle) {
        const name = root.lower(entry.name);
        if (name.startsWith(needle))
            return 0;
        if (root.initials(name).startsWith(needle))
            return 1;
        if (name.includes(needle))
            return 2;

        // Wider fields only for longer queries; a letter or two matches
        // nearly every description.
        if (needle.length < 2)
            return -1;

        const near = [
            root.lower(entry.genericName),
            root.lower(entry.keywords),
            root.lower(entry.startupClass)
        ];
        for (let i = 0; i < near.length; i++) {
            if (near[i].includes(needle))
                return i + 3;
        }

        if (needle.length < 3)
            return -1;

        const far = [
            root.lower(entry.comment),
            root.lower(entry.execString)
        ];
        for (let i = 0; i < far.length; i++) {
            if (far[i].includes(needle))
                return i + 6;
        }

        if (root.subsequence(name, needle))
            return 8;
        return -1;
    }

    readonly property var matches: {
        const needle = root.query.trim().toLowerCase();
        const list = root.allEntries;
        if (needle === "")
            return list.slice().sort((a, b) => (a.name ?? "").localeCompare(b.name ?? "")).slice(0, root.maxRows);
        const scored = [];
        for (const e of list) {
            const s = root.score(e, needle);
            if (s >= 0)
                scored.push({ entry: e, rank: s });
        }
        scored.sort((a, b) => a.rank - b.rank || (a.entry.name ?? "").localeCompare(b.entry.name ?? ""));
        return scored.slice(0, root.maxRows).map(x => x.entry);
    }

    function launch(entry) {
        root.close();
        if (!entry) {
            console.warn("[launcher] nothing selected");
            return;
        }
        // entry.command has field codes stripped but ignores Terminal=true,
        // so wrap it in a terminal ourselves. Apps.open so it survives
        // `bar --restart`.
        // scripts/terminal.sh, not kitty by name: it runs the first terminal
        // installed, so the launcher works on a machine without kitty.
        const terminal = [Paths.hyprScripts + "/terminal.sh", "-e"];
        const argv = entry.command;
        if (Array.isArray(argv) && argv.length > 0) {
            if (entry.runInTerminal === true)
                Apps.open(terminal.concat(argv));
            else
                Apps.open(argv);
            return;
        }
        // Fallback: strip field codes, or an editor opens a literal "%U".
        const exec = (entry.execString ?? "").replace(/%[fFuUdDnNickvm]/g, "").trim();
        if (exec === "") {
            console.warn("[launcher] no usable Exec line for", entry.name);
            return;
        }
        if (entry.runInTerminal === true)
            Apps.open(terminal.concat(["sh", "-c", exec]));
        else
            Apps.open(["sh", "-c", exec]);
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            id: win

            // The focused screen (services/Screens.qml says why not the default).
            screen: Screens.focused

            // The card's share of this screen, as on the reference output.
            readonly property real fit: Theme.fit(win.screen)

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: "quickshell:launcher"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.72)

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Math.round(parent.height * 0.09)
                // Scaled about its top centre: the 9% offset is already a
                // share of the screen, the width and rows are not.
                scale: win.fit
                transformOrigin: Item.Top
                width: Theme.px(560)
                implicitHeight: body.implicitHeight + Theme.px(20)
                radius: Theme.surfaceRadius
                color: Theme.surfaceBg
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine

                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    id: body

                    anchors.centerIn: parent
                    width: parent.width - Theme.px(24)
                    spacing: Theme.px(8)

                    Row {
                        width: parent.width
                        spacing: Theme.px(10)

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.iconSearch
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.px(16)
                            color: Theme.muted
                        }

                        TextInput {
                            id: input

                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.px(38)
                            focus: true
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(15)
                            color: Theme.fg
                            selectionColor: Theme.accentIndigo
                            selectedTextColor: Theme.ink
                            clip: true

                            // Seeded once, never bound: a binding to root.query
                            // plus onTextChanged writing it back loop and stick.
                            Component.onCompleted: input.text = root.query

                            onTextChanged: {
                                root.query = input.text;
                                root.selected = 0;
                            }

                            Text {
                                anchors.fill: parent
                                visible: input.text === ""
                                text: "search applications"
                                font: input.font
                                color: Theme.muted
                            }

                            Keys.onPressed: event => {
                                const n = root.matches.length;
                                const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;

                                function step(by) {
                                    if (n > 0)
                                        root.selected = (root.selected + by + n) % n;
                                }

                                switch (event.key) {
                                case Qt.Key_Escape:
                                    root.close();
                                    break;
                                case Qt.Key_Down:
                                    step(1);
                                    break;
                                case Qt.Key_Up:
                                    step(-1);
                                    break;
                                // Ctrl+N/P step; plain N/P fall through to the field.
                                case Qt.Key_N:
                                    if (!ctrl)
                                        return;
                                    step(1);
                                    break;
                                case Qt.Key_P:
                                    if (!ctrl)
                                        return;
                                    step(-1);
                                    break;
                                case Qt.Key_Return:
                                case Qt.Key_Enter:
                                    root.launch(root.matches[root.selected]);
                                    break;
                                default:
                                    return;
                                }
                                event.accepted = true;
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // Say why the list is empty; the two causes differ.
                    Text {
                        width: parent.width
                        visible: root.matches.length === 0
                        text: root.allEntries.length === 0 ? "no application entries found under XDG_DATA_DIRS" : `nothing matches "${root.query}"`
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.textSize
                        color: Theme.muted
                        padding: Theme.px(10)
                    }

                    Repeater {
                        model: root.matches

                        Rectangle {
                            id: row

                            required property int index
                            required property var modelData

                            readonly property bool current: root.selected === row.index
                            readonly property string iconSource: Theme.appIcon(row.modelData.icon ?? "")

                            width: body.width
                            height: Theme.px(40)
                            radius: Theme.px(10)
                            color: row.current ? Theme.accentIndigo : "transparent"

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.px(10)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.px(12)

                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: row.iconSource !== ""
                                    source: row.iconSource
                                    sourceSize.width: Theme.px(22)
                                    sourceSize.height: Theme.px(22)
                                    width: Theme.px(22)
                                    height: Theme.px(22)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1

                                    Text {
                                        text: row.modelData.name ?? ""
                                        // Untrusted .desktop content.
                                        textFormat: Text.PlainText
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(13)
                                        font.weight: Font.Medium
                                        color: row.current ? Theme.ink : Theme.fg
                                    }

                                    Text {
                                        visible: (row.modelData.genericName ?? "") !== ""
                                        text: row.modelData.genericName ?? ""
                                        textFormat: Text.PlainText
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(10)
                                        color: row.current ? Theme.ink : Theme.muted
                                    }
                                }
                            }

                            HoverHandler {
                                onHoveredChanged: {
                                    if (hovered)
                                        root.selected = row.index;
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.launch(row.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    GlobalShortcut {
        name: "launcher"
        description: "Application launcher"

        onPressed: root.toggle()
    }
}
