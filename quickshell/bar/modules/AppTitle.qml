pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

// The left end of the menu bar: the system glyph, then the focused window's
// application name.
//
// No File/Edit/View after it. Wayland has no global menu protocol, so a bar
// can only show what an application exported over D-Bus -- which Qt and KDE
// applications do and Chrome, Firefox, kitty and foot do not. Menus for a
// third of what is running is worse than never promising them.
//
// The name answers "what am I typing into". The old bar answered "what is
// open", with a chip per window, which is a different question.
Row {
    id: root

    readonly property var focusedWindow: {
        const windows = Hyprland.focusedWorkspace?.toplevels?.values ?? [];
        return windows.find(w => w.activated) ?? null;
    }

    readonly property string appId: root.focusedWindow?.wayland?.appId
                                    ?? root.focusedWindow?.lastIpcObject?.class ?? ""
    readonly property var entry: root.appId !== "" ? DesktopEntries.heuristicLookup(root.appId) : null
    // The desktop entry's name is the one a person would recognise -- "Visual
    // Studio Code" rather than "code-oss". The class is the fallback, and an
    // empty workspace has neither.
    readonly property string appName: root.entry?.name ?? root.appId
    readonly property string windowTitle: root.focusedWindow?.title ?? ""

    readonly property string hyprScripts: (Quickshell.env("XDG_CONFIG_HOME")
                                           ?? `${Quickshell.env("HOME")}/.config`) + "/hypr/scripts"

    spacing: Theme.menuTitleGap

    // The system glyph, in the place and with the role the Apple menu has:
    // the things you do to the machine rather than to a document. The two
    // entries are the two that are always available and always mean the same
    // thing; everything else about power lives in the power menu, which has a
    // key of its own and does not need a second door here.
    Item {
        id: badge

        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: Theme.barHeight
        implicitWidth: logo.implicitWidth + Theme.menuItemPadX * 2

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: Theme.px(3)
            anchors.bottomMargin: Theme.px(3)
            radius: Theme.menuItemRadius
            color: systemMenu.open ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.20)
                                   : badgeHover.hovered ? Theme.menuHover : "transparent"

            Behavior on color {
                ColorAnimation {
                    duration: 90
                    easing.type: Easing.OutCubic
                }
            }
        }

        Text {
            id: logo

            anchors.centerIn: parent
            text: String.fromCodePoint(0xF08C7)
            font.family: Theme.iconFont
            // The glyph's ink fills 0.64 of its em box, so this lands the
            // drawing at the height asked for rather than at the size set.
            // The same arithmetic the old SystemBadge used, against the menu
            // bar's smaller text rather than against a pill.
            font.pixelSize: Math.round(Theme.menuBarTextSize / 0.64)
            // Monochrome, like every other glyph on this bar. The old badge
            // was sky blue, which on a menu bar reads as a status light.
            color: Theme.fg
        }

        HoverHandler {
            id: badgeHover
        }

        Tooltip {
            anchorItem: badge
            active: badgeHover.hovered && !systemMenu.open
            text: `Arch Linux\nKernel    ${Resources.kernel}\nUptime    ${Resources.uptimeText}`
        }

        PopupMenu {
            id: systemMenu

            anchorItem: badge
            entries: [
                {
                    label: "Lock",
                    icon: Theme.iconLock,
                    // Through loginctl, never hyprlock directly. The reason is
                    // in PowerMenu.qml: lock.sh turns the input method off
                    // first, and hyprlock binds no text-input protocol, so a
                    // lock that skips that step eats every keystroke composed
                    // in Hangul and walks the account into pam_faillock.
                    detail: "loginctl lock-session",
                    action: () => Apps.open(["loginctl", "lock-session"])
                },
                {
                    label: "Sign out",
                    icon: Theme.iconLogout,
                    // In Lua syntax: hyprctl wraps what follows "dispatch" as
                    // hl.dispatch(<that>), and a bare "exit" evaluates to nil
                    // and is refused with no message reaching here.
                    detail: "end the session",
                    action: () => Apps.open(["hyprctl", "dispatch", "hl.dsp.exit()"])
                }
            ]
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: systemMenu.toggle()
        }
    }

    // The name, in the one weight that is not the bar's default. macOS sets
    // the app name apart by weight alone and leaves size and colour to match
    // everything else, which is why it reads as a title rather than as a
    // heading.
    Text {
        id: name

        anchors.verticalCenter: parent.verticalCenter
        visible: root.appName !== ""
        text: root.appName
        // The class and the desktop entry name are both strings this machine
        // did not choose. Nothing here ever wanted markup.
        textFormat: Text.PlainText
        font.family: Theme.uiFont
        font.pixelSize: Theme.menuBarTextSize
        font.weight: Font.DemiBold
        color: Theme.fg

        HoverHandler {
            id: nameHover
        }

        Tooltip {
            anchorItem: name
            active: nameHover.hovered
            text: {
                const lines = [];
                if (root.appName !== "")
                    lines.push(`App       ${root.appName}`);
                if (root.windowTitle !== "")
                    lines.push(`Title     ${Theme.shorten(root.windowTitle, 56)}`);
                if (root.appId !== "")
                    lines.push(`Class     ${root.appId}`);
                return lines.join("\n");
            }
        }
    }
}
