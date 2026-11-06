import QtQuick
import Quickshell
import qs.services

// The clock widget, in the reference pixels WidgetCard scales: the time alone
// and huge (HeroText), hours over minutes in the square, one line in the wide
// card, with only the padding around it (the user, 2026-11-05: 24 or 12 hours
// the only choice, the inside filled tight). On 12 hours AM or PM stands
// small at the right end of the last line, on its baseline: the box's bottom
// right corner in the square (the user, 2026-11-05), the figures moved over
// by its width so the two never touch. It ticks by the minute and only while
// its window exists: a covered desktop keeps no clock running.
Item {
    id: root

    required property string size
    required property var options

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    function pad(n: int): string {
        return n < 10 ? `0${n}` : `${n}`;
    }

    readonly property bool stacked: root.size === "small"
    readonly property bool hours24: root.options.hours24 !== false
    readonly property int hour: clock.date.getHours()
    // Worked out here: Qt's "hh" is the 12-hour form only beside "AP", and the
    // marker's words follow the locale.
    readonly property string hourText: root.pad(root.hours24 ? root.hour : (root.hour + 11) % 12 + 1)
    readonly property string minuteText: root.pad(clock.date.getMinutes())
    readonly property string meridiem: root.hours24 ? "" : (root.hour < 12 ? "AM" : "PM")
    readonly property real innerW: root.width - Theme.widgetPad * 2
    readonly property real innerH: root.height - Theme.widgetPad * 2
    readonly property real rowGap: 8
    // Room for the wider of the two markers, so the figures hold still from
    // noon to noon.
    readonly property real markerRoom: root.hours24 ? 0 : markerProbe.advanceWidth + 6
    // The figures' share of the box they stand in, centred in it: the whole
    // was a little much (the user, 2026-11-05).
    readonly property real share: 0.88
    readonly property real regionW: root.innerW - root.markerRoom
    readonly property real areaW: root.regionW * root.share
    readonly property real areaH: root.innerH * root.share
    readonly property real areaX: Theme.widgetPad + (root.regionW - root.areaW) / 2
    readonly property real areaY: Theme.widgetPad + (root.innerH - root.areaH) / 2
    readonly property real rowH: (root.areaH - root.rowGap) / 2

    TextMetrics {
        id: markerProbe

        font: marker.font
        text: "AM"
    }

    HeroText {
        id: hours

        x: root.areaX
        y: root.areaY
        width: root.areaW
        height: root.stacked ? root.rowH : root.areaH
        text: root.stacked ? root.hourText : `${root.hourText}:${root.minuteText}`
        probe: root.stacked ? "00" : "00:00"
        horizontal: "center"
        // The two rows meet at the gap, whichever of height or width set
        // their size.
        vertical: root.stacked ? "bottom" : "center"
        tabular: true
    }

    HeroText {
        id: minutes

        visible: root.stacked
        x: root.areaX
        y: root.areaY + root.rowH + root.rowGap
        width: root.areaW
        height: root.rowH
        text: root.minuteText
        probe: "00"
        horizontal: "center"
        vertical: "top"
        tabular: true
    }

    Text {
        id: marker

        readonly property HeroText line: root.stacked ? minutes : hours

        visible: root.meridiem !== ""
        anchors.right: parent.right
        anchors.rightMargin: Theme.widgetPad
        anchors.baseline: parent.top
        anchors.baselineOffset: marker.line.y + marker.line.figureBaseline
        text: root.meridiem
        font.family: Theme.uiFont
        font.pixelSize: Theme.widgetTitleSize
        font.weight: Font.DemiBold
        font.letterSpacing: 0.6
        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.72)
    }
}
