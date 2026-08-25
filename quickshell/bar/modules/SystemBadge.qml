import QtQuick
import qs.services

Item {
    id: root

    implicitWidth: Math.round(Theme.pillHeight * 1.15)
    implicitHeight: Theme.pillHeight

    Text {
        anchors.centerIn: parent
        text: String.fromCodePoint(0xF08C7)
        font.family: Theme.iconFont
        font.pixelSize: Theme.px(30)
        color: Theme.blue
    }

    HoverHandler {
        id: hover
    }

    Tooltip {
        anchorItem: root
        active: hover.hovered
        text: `Arch Linux\nKernel    ${Resources.kernel}\nUptime    ${Resources.uptimeText}`
    }
}
