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

    // Ranked. The order is what makes a two or three letter query useful:
    // a prefix on the name beats initials, initials beat a match buried in a
    // command line, and a scattered subsequence is the last resort.
    //
    // Keywords carry the names nobody writes on the tile. "vscode" appears
    // nowhere in "Visual Studio Code" or in "code %F"; it is on the Keywords
    // line, which is what that line is for. The window class is here for the
    // same reason: it is the name the window itself answers to.
    // A .desktop field is not always the type the documentation gives:
    // keywords arrives as a list, which has no toLowerCase.
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

    // Every letter of the needle in order, not necessarily adjacent. This is
    // what turns "vscd" into Visual Studio Code, and it is last because on
    // its own it matches far too much.
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

    function score(entry, needle) {
        const name = root.lower(entry.name);
        if (name.startsWith(needle))
            return 0;
        if (root.initials(name).startsWith(needle))
            return 1;
        if (name.includes(needle))
            return 2;

        // Everything below searches text that was written for a person to
        // read, not to be searched. One or two letters match almost every
        // description on the machine, and the result is the whole menu in
        // alphabetical order, which looks exactly like a search that is not
        // running. So the wider fields only open up once the query is long
        // enough to mean something.
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

    // A .desktop Exec line carries field codes the spec says to strip when
    // there is nothing to pass. Leaving them in launches an editor with a
    // literal "%U" as its filename.
    function launch(entry) {
        root.close();
        if (!entry) {
            console.warn("[launcher] nothing selected");
            return;
        }
        // entry.command comes with the field codes already stripped, but
        // quickshell builds it without a terminal even for an entry that asks
        // for one, so btop and friends would start with no tty and exit.
        const argv = entry.command;
        if (Array.isArray(argv) && argv.length > 0) {
            if (entry.runInTerminal === true)
                Quickshell.execDetached(["kitty", "-e"].concat(argv));
            else
                Quickshell.execDetached(argv);
            return;
        }
        const exec = (entry.execString ?? "").replace(/%[fFuUdDnNickvm]/g, "").trim();
        if (exec === "") {
            console.warn("[launcher] no usable Exec line for", entry.name);
            return;
        }
        if (entry.runInTerminal === true)
            Quickshell.execDetached(["kitty", "-e", "sh", "-c", exec]);
        else
            Quickshell.execDetached(["sh", "-c", exec]);
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            // Without this the overlay lands on whichever screen quickshell
            // happens to pick, which on this machine is the parked laptop
            // panel at x=5000 while it is disabled: the window opens
            // correctly and is simply nowhere you can see it.
            screen: {
                const name = Hyprland.focusedMonitor?.name ?? "";
                const match = Quickshell.screens.find(s => s.name === name);
                return match ?? Quickshell.screens[0] ?? null;
            }

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
                width: Theme.px(560)
                implicitHeight: body.implicitHeight + Theme.px(20)
                radius: Theme.px(16)
                color: Theme.bgAlt

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

                            // Seeded once, never bound. Binding text to
                            // root.query while this handler writes root.query
                            // makes the two chase each other: the field kept
                            // showing every letter typed while the query stuck
                            // on the first one, so the results were always a
                            // search for "v" under a box reading "vscode".
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
                                // Ctrl+N and Ctrl+P, so the list can be walked
                                // without leaving the home row. Without the
                                // modifier they are ordinary letters and have
                                // to reach the field.
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

                    // Named rather than left blank: an empty panel looks like
                    // a bug, and the two reasons it can be empty need
                    // different responses from the person looking at it.
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
                                        // Read out of a .desktop file, which anything that can write to a
                                        // data dir controls.
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
