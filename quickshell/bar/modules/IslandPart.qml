import QtQuick
import qs.services

// One part of the island's row (MediaChip.qml): what plays, a call, OBS, a
// share, or a system event. It opens on the island's spring and shuts on its
// swap curve, uncovered from its left, what it holds fading in once well
// open; laid out at its full width throughout, so nothing in it reflows.
Item {
    id: root

    // Wanted in the island, as MediaChip decides from the room it has.
    property bool wanted: false
    // How far open: 0 shut, 1 open, past 1 for a moment as it opens.
    property real open: 0
    // Its width open.
    property int full: 0
    readonly property int span: Math.round(root.full * root.open)
    // Going, or gone halfway: a part coming in meanwhile takes its curve.
    readonly property bool closing: root.open > 0 && !root.wanted
    // Width past what it holds, for a part alone: what plays to the music
    // island's least (MediaChip.musicLeastRow), a call, OBS or a share to the
    // one width (oneRow); an event gets none. Asked for, and as it is now,
    // eased while the part shows so a part coming or going widens nothing at
    // once.
    property int spread: 0
    property real extra: 0

    onSpreadChanged: {
        if (root.open > 0.01) {
            spreading.to = root.spread;
            spreading.restart();
        } else {
            spreading.stop();
            root.extra = root.spread;
        }
    }

    default property alias content: holder.data

    // The pill's own height: the row it sits in takes its height from its
    // parts, so a part sized by that row came out with none.
    width: root.span
    height: Theme.islandHeight
    visible: root.width > 0
    clip: true

    // Set where it should be at once, as when the island opens from nothing
    // and its own opening carries the parts.
    function snap(): void {
        opening.stop();
        shutting.stop();
        spreading.stop();
        root.open = root.wanted ? 1 : 0;
        root.extra = root.spread;
    }

    // A part coming in as another goes out takes the going one's curve: on
    // the spring it grew while the other shrank, and the island widened
    // before it narrowed (measured).
    function ease(swap: bool): void {
        if (opening.running)
            return;
        opening.duration = swap ? Theme.islandShutMs : Theme.islandOpenMs;
        opening.easing.type = swap ? Easing.InOutCubic : Easing.OutBack;
    }

    // Opened or shut from wherever the other left it.
    function move(): void {
        const go = root.wanted ? opening : shutting;
        (root.wanted ? shutting : opening).stop();
        if (!go.running && root.open !== go.to)
            go.start();
    }

    NumberAnimation {
        id: opening

        target: root
        property: "open"
        to: 1
        duration: Theme.islandOpenMs
        easing.type: Easing.OutBack
        easing.overshoot: Theme.islandOvershoot
    }

    NumberAnimation {
        id: spreading

        target: root
        property: "extra"
        duration: Theme.islandShutMs
        easing.type: Easing.InOutCubic
    }

    NumberAnimation {
        id: shutting

        target: root
        property: "open"
        to: 0
        duration: Theme.islandShutMs
        easing.type: Easing.InOutCubic
    }

    Item {
        id: holder

        width: root.full
        height: root.height
        opacity: Math.max(0, Math.min(1, (root.open - 0.4) / 0.5))
    }
}
