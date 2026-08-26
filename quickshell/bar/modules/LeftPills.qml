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

    // "UTC+9" rather than "KST". An abbreviation has to be recognised before it
    // says anything, and several of them are ambiguous across regions; an offset
    // is the same number everywhere. Minutes are printed only when they are not
    // zero, which is what makes Kathmandu read as UTC+5:45 and Seoul as UTC+9
    // rather than UTC+9:00.
    function zoneLabel(d) {
        const mins = -d.getTimezoneOffset();
        const sign = mins < 0 ? "-" : "+";
        const h = Math.floor(Math.abs(mins) / 60);
        const m = Math.abs(mins) % 60;
        return "UTC" + sign + h + (m === 0 ? "" : ":" + (m < 10 ? "0" : "") + m);
    }

    // Beige, and fixed. The clock is the one readout here that never changes
    // meaning, so it is the one that should never change colour: anything the
    // weather does beside it then reads as the weather having changed.
    Pill {
        icon: Theme.iconClock
        label: `${Qt.formatDateTime(clock.date, "MM-dd  HH:mm")}  ${root.zoneLabel(clock.date)}`
        fill: Theme.beige
        textColor: Theme.readableOn(fill)
        tooltip: `${Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")}
Time      ${Qt.formatDateTime(clock.date, "HH:mm")}
Week      ${Qt.formatDateTime(clock.date, "'W'ww")}
Zone      ${Qt.formatDateTime(clock.date, "t")}, ${root.zoneLabel(clock.date)}`
    }

    // The observation time comes out of the payload, so nothing here has to
    // infer one from when a line last arrived, and the pill keeps its place
    // rather than leaving: a pill that disappears reads as a change to the
    // bar, one that says it has no reading reads as a change to the feed,
    // which is what happened. An hour against a fifteen-minute poll is four
    // consecutive misses.
    Pill {
        visible: Weather.ready
        unknown: Weather.unknown || Theme.stale(Weather.asOf, 3600000)
        icon: Theme.weatherIcon(Weather.code, Weather.day)
        label: Weather.place !== "" ? `${Weather.place}, ${Weather.temp}°` : `${Weather.temp}°`
        fill: Theme.weatherColor(Weather.code, Weather.day)
        textColor: Theme.readableOn(fill)
        // A line is dropped rather than printed with its sentinel. The tooltip
        // is where a reading gets checked, so it is the last surface that may
        // say "feels -999°C". temp needs no guard: without one the whole pill
        // is unread and this tooltip is never the one shown.
        tooltip: {
            const lines = [`Sky       ${Theme.weatherText(Weather.code)}`];
            lines.push(Weather.feels > -999
                       ? `Now       ${Weather.temp}°C, feels ${Weather.feels}°C`
                       : `Now       ${Weather.temp}°C`);
            if (Weather.todayMin > -999 && Weather.todayMax > -999)
                lines.push(`Today     ${Weather.todayMin}° to ${Weather.todayMax}°C`);
            if (Weather.humidity >= 0)
                lines.push(`Humidity  ${Weather.humidity}%`);
            if (Weather.wind >= 0)
                lines.push(`Wind      ${Weather.wind} km/h`);
            if (Weather.place !== "")
                lines.push(`Location  ${Weather.place}`);
            return lines.join("\n");
        }
    }
}
