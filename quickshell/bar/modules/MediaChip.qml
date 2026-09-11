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

    // How much of the bar the chip may take, outer edge to outer edge. The bar
    // works it out from what its two groups are not using and sets it; the
    // default is the cap on its own, so anything drawing the chip without
    // measuring for it still gets a whole chip.
    //
    // A fifth of the screen was the whole answer while the only screen was the
    // 2560 monitor. It is not one on a 1920 panel: the same status items are
    // drawn there at a larger scale and reach much further in, and a chip
    // sized as a share of the screen ran under the input method and the radios.
    property int room: Theme.mediaChipWidth + Theme.menuItemPadX * 2

    // Whichever binds first, less the padding the hover highlight carries.
    // What is left is the row's.
    readonly property int rowRoom: Math.max(0,
        Math.min(Theme.mediaChipWidth + Theme.menuItemPadX * 2, root.room) - Theme.menuItemPadX * 2)

    // A title elided down to an ellipsis is not a shorter title, it is a title
    // that failed. Under this the text is dropped instead, and the chip is the
    // glyph that says something is playing.
    readonly property int titleFloor: Theme.px(56)

    // The meter is what goes first when the room runs out. It and the glyph
    // beside it say the same thing -- that something is playing -- and only the
    // title says what, so spending the last of the room on the meter buys
    // nothing and costs the one part that was worth reading.
    readonly property bool meterShown: Media.playing && Cava.levels.length > 0
        && root.rowRoom - glyph.implicitWidth - meter.implicitWidth
           - root.itemGap * 2 >= root.titleFloor

    // The row's parts, measured before it is laid out, because the title has to
    // be told a width and the width is whatever the others leave.
    //
    // Every part counts here, including the meter and the second gap it brings
    // with it. Leaving them out made the item narrower than what it drew, and
    // the hover highlight -- which is the item, not the row -- stopped short of
    // the title while the title carried on past it.
    readonly property int meterWidth: root.meterShown ? meter.implicitWidth + root.itemGap : 0
    readonly property int headWidth: glyph.implicitWidth + root.meterWidth + root.itemGap
    readonly property int textRoom: Math.max(0, root.rowRoom - root.headWidth)
    readonly property int textWidth: root.textRoom < root.titleFloor ? 0
                                   : Math.min(Math.ceil(metrics.width) + Theme.px(2), root.textRoom)
    // The gap before the title goes with the title. Counting it either way
    // round is what makes the highlight and the row the same width.
    readonly property int rowWidth: root.textWidth > 0 ? root.headWidth + root.textWidth
                                                       : root.headWidth - root.itemGap

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

    // Gone rather than overlapping, for the panel narrow enough that even the
    // glyph does not fit between the groups.
    visible: Media.present && root.rowRoom >= glyph.implicitWidth
    implicitWidth: root.rowWidth + Theme.menuItemPadX * 2
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
            visible: root.meterShown
            wellHeight: Theme.barHeight - Theme.barInset * 2 - Theme.px(3)
            barColor: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.85)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // Not a zero-width item: Row lays out what is visible, and one left
            // visible at no width still takes the spacing either side of it.
            visible: root.textWidth > 0
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
