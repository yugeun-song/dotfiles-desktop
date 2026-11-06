import QtQuick

// A surface of the lock screen, its pane and its edge coloured per pixel
// from what lies under it (LockInk's mode 1): drawn here as two masks in one
// layer, the pane in red and the edge in green, which the shader takes
// apart. The card and the power panel lie on these, so no surface goes the
// colour of its ground (the user, 2026-11-06).
Item {
    id: root

    required property var under
    required property Item screenItem
    property real radius: 0
    property real edgeWidth: 1
    // Bumped by an owner that moves this without its own x or y changing.
    property int tick: 0

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "#ff0000"
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: root.edgeWidth
        border.color: "#00ff00"
    }

    // Sampled smoothly, as LockLabel's.
    layer.enabled: true
    layer.smooth: true
    layer.effect: LockInk {
        target: root
        tick: root.tick
        under: root.under
        screenItem: root.screenItem
        mode: 1
    }
}
