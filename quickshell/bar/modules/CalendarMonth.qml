pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// A month, with today's date set beside it.
//
// It was a strip of the seven days around today, which was too little: the
// question people take to a calendar is "what date is the Thursday after
// next", and a strip cannot answer it.
//
// The heading stays at the left of the grid, stacked and flush to one edge,
// which is what leaves the grid the full height of the card and keeps the card
// wider than it is tall. It is two blocks: the month over the year, and the
// weekday beside the day, the day set large enough to be read without stopping.
//
// Both blocks are in the type the rest of the shell uses. An earlier pass set
// the month in wide-tracked capitals over a 46px day, copying a phone's lock
// screen; on a card this size that is a poster, and the month competed with the
// grid it is a label for.
//
// Nothing about events. This machine has no calendar -- no khal, no
// vdirsyncer, no local store -- so a line under the grid could only ever have
// said "nothing", which is a decoration pretending to be a readout. Alarms
// live on the bar's own alarm item, where they are real.
Item {
    id: root

    // Sized by its contents, because the card around it sizes to this.
    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    SystemClock {
        id: clock

        // Nothing here changes until the date does, but Days is not a
        // precision SystemClock offers and Hours would still be 24 wakes for
        // one change. Minutes is what the rest of the shell uses.
        precision: SystemClock.Minutes
    }

    readonly property int year: clock.date.getFullYear()
    readonly property int month: clock.date.getMonth()
    readonly property int today: clock.date.getDate()

    // Monday-first, matching the letters below. Sunday-first split the weekend
    // across the two edges of the row and put the red column under the heading;
    // with Monday first the two days that are not work sit together at the end,
    // which is where every printed calendar this design is taken from puts them.
    readonly property int leading: (new Date(root.year, root.month, 1).getDay() + 6) % 7
    readonly property int days: new Date(root.year, root.month + 1, 0).getDate()

    // As many rows as the month needs, not a fixed six. Six kept the popup one
    // height all year, and the cost was a blank row under most months: the
    // grid then sat higher in the card than it looked, and the margin below it
    // was a row taller than the margin above. The card resizes instead, which
    // nobody sees because it is drawn open rather than resized in place.
    readonly property int rows: Math.ceil((root.leading + root.days) / 7)

    readonly property var cells: {
        const out = [];
        for (let i = 0; i < root.rows * 7; i++) {
            const day = i - root.leading + 1;
            out.push(day >= 1 && day <= root.days ? day : 0);
        }
        return out;
    }

    // The day under the pointer, 0 for none. The card answers one question the
    // grid alone cannot: how far off a date is. Counting cells does it and
    // miscounts across a row break, which is the whole reason for the readout.
    property int hoveredDay: 0

    // Positive into the future, the way a countdown is written. Today is
    // D-Day, and the sign is the direction rather than a minus sign that has
    // to be read twice.
    function dayOffset(day: int): string {
        const delta = day - root.today;
        if (delta === 0)
            return "D-Day";
        return delta > 0 ? `D+${delta}` : `D${delta}`;
    }

    // The last two columns, since the week starts on Monday.
    function weekendColor(column: int, fallback: color): color {
        if (column === 6)
            return Theme.accentRed;
        if (column === 5)
            return Theme.accentIndigo;
        return fallback;
    }

    // Bottom left of the card, under the heading, and out of the flow so that
    // appearing and disappearing with the pointer never moves the grid.
    Text {
        anchors.left: layout.left
        anchors.bottom: layout.bottom
        visible: root.hoveredDay > 0
        text: root.hoveredDay > 0 ? root.dayOffset(root.hoveredDay) : ""
        font.family: Theme.uiFont
        font.pixelSize: Theme.calendarTodayLabel
        font.weight: Font.DemiBold
        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.72)
    }

    Row {
        id: layout

        anchors.centerIn: parent
        spacing: Theme.calendarGap

        // All three lines flush to the same left edge, which is the Column's
        // default and still has to be given a width: without one each Text
        // sizes to its own string, and the day under the month then reads as
        // indented however it is actually placed.
        Column {
            id: heading

            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(monthText.implicitWidth, yearText.implicitWidth, today.implicitWidth)
            spacing: Theme.px(10)

            // Both lines flush to the same left edge. Left is the Column's
            // default and it still has to be said: without a width the two
            // Texts each size to their own string, and "2026" under
            // "September" then reads as indented however it is actually placed.
            Column {
                width: parent.width
                // Negative, because two lines of the same size at their own
                // leading read as two separate readings rather than one date.
                spacing: -Theme.px(4)

                Text {
                    id: monthText

                    width: parent.width
                    text: Qt.formatDateTime(clock.date, "MMMM")
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.calendarMonthSize
                    font.weight: Font.DemiBold
                    color: Theme.fg
                }

                Text {
                    id: yearText

                    width: parent.width
                    text: `${root.year}`
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.calendarMonthSize
                    // Lighter and dimmer than the month: the year is the part
                    // nobody is checking, and it is here so the month is not
                    // floating without a date.
                    font.weight: Font.Normal
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.40)
                }
            }

            Row {
                id: today

                spacing: Theme.px(6)

                Text {
                    id: weekdayText

                    // On the day's baseline rather than its centre. Two sizes
                    // centred on each other sit on nothing; on a shared
                    // baseline they read as one line.
                    anchors.baseline: dayText.baseline
                    text: Qt.formatDateTime(clock.date, "ddd")
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.calendarTodayLabel
                    font.weight: Font.DemiBold
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.55)
                }

                Text {
                    id: dayText

                    text: `${root.today}`
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.calendarTodaySize
                    // Not bold. At this size weight reads as width, and the
                    // number is already the widest thing in the heading.
                    font.weight: Font.Medium
                    color: Theme.fg
                }
            }
        }

        Grid {
            id: grid

            anchors.verticalCenter: parent.verticalCenter
            columns: 7
            spacing: Theme.px(3)

            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]

                Item {
                    id: head

                    required property int index
                    required property var modelData

                    width: Theme.calendarCellSize
                    height: Math.round(Theme.calendarCellSize * 0.8)

                    Text {
                        anchors.centerIn: parent
                        text: head.modelData
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.calendarWeekdaySize
                        font.weight: Font.DemiBold
                        // The two ends of the week, in the convention a Korean
                        // calendar uses: Sunday red, Saturday blue. Both are
                        // Tokyo Night's, which is where this palette takes its
                        // accents from, so they sit at the same chroma and
                        // lightness as each other and as the rest.
                        color: root.weekendColor(head.index,
                                                 Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.55))
                    }
                }
            }

            Repeater {
                model: root.cells

                Item {
                    id: cell

                    required property int index
                    required property var modelData

                    readonly property bool present: cell.modelData > 0
                    readonly property bool isToday: cell.present && cell.modelData === root.today
                    readonly property bool marked: cell.isToday || hover.hovered

                    width: Theme.calendarCellSize
                    height: Theme.calendarCellSize

                    // Today is a filled disc rather than a colour, so it is
                    // found without comparing shades. The day under the pointer
                    // takes the same disc: the question the pointer is asking
                    // is how far that day is from this one, and the two ends of
                    // that measurement should look like the same kind of thing.
                    Rectangle {
                        anchors.centerIn: parent
                        visible: cell.marked
                        width: Theme.calendarCellSize
                        height: Theme.calendarCellSize
                        radius: width / 2
                        // The same fill the workspace indicator uses, so the
                        // two marks in this shell that mean "here" match.
                        color: Theme.fg

                        // Only the arriving disc animates. Today's is there
                        // before the card opens and has nothing to arrive from.
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 90
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    HoverHandler {
                        id: hover

                        enabled: cell.present
                        // A cell that reports something when the pointer is on
                        // it is a control, and a control says so before it is
                        // touched.
                        cursorShape: Qt.PointingHandCursor

                        onHoveredChanged: {
                            if (hover.hovered)
                                root.hoveredDay = cell.modelData;
                            else if (root.hoveredDay === cell.modelData)
                                root.hoveredDay = 0;
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: cell.present
                        text: cell.present ? `${cell.modelData}` : ""
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.calendarDaySize
                        font.weight: cell.marked ? Font.DemiBold : Font.Medium
                        color: cell.marked ? Theme.bg
                                           : root.weekendColor(cell.index % 7,
                                                               Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.90))
                    }
                }
            }
        }
    }
}
