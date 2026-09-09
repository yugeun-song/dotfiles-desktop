import QtQuick
import qs.services

// The system glyph at the far left, in the place and with the role the Apple
// menu has: the things you do to the machine rather than to a document.
//
// Two entries, which are the two that are always available and always mean the
// same thing. Everything else about power lives in the power menu, which has a
// key of its own and does not need a second door here.
Item {
    id: root

    implicitHeight: Theme.barHeight
    implicitWidth: logo.implicitWidth + Theme.menuItemPadX * 2

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: Theme.barInset
        anchors.bottomMargin: Theme.barInset
        radius: Theme.menuItemRadius
        color: systemMenu.open ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.20)
                               : hover.hovered ? Theme.menuHover : "transparent"

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
        height: Theme.barLineHeight
        verticalAlignment: Text.AlignVCenter
        text: String.fromCodePoint(0xF08C7)
        font.family: Theme.iconFont
        // The glyph's ink fills 0.64 of its em box, so this lands the drawing
        // at the height asked for rather than at the size set.
        font.pixelSize: Math.round(Theme.menuBarTextSize / 0.64)
        // Monochrome, like every other glyph on this bar. It was sky blue on
        // the old bar, which in a menu bar reads as a status light.
        color: Theme.fg
    }

    HoverHandler {
        id: hover
    }

    Tooltip {
        anchorItem: root
        active: hover.hovered && !systemMenu.open
        text: `Arch Linux\nKernel    ${Resources.kernel}\nUptime    ${Resources.uptimeText}`
    }

    PopupMenu {
        id: systemMenu

        anchorItem: root
        entries: [
            {
                label: "Lock",
                icon: Theme.iconLock,
                // Through loginctl, never hyprlock directly. The reason is in
                // PowerMenu.qml: lock.sh turns the input method off first, and
                // hyprlock binds no text-input protocol, so a lock that skips
                // that step eats every keystroke composed in Hangul and walks
                // the account into pam_faillock.
                detail: "loginctl lock-session",
                action: () => Apps.open(["loginctl", "lock-session"])
            },
            {
                label: "Sign out",
                icon: Theme.iconLogout,
                // In Lua syntax: hyprctl wraps what follows "dispatch" as
                // hl.dispatch(<that>), and a bare "exit" evaluates to nil and
                // is refused with no message reaching here.
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
