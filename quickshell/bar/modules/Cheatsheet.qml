pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.services

// Key bindings read live from `hyprctl -j binds`, so the sheet never drifts
// from hypr/config/keybinds.lua; binds without a description are left out
// on purpose. As the user asked (2026-11-04): searched as the launcher is,
// laid out to be read at a glance, and the keys drawn as keys, the key
// overlay's caps at a list's size. The grouping, the merging of one action's
// chords and the search are services/Shortcuts.qml's. Modifiers keep their
// words on the caps (Super, Ctrl, Alt, Shift), not the overlay's symbols:
// the sheet is for readers who do not know the bindings yet.
Scope {
    id: root

    property bool open: false
    property var groups: []
    property string query: ""

    readonly property var shown: Shortcuts.filter(root.groups, root.query)
    readonly property int count: root.shown.reduce((n, g) => n + g.rows.length, 0)

    function toggle() {
        if (!root.open && !Surfaces.mayOpen("cheatsheet"))
            return;
        if (!root.open) {
            root.query = "";
            binds.running = true;   // reread on every open; bindings can change
        }
        root.open = !root.open;
    }

    function close() {
        root.open = false;
    }

    // Transient, one panel at a time (services/Surfaces.qml).
    onOpenChanged: Surfaces.report("cheatsheet", root.open)

    Connections {
        target: Surfaces

        function onShut(name) {
            if (name === "cheatsheet")
                root.close();
        }
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
                }
                // Replaced only when the bindings changed: a new list rebuilt
                // every row and the list jumped as it opened.
                const next = Shortcuts.build(parsed);
                if (JSON.stringify(next) !== JSON.stringify(root.groups))
                    root.groups = next;
            }
        }
    }

    GlobalShortcut {
        name: "cheatsheet"
        description: "Show every key binding"
        onPressed: root.toggle()
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            id: win

            screen: Screens.focused
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

            // The sheet's share of this screen, as on the reference output.
            readonly property real fit: Theme.fit(win.screen)

            FittedStage {
                id: stage

                fit: win.fit

                // A clear backdrop (the user, 2026-11-04: only the session
                // dialog dims); clicking it closes the sheet.
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }

                Rectangle {
                    id: card

                    readonly property int gutter: Theme.px(26)
                    // The scroll bar's column beside the list, kept whether or
                    // not it shows.
                    readonly property int barRoom: Theme.px(8) + Theme.px(10)

                    anchors.centerIn: parent
                    // A share of the screen, the same on every one, and one
                    // column, as the user asked (2026-11-04: by ratio, smaller,
                    // a single column). Its height holds whatever a search
                    // leaves, so the card does not jump while typing.
                    width: Math.max(Math.min(Theme.px(520), parent.width - Theme.px(64)),
                                    Math.round(parent.width * 0.36))
                    height: Math.round(parent.height * 0.72)
                    radius: Theme.surfaceRadius
                    color: Theme.surfaceBg
                    border.width: Theme.surfaceBorder
                    border.color: Theme.surfaceLine

                    // Swallow clicks so they do not reach the backdrop.
                    MouseArea {
                        anchors.fill: parent
                    }

                    Item {
                        id: head

                        x: card.gutter
                        y: card.gutter
                        width: card.width - card.gutter * 2
                        height: Theme.px(30)

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Keyboard shortcuts"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(22)
                            font.weight: Font.DemiBold
                            color: Theme.fg
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.query.trim() !== "" ? `${root.count} found · Esc to close` : "Esc to close"
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(13)
                            color: Theme.surfaceFaint
                        }
                    }

                    // The search, set as the launcher's and the weather panel's
                    // fields are; typing goes here.
                    Rectangle {
                        id: search

                        x: card.gutter
                        y: head.y + head.height + Theme.px(14)
                        width: card.width - card.gutter * 2
                        height: Theme.px(40)
                        radius: height / 2
                        color: Theme.surfaceRaised

                        Text {
                            id: glyph

                            x: Theme.px(14)
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.iconSearch
                            font.family: Theme.iconFont
                            font.pixelSize: Theme.px(16)
                            color: Theme.muted
                        }

                        TextInput {
                            id: field

                            anchors.left: glyph.right
                            anchors.leftMargin: Theme.px(10)
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.px(14)
                            anchors.verticalCenter: parent.verticalCenter
                            focus: true
                            clip: true
                            maximumLength: 60
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(14)
                            color: Theme.fg
                            selectionColor: Theme.accentIndigo
                            selectedTextColor: Theme.ink
                            // A composing Hangul syllable counts at once.
                            onTextChanged: root.query = field.text + field.preeditText
                            onPreeditTextChanged: root.query = field.text + field.preeditText

                            Text {
                                anchors.fill: parent
                                visible: field.text === "" && field.preeditText === ""
                                text: "Search shortcuts"
                                font: field.font
                                color: Theme.muted
                            }

                            // Esc closes at once, a search or not (the user,
                            // 2026-11-04: not twice); the next opening starts
                            // with an empty field.
                            Keys.onPressed: event => {
                                switch (event.key) {
                                case Qt.Key_Escape:
                                    root.close();
                                    break;
                                case Qt.Key_Down:
                                    list.contentY = Math.min(list.contentY + Theme.px(40),
                                                             Math.max(0, list.contentHeight - list.height));
                                    break;
                                case Qt.Key_Up:
                                    list.contentY = Math.max(0, list.contentY - Theme.px(40));
                                    break;
                                case Qt.Key_PageDown:
                                    list.contentY = Math.min(list.contentY + list.height * 0.9,
                                                             Math.max(0, list.contentHeight - list.height));
                                    break;
                                case Qt.Key_PageUp:
                                    list.contentY = Math.max(0, list.contentY - list.height * 0.9);
                                    break;
                                default:
                                    return;
                                }
                                event.accepted = true;
                            }
                        }
                    }

                    Flickable {
                        id: list

                        x: card.gutter
                        y: search.y + search.height + Theme.px(18)
                        width: card.width - card.gutter * 2 - card.barRoom
                        height: card.height - list.y - card.gutter
                        contentWidth: list.width
                        contentHeight: groups.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: groups

                            width: list.width
                            spacing: Theme.px(22)

                            Repeater {
                                model: root.shown

                                ShortcutGroup {
                                    required property var modelData

                                    data_: modelData
                                    columnWidth: list.width
                                }
                            }
                        }

                        // Say why the list is empty; the two causes differ.
                        Text {
                            width: list.width
                            visible: root.count === 0
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            text: root.groups.length === 0 ? "No key bindings with a description were found."
                                                           : `No shortcut matches "${root.query.trim()}".`
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.menuItemTextSize
                            color: Theme.muted
                        }
                    }

                    ScrollTrack {
                        x: list.x + list.width + Theme.px(10)
                        y: list.y
                        width: Theme.px(8)
                        height: list.height
                        view: list
                    }
                }
            }
        }
    }
}
