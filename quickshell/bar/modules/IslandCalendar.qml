pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// The calendar half of the island: the month, the week around today, and
// what is actually on today.
//
// A week rather than a month grid. A month needs six rows and this surface has
// two, and a month grid answers "what is the date on the 23rd", which is not a
// question anyone asks a status bar. A strip centred on today answers "what
// day is it and what is near it", which is.
//
// The events line is the next alarm, not a calendar entry. This machine has no
// calendar -- no khal, no vdirsyncer, no local store of any kind -- and a line
// that says "Nothing for today" while reading nothing at all would be a
// decoration pretending to be a readout. Alarms are real, scripts/alarm.sh
// sets them, and services/Alarms.qml already watches them.
Item {
    id: root

    // Days either side of today. Seven columns is what the width holds at
    // this text size; an even split keeps today in the middle.
    readonly property int reach: 3

    SystemClock {
        id: clock

        // Days, not minutes: nothing here changes until the date does, and a
        // minute clock would re-evaluate the whole strip sixty times an hour
        // to arrive at the same seven numbers.
        precision: SystemClock.Minutes
    }

    readonly property var days: {
        const out = [];
        const today = clock.date;
        for (let offset = -root.reach; offset <= root.reach; offset++) {
            const d = new Date(today.getFullYear(), today.getMonth(), today.getDate() + offset);
            out.push({
                day: d.getDate(),
                weekday: d.getDay(),
                initial: Qt.formatDateTime(d, "ddd").charAt(0),
                today: offset === 0
            });
        }
        return out;
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.px(8)

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.px(10)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDateTime(clock.date, "MMM")
                font.family: Theme.uiFont
                font.pixelSize: Theme.px(20)
                font.weight: Font.Bold
                color: "#ffffff"
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.px(7)

                Repeater {
                    model: root.days

                    Column {
                        id: column

                        required property var modelData

                        // Sunday reads as the week's edge, which is the one
                        // thing a strip this short cannot show by position.
                        readonly property color tone: column.modelData.today ? Theme.accentSky
                                                    : column.modelData.weekday === 0 ? Theme.accentRed
                                                    : Qt.rgba(1, 1, 1, 0.55)

                        spacing: Theme.px(1)

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: column.modelData.initial
                            font.family: Theme.uiFont
                            font.pixelSize: Theme.px(9)
                            color: Qt.rgba(column.tone.r, column.tone.g, column.tone.b, 0.7)
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            // Two digits always, so the columns keep their
                            // spacing across the turn of a month.
                            text: column.modelData.day < 10 ? `0${column.modelData.day}` : `${column.modelData.day}`
                            font.family: Theme.uiFont
                            font.pixelSize: column.modelData.today ? Theme.px(16) : Theme.px(13)
                            font.weight: column.modelData.today ? Font.Bold : Font.Normal
                            color: column.tone
                        }
                    }
                }
            }
        }

        // What is on. One line, because that is what the surface has, and the
        // rest is a hover away on the bar's own alarm item.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.px(6)

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Alarms.ringing ? Theme.iconAlarmRing : Theme.iconAlarm
                font.family: Theme.iconFont
                font.pixelSize: Theme.px(12)
                color: Alarms.ringing ? Theme.accentRed
                                      : Alarms.hasAlarm ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(1, 1, 1, 0.30)
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    if (Alarms.ringing)
                        return Theme.shorten(Alarms.ringing.label, 24);
                    if (!Alarms.hasAlarm)
                        return "Nothing for today";
                    const next = Alarms.pending[0];
                    return next ? `${next.at}  ${Theme.shorten(next.label, 18)}` : `In ${Alarms.countdown}`;
                }
                textFormat: Text.PlainText
                font.family: Theme.uiFont
                font.pixelSize: Theme.islandSubSize
                color: Alarms.ringing ? Theme.accentRed
                                      : Alarms.hasAlarm ? Qt.rgba(1, 1, 1, 0.75) : Qt.rgba(1, 1, 1, 0.40)
            }
        }
    }
}
