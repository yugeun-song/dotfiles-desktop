pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// A month grid with a heading (month/year, weekday/day) to its left, so the
// grid gets the card's full height.
//
// No events: this machine has no calendar store (no khal, no vdirsyncer).
Item {
    id: root

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    SystemClock {
        id: clock

        // SystemClock has no Days precision; Minutes matches the rest.
        precision: SystemClock.Minutes
    }

    readonly property int year: clock.date.getFullYear()
    readonly property int month: clock.date.getMonth()
    readonly property int today: clock.date.getDate()

    // Monday-first, so the weekend sits together at the end.
    readonly property int leading: (new Date(root.year, root.month, 1).getDay() + 6) % 7
    readonly property int days: new Date(root.year, root.month + 1, 0).getDate()

    // Only the rows the month needs; a fixed six left a blank row that
    // unbalanced the card's margins.
    readonly property int rows: Math.ceil((root.leading + root.days) / 7)

    readonly property var cells: {
        const out = [];
        for (let i = 0; i < root.rows * 7; i++) {
            const day = i - root.leading + 1;
            out.push(day >= 1 && day <= root.days ? day : 0);
        }
        return out;
    }

    // Day under the pointer (0 = none), for the D+n distance readout.
    property int hoveredDay: 0

    // Korean D-day notation: D+n in the future, D-n in the past.
    function dayOffset(day: int): string {
        const delta = day - root.today;
        if (delta === 0)
            return "D-Day";
        return delta > 0 ? `D+${delta}` : `D${delta}`;
    }

    // Sunday red, Saturday blue, as on Korean calendars.
    function weekendColor(column: int, fallback: color): color {
        if (column === 6)
            return Theme.accentRed;
        if (column === 5)
            return Theme.accentIndigo;
        return fallback;
    }

    // Out of the flow so it never moves the grid.
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

        // Explicit width: without it each Text sizes to its own string and the
        // lines read as indented.
        Column {
            id: heading

            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(monthText.implicitWidth, yearText.implicitWidth, today.implicitWidth)
            spacing: Theme.px(10)

            Column {
                width: parent.width
                // Tightened so month and year read as one date.
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
                    font.weight: Font.Normal
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.40)
                }
            }

            Row {
                id: today

                spacing: Theme.px(6)

                Text {
                    id: weekdayText

                    // Shared baseline: two sizes centred on each other sit on nothing.
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
                    // Not bold: at this size weight reads as width.
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

                    // Today and the hovered day share one disc: they are the two
                    // ends of the distance being read.
                    Rectangle {
                        anchors.centerIn: parent
                        visible: cell.marked
                        width: Theme.calendarCellSize
                        height: Theme.calendarCellSize
                        radius: width / 2
                        // Same fill as the workspace indicator.
                        color: Theme.fg
                    }

                    HoverHandler {
                        id: hover

                        enabled: cell.present
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
