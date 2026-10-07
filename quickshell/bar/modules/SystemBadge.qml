import QtQuick
import qs.services

// The system glyph at the far left, in the Apple menu's role. Only lock and
// sign out; the rest of power lives in the power menu, which has its own key.
Item {
    id: root

    implicitHeight: Theme.barHeight
    implicitWidth: logo.implicitWidth + Theme.menuItemPadX * 2

    // The distribution's mark by /etc/os-release ID; the Material set has
    // the common ones and Tux for the rest. Code points read from the cmap.
    function distroGlyph(id) {
        switch (id) {
        case "arch":
        case "archarm":
        case "manjaro":
        case "endeavouros":
        case "cachyos":
            return String.fromCodePoint(0xF08C7);   // md-arch
        case "ubuntu":
            return String.fromCodePoint(0xF0548);   // md-ubuntu
        case "debian":
            return String.fromCodePoint(0xF08DA);   // md-debian
        case "fedora":
            return String.fromCodePoint(0xF08DB);   // md-fedora
        default:
            return String.fromCodePoint(0xF033D);   // md-linux
        }
    }

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
        // Mapped here, not in Theme: a singleton's function is not always
        // callable when the first binding runs at start, and a badge that
        // evaluated once as empty would stay empty.
        text: root.distroGlyph(Resources.distroId)
        font.family: Theme.iconFont
        // The glyph's ink fills 0.64 of its em box.
        font.pixelSize: Math.round(Theme.menuBarTextSize / 0.64)
        // Monochrome: a coloured badge reads as a status light.
        color: Theme.fg
    }

    HoverHandler {
        id: hover

        // Uptime is read for the tooltip only; see Resources.readUptime.
        onHoveredChanged: {
            if (hover.hovered)
                Resources.readUptime();
        }
    }

    Tooltip {
        anchorItem: root
        active: hover.hovered && !systemMenu.open
        text: `${Resources.distroName}\nKernel    ${Resources.kernel}\nUptime    ${Resources.uptimeText}`
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
                // The same path as the power menu's: session-power.sh turns
                // the panel off first when an external is lit beside it.
                detail: "end the session",
                action: () => Apps.open([Paths.hyprScripts + "/session-power.sh", "logout"])
            }
        ]
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: systemMenu.toggle()
    }
}
