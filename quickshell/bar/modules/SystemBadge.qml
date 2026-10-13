import QtQuick
import qs.services

// The distribution mark at the far left, in the Apple menu's role. Its menu
// picks the mark (BadgePicker, services/Badge.qml); lock and sign out live in
// the power menu, which has its own key.
Item {
    id: root

    implicitHeight: Theme.barHeight
    implicitWidth: logo.implicitWidth + Theme.menuItemPadX * 2

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: Theme.barInset
        anchors.bottomMargin: Theme.barInset
        radius: Theme.menuItemRadius
        color: picker.open ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.20)
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
        // A property, not a mapping function: a singleton's function is not
        // always callable when the first binding runs at start, and a badge
        // that evaluated once as empty would stay empty.
        text: Badge.glyph
        font.family: Theme.iconFont
        // An Arch mark's ink fills 0.64 of its em box; a taller mark is
        // brought to the same height by its scale.
        font.pixelSize: Math.round(Theme.menuBarTextSize / 0.64 * (Badge.current.scale ?? 1))
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
        active: hover.hovered && !picker.open
        text: `${Resources.distroName}\nKernel    ${Resources.kernel}\nUptime    ${Resources.uptimeText}\nClick to choose the mark`
    }

    BadgePicker {
        id: picker

        anchorItem: root
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: picker.toggle()
    }
}
