import QtQuick
import Quickshell
import qs.services

// The pills that sit between the badge and the workspaces.
//
// Time and weather read as "where and when am I" rather than as machine state,
// which is what the right-hand group is for, so they live at the other end of
// the bar. Keeping them in a Row of their own means Bar.qml still reads as
// three sections rather than a list of individual widgets.
Row {
    id: root

    spacing: Theme.gap

    // Wakes on the minute rather than on a free-running interval. A Timer at
    // 1000 ms would tick sixty times for every visible change and drift off the
    // minute boundary, so the displayed minute would turn over at an arbitrary
    // point inside it.
    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Pill {
        icon: Theme.iconClock
        label: Qt.formatDateTime(clock.date, "MM-dd  HH:mm")
        fill: Theme.accentSky
        tooltip: `${Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")}
Time      ${Qt.formatDateTime(clock.date, "HH:mm")}
Week      ${Qt.formatDateTime(clock.date, "'W'ww")}
Zone      ${Qt.formatDateTime(clock.date, "t")}`
    }

    // The reading carries no observation time and Weather.data is never
    // cleared, so a feed that stopped arriving would keep reading as the
    // current sky. The pill leaves when nothing new has come in for an hour.
    Timer {
        id: weatherFresh

        interval: 3600000
        running: true
    }

    Connections {
        target: Weather

        function onDataChanged() {
            weatherFresh.restart();
        }
    }

    Pill {
        visible: Weather.ready && weatherFresh.running
        icon: Theme.weatherIcon(Weather.code, Weather.day)
        label: Weather.place !== "" ? `${Weather.place}, ${Weather.temp}°` : `${Weather.temp}°`
        fill: Theme.accentSky
        tooltip: `Sky       ${Theme.weatherText(Weather.code)}
Now       ${Weather.temp}°C, feels ${Weather.feels}°C
Today     ${Weather.todayMin}° to ${Weather.todayMax}°C
Humidity  ${Weather.humidity}%
Wind      ${Weather.wind} km/h
Location  ${Weather.place}`
    }
}
