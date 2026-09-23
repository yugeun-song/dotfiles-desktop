import QtQuick
import qs.services

Rectangle {
    id: root

    property color barColor: Theme.ink

    // Settable: drawn both in the bar's media chip and on the player card.
    property int wellHeight: Theme.pillHeight - Theme.px(7)

    readonly property int barWidth: Theme.vizBarWidth
    readonly property int barSpacing: Theme.vizBarSpacing
    readonly property int wellPadding: Theme.vizPadding
    readonly property int maxHeight: root.wellHeight - Theme.px(2)

    implicitWidth: Cava.barCount * root.barWidth + (Cava.barCount - 1) * root.barSpacing + root.wellPadding * 2
    implicitHeight: root.wellHeight
    radius: Theme.px(5)

    // A backing well so the bars read as one element among the bar's words;
    // off on the player card, where it would box nothing.
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

                // No Behavior on height: at cava's 30 fps an animation never
                // settles and forces repaints at the monitor rate. Smoothing
                // comes from noise_reduction in cava.conf instead.
            }
        }
    }
}
