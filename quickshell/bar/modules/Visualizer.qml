import QtQuick
import qs.services

Rectangle {
    id: root

    property color barColor: Theme.ink

    readonly property int barWidth: Theme.vizBarWidth
    readonly property int barSpacing: Theme.vizBarSpacing
    readonly property int wellPadding: Theme.vizPadding
    readonly property int maxHeight: Theme.pillHeight - Theme.px(9)

    implicitWidth: Cava.barCount * root.barWidth + (Cava.barCount - 1) * root.barSpacing + root.wellPadding * 2
    implicitHeight: Theme.pillHeight - Theme.px(7)
    radius: Theme.px(5)

    // A slightly darker well so the bars read as their own element rather than
    // as marks floating on the pill.
    color: Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b, 0.22)

    Row {
        anchors.centerIn: parent
        spacing: root.barSpacing

        Repeater {
            model: Cava.barCount

            Rectangle {
                id: bar

                required property int index

                readonly property real level: Math.max(0, Math.min(100, Cava.levels[bar.index] ?? 0)) / 100

                width: root.barWidth
                height: Math.max(3, root.maxHeight * bar.level)
                radius: 1.5
                color: root.barColor
                anchors.verticalCenter: parent.verticalCenter
                opacity: 0.65 + bar.level * 0.35

                // No Behavior on height. cava delivers 30 frames a second and a
                // 70 ms animation between them is never finished before the next
                // one starts, so every bar stays permanently in transit and the
                // whole bar repaints at the monitor's rate instead of the feed's.
                // The glide it was providing comes from cava's own smoothing now,
                // which costs no extra frames: noise_reduction in cava.conf.
            }
        }
    }
}
