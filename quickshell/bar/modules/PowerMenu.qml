pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import qs.services

// A session dialog in the shape Ctrl+Alt+Del gives you on Windows: lock,
// sign out, sleep, restart, shut down.
//
// Every entry is checked against the system before it is offered. Showing a
// Lock button on a machine without a locker installed would be worse than not
// showing it, because the failure arrives only after the click, by which time
// the screen is expected to already be locked.
Scope {
    id: root

    property bool open: false

    function toggle() {
        root.open = !root.open;
    }

    function close() {
        root.open = false;
    }

    readonly property var entries: [
        {
            id: "lock",
            label: "Lock",
            icon: Theme.iconLock,
            accent: Theme.accentIndigo,
            command: ["hyprlock"],
            probe: "hyprlock"
        },
        {
            id: "logout",
            label: "Sign out",
            icon: Theme.iconLogout,
            accent: Theme.accentSky,
            command: ["hyprctl", "dispatch", "exit"],
            probe: "hyprctl"
        },
        {
            id: "suspend",
            label: "Sleep",
            icon: Theme.iconSleep,
            accent: Theme.accentTeal,
            command: ["systemctl", "suspend"],
            probe: "systemctl"
        },
        {
            id: "reboot",
            label: "Restart",
            icon: Theme.iconRestart,
            accent: Theme.accentAmber,
            command: ["systemctl", "reboot"],
            probe: "systemctl"
        },
        {
            id: "poweroff",
            label: "Shut down",
            icon: Theme.iconPower,
            accent: Theme.accentRed,
            command: ["systemctl", "poweroff"],
            probe: "systemctl"
        }
    ]

    // Which of the above are actually usable here. Populated once at startup
    // rather than per open, so the dialog never waits on a process.
    property var available: ({})

    Component.onCompleted: probe.running = true

    Process {
        id: probe

        command: ["sh", "-c", "for c in hyprlock hyprctl systemctl; do command -v \"$c\" >/dev/null 2>&1 && echo \"$c\"; done"]

        stdout: SplitParser {
            onRead: line => {
                const name = line.trim();
                if (name === "")
                    return;
                const next = Object.assign({}, root.available);
                next[name] = true;
                root.available = next;
            }
        }
    }

    readonly property var usable: root.entries.filter(e => root.available[e.probe] === true)

    function run(entry) {
        root.close();
        if (!entry || !root.available[entry.probe]) {
            console.warn("[power] refusing to run", entry?.id, "-", entry?.probe, "is not installed");
            return;
        }
        action.entryId = entry.id;
        action.command = entry.command;
        action.running = true;
    }

    // The probe says the binary exists, which is not the same as the action
    // being allowed: polkit can refuse a suspend, and hyprlock exits non-zero
    // when the session is already locked. Detaching the command threw that
    // away, so a refused Lock closed the dialog and left nothing behind.
    Process {
        id: action

        property string entryId: ""

        onExited: code => {
            if (code !== 0)
                console.warn("[power]", action.entryId, "exited", code);
        }
    }

    LazyLoader {
        active: root.open

        PanelWindow {
            id: overlay

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
            WlrLayershell.namespace: "quickshell:powermenu"

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

            // The dialog itself swallows clicks so the backdrop handler above
            // does not close it when a button is missed by a pixel.
            Rectangle {
                id: dialog

                anchors.centerIn: parent
                implicitWidth: column.implicitWidth + Theme.px(48)
                implicitHeight: column.implicitHeight + Theme.px(40)
                radius: Theme.px(18)
                color: Theme.bgAlt

                MouseArea {
                    anchors.fill: parent
                }

                Column {
                    id: column

                    anchors.centerIn: parent
                    spacing: Theme.px(18)

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Session"
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.px(15)
                        font.weight: Font.DemiBold
                        color: Theme.muted
                    }

                    Row {
                        spacing: Theme.px(12)

                        Repeater {
                            model: root.usable

                            Rectangle {
                                id: button

                                required property int index
                                required property var modelData

                                readonly property bool current: overlay.selected === button.index

                                width: Theme.px(96)
                                height: Theme.px(96)
                                radius: Theme.px(14)
                                color: button.current || hover.hovered ? button.modelData.accent : Qt.rgba(1, 1, 1, 0.05)

                                Column {
                                    anchors.centerIn: parent
                                    spacing: Theme.px(8)

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: button.modelData.icon
                                        font.family: Theme.iconFont
                                        font.pixelSize: Theme.px(30)
                                        color: button.current || hover.hovered ? Theme.ink : Theme.fg
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: button.modelData.label
                                        font.family: Theme.uiFont
                                        font.pixelSize: Theme.px(12)
                                        font.weight: Font.Medium
                                        color: button.current || hover.hovered ? Theme.ink : Theme.muted
                                    }
                                }

                                HoverHandler {
                                    id: hover

                                    onHoveredChanged: {
                                        if (hovered)
                                            overlay.selected = button.index;
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.run(button.modelData)
                                }
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "arrows to move, enter to confirm, esc to cancel"
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.px(11)
                        color: Theme.muted
                    }
                }
            }

            property int selected: 0

            Item {
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    const n = root.usable.length;
                    if (n === 0) {
                        root.close();
                        event.accepted = true;
                        return;
                    }
                    switch (event.key) {
                    case Qt.Key_Escape:
                        root.close();
                        break;
                    case Qt.Key_Left:
                    case Qt.Key_H:
                        overlay.selected = (overlay.selected - 1 + n) % n;
                        break;
                    case Qt.Key_Right:
                    case Qt.Key_L:
                        overlay.selected = (overlay.selected + 1) % n;
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.run(root.usable[overlay.selected]);
                        break;
                    default:
                        return;
                    }
                    event.accepted = true;
                }
            }
        }
    }

    GlobalShortcut {
        name: "powerMenu"
        description: "Session dialog: lock, sign out, sleep, restart, shut down"
        // pressed is a property, so onPressed fires on the change to true and
        // again on the change back to false. Toggling in both directions
        // opens and closes in one keypress, which looks exactly like a
        // keybinding that does nothing.

        onPressed: {

            if (!pressed)

                return;

            root.toggle()

        }
    }
}
