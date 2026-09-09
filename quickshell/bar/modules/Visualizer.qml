import QtQuick
import qs.services

Rectangle {
    id: root

    property color barColor: Theme.ink

    // The well's height, settable because this is drawn on two surfaces of
    // very different sizes: a pill, which it was written for, and the island's
    // collapsed tab, which is smaller than a pill and had the well filling it
    // edge to edge with nothing left as margin.
    property int wellHeight: Theme.pillHeight - Theme.px(7)

    readonly property int barWidth: Theme.vizBarWidth
    readonly property int barSpacing: Theme.vizBarSpacing
    readonly property int wellPadding: Theme.vizPadding
    readonly property int maxHeight: root.wellHeight - Theme.px(2)

    implicitWidth: Cava.barCount * root.barWidth + (Cava.barCount - 1) * root.barSpacing + root.wellPadding * 2
    implicitHeight: root.wellHeight
    radius: Theme.px(5)

    // A well behind the bars, so they read as their own element rather than as
    // marks floating on whatever is under them. Wanted on the bar, where the
    // meter sits among words; not on the player card, where it is the only
    // thing in its corner and the well would be a box around nothing.
    property bool showWell: true

    color: root.showWell ? Qt.rgba(root.barColor.r, root.barColor.g, root.barColor.b, 0.22)
                         : "transparent"

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
