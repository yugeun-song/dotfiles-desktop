import QtQuick
import qs.services

// One system event on the island (services/Island.qml, MediaChip.qml), set
// out as in the user's references (2026-10-26) with the bar's glyphs: glyph
// and value in the event's colour, the words in white, a level as a slim bar
// on the companion's track (Theme.islandDim), a battery as a small cell.
Row {
    id: root

    property string glyph: ""
    property string text: ""
    property string value: ""
    property real level: -1
    property real battery: -1
    property color tone: Theme.islandText
    // The most the island gives it (MediaChip.eventRoom), -1 for no bound:
    // past it the words are cut short, never the value at the right end,
    // which the island's clip took instead.
    property int room: -1
    // Everything but the words, each part with the spacing beside it. By
    // what each part is given, not by `visible`, which turns false with the
    // island's part while that is shut and went round through its width.
    readonly property int others: {
        const widths = [Math.ceil(glyphText.width), Theme.shareGap - root.spacing];
        if (root.level >= 0)
            widths.push(levelBar.width);
        if (root.value !== "")
            widths.push(Math.ceil(valueText.width));
        if (root.battery >= 0)
            widths.push(cellBox.width);
        return widths.reduce((sum, w) => sum + w, 0) + root.spacing * widths.length;
    }
    // Its width, the island's for it (as wide as it holds; the user,
    // 2026-10-26), summed from the parts, since the row's own width loops
    // through the room.
    readonly property int natural: root.others + Math.ceil(words.width)

    spacing: Theme.px(8)

    Text {
        id: glyphText

        anchors.verticalCenter: parent.verticalCenter
        height: Theme.barLineHeight
        verticalAlignment: Text.AlignVCenter
        text: root.glyph
        font.family: Theme.iconFont
        font.pixelSize: Theme.statusIconSize
        color: root.tone
    }

    Text {
        id: words

        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, Math.min(implicitWidth, Theme.islandEventTextMax,
                                    root.room >= 0 ? root.room - root.others : implicitWidth))
        height: Theme.barLineHeight
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.text
        // A device's name comes from the device; never markup.
        textFormat: Text.PlainText
        font.family: Theme.uiFont
        font.pixelSize: Theme.menuBarTextSize
        color: Theme.islandText
    }

    // Apart from the words, as the references keep the value to the right.
    Item {
        id: apart

        width: Theme.shareGap - parent.spacing
        height: 1
    }

    Item {
        id: levelBar

        anchors.verticalCenter: parent.verticalCenter
        visible: root.level >= 0
        width: Theme.islandLevelWidth
        height: Theme.islandLevelHeight

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.islandDim(root.tone)
        }

        Rectangle {
            width: Math.max(height, parent.width * Math.min(1, root.level))
            height: parent.height
            radius: height / 2
            visible: root.level > 0
            color: root.tone
        }
    }

    Text {
        id: valueText

        anchors.verticalCenter: parent.verticalCenter
        visible: root.value !== ""
        height: Theme.barLineHeight
        verticalAlignment: Text.AlignVCenter
        text: root.value
        font.family: Theme.uiFont
        font.pixelSize: Theme.menuBarTextSize
        font.weight: Font.DemiBold
        font.features: ({ "tnum": 1 })
        color: root.tone
    }

    // The cell, its cap on the right.
    Item {
        id: cellBox

        anchors.verticalCenter: parent.verticalCenter
        visible: root.battery >= 0
        width: Theme.islandCellWidth + Math.max(2, Theme.px(2))
        height: Theme.islandCellHeight

        Rectangle {
            id: cell

            width: Theme.islandCellWidth
            height: parent.height
            radius: Math.max(2, Theme.px(3))
            color: "transparent"
            border.width: Math.max(1, Theme.px(1))
            border.color: Theme.islandDim(root.tone)

            Rectangle {
                readonly property int inset: Math.max(2, Theme.px(2))

                x: inset
                y: inset
                width: Math.max(0, (cell.width - inset * 2) * Math.min(1, root.battery))
                height: cell.height - inset * 2
                radius: Math.max(1, cell.radius - inset)
                color: root.tone
            }
        }

        Rectangle {
            anchors.left: cell.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(2, Theme.px(2))
            height: Math.round(parent.height * 0.4)
            radius: width / 2
            color: Theme.islandDim(root.tone)
        }
    }
}
