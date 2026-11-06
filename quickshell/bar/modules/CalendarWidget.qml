pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The calendar widget, in WidgetCard's reference pixels: today's date huge
// (HeroText) between the weekday and the month in small type, alone in the
// small card and beside the month in the medium; the month alone in the
// large, the default and the bar's month when the clock is hovered
// (CalendarPopup), so the two are one design. A day under the pointer is
// marked and its distance from today read in D-day notation, as the bar's
// month always did (the user, 2026-11-05), beside the words for today and
// never in their place (the same day: print them together, do not swap the
// words; 2026-11-06: in the medium card too, as its size allows). Sunday
// red and Saturday blue, as Korean calendars colour them; Monday first
// unless its options say Sunday.
Item {
    id: root

    required property string size
    required property var options
    // The pointer over the card, in these reference pixels, or null: the
    // card's own hover (WidgetCard), so the days need no handler each.
    property var pointer: null

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    readonly property int year: clock.date.getFullYear()
    readonly property int month: clock.date.getMonth()
    readonly property int today: clock.date.getDate()
    readonly property bool mondayFirst: root.options.mondayFirst
    readonly property int leading: (new Date(root.year, root.month, 1).getDay() + (root.mondayFirst ? 6 : 0)) % 7
    readonly property int days: new Date(root.year, root.month + 1, 0).getDate()
    readonly property int rows: Math.ceil((root.leading + root.days) / 7)
    readonly property var cells: {
        const out = [];
        for (let i = 0; i < root.rows * 7; i++) {
            const day = i - root.leading + 1;
            out.push(day >= 1 && day <= root.days ? day : 0);
        }
        return out;
    }
    readonly property var letters: root.mondayFirst ? ["M", "T", "W", "T", "F", "S", "S"] : ["S", "M", "T", "W", "T", "F", "S"]

    // The day under the pointer, 0 for none: worked out from the grid's
    // place, so it costs nothing while the pointer is away.
    readonly property int hoveredDay: {
        const p = root.pointer;
        if (!p || !monthColumn.visible)
            return 0;
        const g = root.grid;
        const col = Math.floor((p.x - g.x) / g.pitch);
        const row = Math.floor((p.y - g.y) / g.pitch);
        if (col < 0 || col > 6 || row < 0 || row >= root.rows)
            return 0;
        return root.cells[row * 7 + col] ?? 0;
    }

    // The last day under the pointer, so its distance fades out as it was.
    property int lastHovered: 0
    readonly property string lastOffset: root.lastHovered > 0 ? root.dayOffset(root.lastHovered) : ""

    onHoveredDayChanged: {
        if (root.hoveredDay > 0)
            root.lastHovered = root.hoveredDay;
    }

    // A day's cell, for the bar's month to set its scale by (CalendarPopup).
    readonly property real cellSize: monthColumn.cell

    // Where the days start and how far apart they are, in these pixels.
    readonly property var grid: ({
        x: monthColumn.x + monthGrid.x,
        y: monthColumn.y + monthGrid.y + monthColumn.headH + monthColumn.gap,
        pitch: monthColumn.cell + monthColumn.gap
    })

    // Korean D-day notation: D+n ahead, D-n behind.
    function dayOffset(day: int): string {
        const delta = day - root.today;
        if (delta === 0)
            return "D-Day";
        return delta > 0 ? `D+${delta}` : `D${delta}`;
    }

    // The column's day of the week, Sunday 0.
    function weekday(column: int): int {
        return root.mondayFirst ? (column + 1) % 7 : column;
    }

    function dayColor(column: int, fallback: color): color {
        const d = root.weekday(column);
        return d === 0 ? Theme.accentRed : d === 6 ? Theme.accentIndigo : fallback;
    }

    // Today: the small card, and the medium card's left.
    Item {
        id: todayArea

        readonly property real gap: 8

        visible: root.size !== "large"
        x: Theme.widgetPad
        y: Theme.widgetPad
        width: (root.size === "medium" ? monthColumn.x - monthColumn.apart : root.width - Theme.widgetPad) - Theme.widgetPad
        height: root.height - Theme.widgetPad * 2

        Text {
            id: weekdayText

            width: parent.width
            elide: Text.ElideRight
            text: Qt.formatDateTime(clock.date, "dddd").toUpperCase()
            font.family: Theme.uiFont
            font.pixelSize: Theme.widgetSmallText
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
            color: Theme.accentRed
        }

        HeroText {
            y: weekdayText.height + todayArea.gap
            width: parent.width
            height: parent.height - weekdayText.height - monthLine.height - todayArea.gap * 2
            text: `${root.today}`
            probe: "00"
        }

        // The month, and after it the distance to the day under the pointer
        // in the large card's words for it. Not on a line of its own: the
        // card has none to spare without shrinking today's figure. Not at
        // the line's far end either: there it would stand 10 px from the
        // days' first column and read as one of them. Only the medium card
        // has the days, so only it keeps room for the distance.
        Item {
            id: monthLine

            anchors.bottom: parent.bottom
            width: parent.width
            height: monthText.implicitHeight

            Text {
                id: monthText

                width: Math.min(monthText.implicitWidth,
                                parent.width - (monthDistance.visible ? monthDistance.implicitWidth + monthDistance.gap : 0))
                elide: Text.ElideRight
                text: Qt.formatDateTime(clock.date, "MMMM yyyy")
                font.family: Theme.uiFont
                font.pixelSize: Theme.widgetTitleSize
                font.weight: Font.Medium
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.55)
            }

            Text {
                id: monthDistance

                readonly property real gap: 8

                visible: monthColumn.visible
                x: monthText.width + monthDistance.gap
                anchors.baseline: monthText.baseline
                text: root.lastOffset
                font.family: Theme.uiFont
                font.pixelSize: Theme.widgetTitleSize
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.72)
                opacity: root.hoveredDay > 0 ? 1 : 0

                Behavior on opacity {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    // The month: beside today in the medium card, the whole card in the large.
    Column {
        id: monthColumn

        readonly property bool large: root.size === "large"
        // The days built as the bar's month first built them (the user,
        // 2026-11-05, after several sizes that read worse: "as it was"):
        // square cells set apart by 3/22 of one, the day in Medium with
        // proportional figures, the weekday letters 11/22 above them in a
        // row 0.8 of a cell, today and the day under the pointer on a disc
        // the size of a cell; the grid as tall as the card allows, six weeks
        // of it, so a month of five sits in the same cells. The day 12/22 of
        // a cell, a little under the first 13 (the same day: "a little
        // smaller"). In the large card the cells take a set part of it,
        // less than it would hold, and the month's name above them grows
        // into the room that leaves (the same day: the days smaller, the
        // card as it is, the words above larger, then a little less margin
        // round them); the two stand together in its middle.
        readonly property real gridH: root.height - Theme.widgetPad * 2
        readonly property real cell: monthColumn.large ? monthColumn.gridH * 0.108 : monthColumn.gridH / (0.8 + 6 + 6 * 3 / 22)
        readonly property real gap: monthColumn.cell * 3 / 22
        readonly property real headH: monthColumn.cell * 0.8
        // The words at the system widget's sizes (the user, 2026-11-05: the
        // weights, the gaps and the letter shapes kept, the sizes themselves
        // as that widget's): a day as one of its names (nameSize 15), a
        // weekday letter as one of its details (detailSize 12), the month at
        // its largest step (figureH 22). Never more than a medium card's
        // smaller cells hold.
        readonly property int figureSize: Math.min(15, Math.round(monthColumn.cell * 12 / 22))
        readonly property int letterSize: Math.min(12, Math.round(monthColumn.cell * 11 / 22))
        // Between today and the month in the medium card.
        readonly property real apart: 10

        visible: root.size !== "small"
        // Beside today in the medium card; in the middle of the large one.
        x: monthColumn.large ? (root.width - monthColumn.width) / 2 : root.width - Theme.widgetPad - monthColumn.width
        anchors.verticalCenter: parent.verticalCenter
        // Less than the 16 of the month's name alone: the date line under
        // it takes the room, and the heading and the days still stand a
        // card's padding from its edges.
        spacing: monthColumn.large ? 12 : 0

        // The large card's heading: the month, and under it today's date
        // with the distance to the day under the pointer at its end, in the
        // medium card's words for them (its month line's size and inks). A
        // distance beside the month at this size met it (the user,
        // 2026-11-05), and a longer month would run into it.
        Column {
            visible: monthColumn.large
            width: monthGrid.width
            spacing: 3

            Text {
                id: monthTitle

                width: parent.width
                elide: Text.ElideRight
                text: Qt.formatDateTime(clock.date, "MMMM yyyy")
                font.family: Theme.uiFont
                font.pixelSize: 22
                font.weight: Font.DemiBold
                color: Theme.fg
            }

            Item {
                width: parent.width
                height: todayLine.implicitHeight

                Text {
                    id: todayLine

                    width: parent.width - distance.implicitWidth - 8
                    elide: Text.ElideRight
                    text: Qt.formatDateTime(clock.date, "dddd d MMMM")
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.widgetTitleSize
                    font.weight: Font.Medium
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.55)
                }

                Text {
                    id: distance

                    anchors.right: parent.right
                    anchors.baseline: todayLine.baseline
                    text: root.lastOffset
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.widgetTitleSize
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.72)
                    opacity: root.hoveredDay > 0 ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        Grid {
            id: monthGrid

            columns: 7
            spacing: monthColumn.gap

            Repeater {
                model: root.letters

                Item {
                    id: head

                    required property int index
                    required property var modelData

                    width: monthColumn.cell
                    height: monthColumn.headH

                    Text {
                        anchors.centerIn: parent
                        text: head.modelData
                        font.family: Theme.uiFont
                        font.pixelSize: monthColumn.letterSize
                        font.weight: Font.DemiBold
                        color: root.dayColor(head.index, Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.55))
                    }
                }
            }

            Repeater {
                model: root.cells

                Item {
                    id: cell

                    required property int index
                    required property var modelData

                    readonly property bool marked: cell.modelData > 0
                        && (cell.modelData === root.today || cell.modelData === root.hoveredDay)

                    width: monthColumn.cell
                    height: monthColumn.cell

                    // Today and the day under the pointer share one disc: they
                    // are the two ends of the distance read.
                    Rectangle {
                        anchors.centerIn: parent
                        visible: cell.marked
                        width: monthColumn.cell
                        height: width
                        radius: width / 2
                        color: Theme.fg
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: cell.modelData > 0
                        text: `${cell.modelData}`
                        font.family: Theme.uiFont
                        font.pixelSize: monthColumn.figureSize
                        font.weight: cell.marked ? Font.DemiBold : Font.Medium
                        color: cell.marked ? Theme.bg : root.dayColor(cell.index % 7, Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.90))
                    }
                }
            }
        }
    }
}
