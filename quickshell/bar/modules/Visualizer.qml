import QtQuick
import qs.services

// cava's levels as bars: a spread of its bands in the island (MediaChip.qml),
// as many as fit on the player card (MediaPlayer.qml).
Item {
    id: root

    property color barColor: Theme.fg
    // Off while paused: the bars stand flat in their colour (the island gives
    // its companion) rather than in the dimming meant for a quiet band.
    property bool live: true

    // The tallest a bar gets.
    property int levelHeight: Theme.px(18)

    // Fewer bars than cava's bands take bands spread across the spectrum.
    property int bars: Cava.barCount

    readonly property int barWidth: Theme.vizBarWidth
    readonly property int barSpacing: Theme.vizBarSpacing
    readonly property int maxHeight: root.levelHeight

    implicitWidth: root.bars * root.barWidth + (root.bars - 1) * root.barSpacing
    implicitHeight: root.levelHeight

    Row {
        anchors.centerIn: parent
        spacing: root.barSpacing

        Repeater {
            model: root.bars

            Rectangle {
                id: bar

                required property int index

                readonly property int band: root.bars === Cava.barCount ? bar.index
                                            : Math.floor((bar.index + 0.5) * Cava.barCount / root.bars)
                readonly property real level: Math.max(0, Math.min(100, Cava.levels[bar.band] ?? 0)) / 100

                width: root.barWidth
                height: Math.max(3, root.maxHeight * bar.level)
                radius: 1.5
                color: root.barColor
                anchors.verticalCenter: parent.verticalCenter
                opacity: root.live ? 0.65 + bar.level * 0.35 : 1

                // No Behavior on height: at cava's 30 fps an animation never
                // settles and forces repaints at the monitor rate. Smoothing
                // comes from noise_reduction in cava.conf instead.
            }
        }
    }
}
