pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// A month, with the month and year set to the side of it.
//
// It was a strip of the seven days around today, which was too little: the
// question people take to a calendar is "what date is the Thursday after
// next", and a strip cannot answer it.
//
// The heading is stacked at the left rather than centred above, which is what
// leaves the grid the full height of the surface and gives the two lines of
// the heading somewhere to be. Both are left-aligned to the same edge.
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

    // Sunday-first, matching the weekday letters below.
    readonly property int leading: new Date(root.year, root.month, 1).getDay()
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

    Row {
        id: layout

        anchors.centerIn: parent
        spacing: Theme.calendarGap

        // Both lines flush to the same left edge. Left is the Column's default
        // and it still has to be said: without a width the two Texts each size
        // to their own string, and "2026" under "September" then reads as
        // indented however it is actually placed.
        Column {
            id: heading

            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(monthText.implicitWidth, yearText.implicitWidth)
            spacing: -Theme.px(4)

            Text {
                id: monthText

                width: parent.width
                horizontalAlignment: Text.AlignLeft
                text: Qt.formatDateTime(clock.date, "MMMM")
                font.family: Theme.uiFont
                font.pixelSize: Theme.calendarMonthSize
                font.weight: Font.DemiBold
                color: Theme.fg
            }

            Text {
                id: yearText

                width: parent.width
                horizontalAlignment: Text.AlignLeft
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

        Grid {
            anchors.verticalCenter: parent.verticalCenter
            columns: 7
            spacing: Theme.px(3)

            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]

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
                        // Sunday is the week's edge, which is the one thing a
                        // grid cannot show by position alone.
                        // The two ends of the week, in the convention a
                        // Korean calendar uses: Sunday red, Saturday blue.
                        // Both are Tokyo Night's, which is where this palette
                        // takes its accents from, so they sit at the same
                        // chroma and lightness as each other and as the rest.
                        color: head.index === 0 ? Theme.accentRed
                               : head.index === 6 ? Theme.accentIndigo
                                                  : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.35)
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
                    readonly property bool sunday: cell.index % 7 === 0
                    readonly property bool saturday: cell.index % 7 === 6

                    width: Theme.calendarCellSize
                    height: Theme.calendarCellSize

                    // Today is a filled disc rather than a colour, so it is
                    // found without comparing shades.
                    Rectangle {
                        anchors.centerIn: parent
                        visible: cell.isToday
                        width: Theme.calendarCellSize
                        height: Theme.calendarCellSize
                        radius: width / 2
                        // The same fill the workspace indicator uses, so the
                        // two marks in this shell that mean "here" match.
                        color: Theme.fg
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: cell.present
                        text: cell.present ? `${cell.modelData}` : ""
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.calendarDaySize
                        font.weight: cell.isToday ? Font.DemiBold : Font.Normal
                        color: cell.isToday ? Theme.bg
                               : cell.sunday ? Theme.accentRed
                               : cell.saturday ? Theme.accentIndigo
                                               : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.72)
                    }
                }
            }
        }
    }
}
