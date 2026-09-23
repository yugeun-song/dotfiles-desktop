pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// What is playing, centred in the bar in the bar's own type. Width is capped
// by the room between the groups. Hovering opens the player card.
Item {
    id: root

    readonly property string line: {
        if (!Media.present)
            return "";
        return Media.artist !== "" ? `${Media.title}  ·  ${Media.artist}` : Media.title;
    }

    readonly property int itemGap: Theme.px(7)

    // Outer width allowed, set by Bar.qml from what the groups leave free. A
    // share of the screen does not work: on the 1920 panel the status items
    // are drawn larger and reach much further in.
    property int room: Theme.mediaChipWidth + Theme.menuItemPadX * 2

    // The tighter of cap and room, less the highlight's padding.
    readonly property int rowRoom: Math.max(0,
        Math.min(Theme.mediaChipWidth + Theme.menuItemPadX * 2, root.room) - Theme.menuItemPadX * 2)

    // Below this the title is dropped rather than elided to nothing.
    readonly property int titleFloor: Theme.px(56)

    // The meter goes first when room runs out: it repeats what the glyph says,
    // only the title says what is playing.
    readonly property bool meterShown: Media.playing && Cava.levels.length > 0
        && root.rowRoom - glyph.implicitWidth - meter.implicitWidth
           - root.itemGap * 2 >= root.titleFloor

    // Measured up front because the title gets whatever width is left. Count
    // every part and gap, or the highlight (the item) ends short of the row.
    readonly property int meterWidth: root.meterShown ? meter.implicitWidth + root.itemGap : 0
    readonly property int headWidth: glyph.implicitWidth + root.meterWidth + root.itemGap
    readonly property int textRoom: Math.max(0, root.rowRoom - root.headWidth)
    readonly property int textWidth: root.textRoom < root.titleFloor ? 0
                                   : Math.min(Math.ceil(metrics.width) + Theme.px(2), root.textRoom)
    // The gap before the title belongs to the title.
    readonly property int rowWidth: root.textWidth > 0 ? root.headWidth + root.textWidth
                                                       : root.headWidth - root.itemGap

    // cava holds a capture stream, so it runs only while playing. A Binding
    // with RestoreNone, so a bar copy torn down on a monitor change cannot
    // switch it off under a surviving one.
    Binding {
        target: Cava
        property: "active"
        value: Media.playing
        restoreMode: Binding.RestoreNone
    }

    // Hidden rather than overlapping when not even the glyph fits.
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

        // Shows state, not action: the controls are in the card.
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

        Visualizer {
            id: meter

            anchors.verticalCenter: parent.verticalCenter
            visible: root.meterShown
            wellHeight: Theme.barHeight - Theme.barInset * 2 - Theme.px(3)
            barColor: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.85)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            // Hidden, not zero-width: Row still spaces a visible empty item.
            visible: root.textWidth > 0
            width: root.textWidth
            height: Theme.barLineHeight
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: root.line
            // Player metadata (for a browser, the page's); never markup.
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
