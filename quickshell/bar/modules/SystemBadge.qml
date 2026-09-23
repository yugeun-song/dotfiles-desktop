import QtQuick
import qs.services

// The system glyph at the far left, in the Apple menu's role. Only lock and
// sign out; the rest of power lives in the power menu, which has its own key.
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
        // The glyph's ink fills 0.64 of its em box.
        font.pixelSize: Math.round(Theme.menuBarTextSize / 0.64)
        // Monochrome: a coloured badge reads as a status light.
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
                // Never hyprlock directly: lock.sh must switch the IME off
                // first, or Hangul-composed keystrokes trip pam_faillock.
                // See PowerMenu.qml and hypr/scripts/lock.sh.
                detail: "loginctl lock-session",
                action: () => Apps.open(["loginctl", "lock-session"])
            },
            {
                label: "Sign out",
                icon: Theme.iconLogout,
                // Lua call syntax: hyprctl wraps it in hl.dispatch(...); a bare
                // "exit" evaluates to nil and is refused silently.
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
