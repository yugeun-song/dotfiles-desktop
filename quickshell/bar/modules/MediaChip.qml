pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// What is playing, in the middle of the bar, in the bar's own type.
//
// Not a surface of its own and not styled as one: the same font, the same size
// and the same colour as everything else on the bar, capped in width so a long
// title cannot reach either group beside it. Hovering it opens the player.
Item {
    id: root

    readonly property string line: {
        if (!Media.present)
            return "";
        return Media.artist !== "" ? `${Media.title}  ·  ${Media.artist}` : Media.title;
    }

    readonly property int itemGap: Theme.px(7)

    // The row's parts, measured before it is laid out, because the title has to
    // be told a width and the width is whatever the others leave.
    //
    // Every part counts here, including the meter and the second gap it brings
    // with it. Leaving them out made the item narrower than what it drew, and
    // the hover highlight -- which is the item, not the row -- stopped short of
    // the title while the title carried on past it.
    readonly property int meterWidth: meter.visible ? meter.implicitWidth : 0
    readonly property int gapCount: meter.visible ? 2 : 1
    readonly property int fixedWidth: glyph.implicitWidth + root.meterWidth + root.itemGap * root.gapCount
    readonly property int textRoom: Math.max(0, Theme.mediaChipWidth - root.fixedWidth)
    readonly property int textWidth: Math.min(Math.ceil(metrics.width) + Theme.px(2), root.textRoom)

    // cava runs whenever something is playing, because the chip draws a level
    // too. It holds a PipeWire capture stream and costs CPU, so it stops the
    // moment playback does. Bound rather than written, so a copy torn down on a
    // monitor change cannot switch it off under a surviving one.
    Binding {
        target: Cava
        property: "active"
        value: Media.playing
        restoreMode: Binding.RestoreNone
    }

    visible: Media.present
    implicitWidth: root.fixedWidth + root.textWidth + Theme.menuItemPadX * 2
    implicitHeight: Theme.barHeight

    TextMetrics {
        id: metrics

        font.family: Theme.uiFont
        font.pixelSize: Theme.menuBarTextSize
        text: root.line
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: Theme.barInset
        anchors.bottomMargin: Theme.barInset
        radius: Theme.menuItemRadius
        color: Media.open ? Theme.menuHover : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: root.itemGap

        // Shows the state rather than the action: this is a readout, and the
        // buttons that do something are in the card it opens.
        Text {
            id: glyph

            anchors.verticalCenter: parent.verticalCenter
            height: Theme.barLineHeight
            verticalAlignment: Text.AlignVCenter
            text: Media.playing ? Theme.iconPlay : Theme.iconPause
            font.family: Theme.iconFont
            font.pixelSize: Theme.statusIconSize
            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.65)
        }

        // The one thing up here that moves, which is what makes a glance at the
        // middle of the bar say something is playing without reading the title.
        Visualizer {
            id: meter

            anchors.verticalCenter: parent.verticalCenter
            visible: Media.playing && Cava.levels.length > 0
            wellHeight: Theme.barHeight - Theme.barInset * 2 - Theme.px(3)
            barColor: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.85)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: root.textWidth
            height: Theme.barLineHeight
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: root.line
            // Title and artist come from the player, and for a browser that
            // means from the page. Nothing here ever wanted markup.
            textFormat: Text.PlainText
            font.family: Theme.uiFont
            font.pixelSize: Theme.menuBarTextSize
            color: Theme.fg
        }
    }

    HoverHandler {
        onHoveredChanged: Media.chipHovered = hovered
    }

    MediaPopup {
        anchorItem: root
    }
}
