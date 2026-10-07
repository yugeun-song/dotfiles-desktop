pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import qs.services

// Session dialog: lock, sign out, sleep, restart, shut down. An entry is
// offered only if its binary exists; a Lock that fails after the click is
// worse than none.
Scope {
    id: root

    // Held by Session: the bar's power button opens this dialog too.
    readonly property bool open: Session.menuOpen

    function toggle() {
        Session.toggleMenu();
    }

    function close() {
        Session.menuOpen = false;
    }

    readonly property var entries: [
        {
            id: "lock",
            label: "Lock",
            icon: Theme.iconLock,
            accent: Theme.accentIndigo,
            // Not hyprlock directly: loginctl -> hypridle lock_cmd -> lock.sh,
            // which turns fcitx5 off first. hyprlock binds no text-input, so in
            // Hangul mode keys never reach it and pam_faillock trips.
            command: ["loginctl", "lock-session"],
            probe: "hyprlock"
        },
        {
            id: "logout",
            label: "Sign out",
            icon: Theme.iconLogout,
            accent: Theme.accentSky,
            // Through session-power.sh like restart and shut down: with the
            // panel and an external both lit it turns the panel off first,
            // since a power-off from the greeter after a session that ended
            // with both lit has needed an EC reset here. See its header.
            command: root.sessionPower("logout"),
            probe: "hyprctl"
        },
        {
            id: "suspend",
            label: "Sleep",
            icon: Theme.iconSleep,
            accent: Theme.accentTeal,
            // Locks itself instead of relying on hypridle's before_sleep_cmd,
            // and suspends only once hyprlock is up. app-scope.sh moves the lock
            // out of bar.service's cgroup, so restarting the bar cannot kill it;
            // setsid is the weaker fallback. Backgrounded: lock.sh blocks while
            // hyprlock runs.
            command: ["sh", "-c",
                "l=\"$HOME/.config/hypr/scripts/lock.sh\"; " +
                "s=\"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/bar/scripts/app-scope.sh\"; " +
                "pidof hyprlock >/dev/null 2>&1 || " +
                "if [ -r \"$s\" ]; then sh \"$s\" -- \"$l\" >/dev/null 2>&1 & " +
                "else setsid -f \"$l\" >/dev/null 2>&1; fi; " +
                "for _ in $(seq 50); do pidof hyprlock >/dev/null 2>&1 && exec systemctl suspend; sleep 0.1; done; " +
                "notify-send -u critical 'Sleep cancelled' 'The screen did not lock, so the session was not suspended.'"],
            probe: "systemctl"
        },
        {
            id: "reboot",
            label: "Restart",
            icon: Theme.iconRestart,
            accent: Theme.accentAmber,
            command: root.sessionPower("reboot"),
            probe: "systemctl"
        },
        {
            id: "poweroff",
            label: "Shut down",
            icon: Theme.iconPower,
            accent: Theme.accentRed,
            command: root.sessionPower("poweroff"),
            probe: "systemctl"
        }
    ]

    // Not `systemctl poweroff` straight from here: started inside the session
    // with the external monitor attached, the shutdown has hung this machine
    // after userspace was done, while signing out first never did.
    // session-power.sh reproduces that order (request the action under a
    // logind delay lock, end the compositor, then let it go); its header has
    // the details. It moves itself into a transient user unit in app.slice
    // first, because this process and its children die with
    // hyprland-session.target the moment the compositor's lock file goes,
    // which is before the compositor has released the GPU, and a delay lock
    // held here would go with them. Failures are in
    // journalctl --user -u session-power-<action>.
    function sessionPower(action) {
        return [Paths.hyprScripts + "/session-power.sh", action];
    }

    // Probed once at startup so opening never waits on a process.
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

    // Not detached, so a refusal (e.g. polkit denying suspend) is logged.
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

            // The focused screen (services/Screens.qml says why not the default).
            screen: Screens.focused

            // The dialog's share of this screen, as on the reference output.
            readonly property real fit: Theme.fit(overlay.screen)

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

            // Swallows clicks so a near miss does not hit the backdrop.
            Rectangle {
                id: dialog

                anchors.centerIn: parent
                scale: overlay.fit
                transformOrigin: Item.Center
                implicitWidth: column.implicitWidth + Theme.px(48)
                implicitHeight: column.implicitHeight + Theme.px(40)
                radius: Theme.px(18)
                color: Theme.surfaceBg
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine

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
        // The pressed() signal only; the release edge goes to onReleased.
        onPressed: root.toggle()
    }
}
