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
        // The glyph's ink fills 0.64 of the em box, so the size set here is
        // not the size on screen. This lands the drawing at the pill height.
        //
        // Weight comes from the size, not from an outline. An outline grows
        // the shape in every direction at once, and the first thing it eats
        // is the notch at the foot of the logo, which is the part that makes
        // it read as the Arch logo rather than as a triangle.
        font.pixelSize: Math.round(Theme.pillHeight / 0.64)
        color: Theme.accentSky
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
