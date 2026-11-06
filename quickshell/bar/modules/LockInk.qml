import QtQuick
import qs.services

// An element of the lock screen recoloured per pixel against what lies under
// it (shaders/lockink.frag; the user, 2026-11-06): set as the element's
// layer.effect, with the element as `target`. The ground is the screen's
// backdrop as LockScreen probes it, a small live copy (`under`), so a video
// recolours the ink frame by frame. A halo needs room round the element
// inside the element itself (padding): a layer's sourceRect larger than its
// item draws squeezed into the item. `mode` 1 takes the layer as a
// surface's two masks (LockSurface).
ShaderEffect {
    id: root

    // The layer's picture of the element, which the layer sets.
    property var source
    required property Item target
    required property var under
    required property Item screenItem
    // How far a halo reaches, in pixels; 0 draws none.
    property real haloSize: 0
    property real mode: 0
    property color beige: Theme.beige
    // Bumped by an owner whose own move mapToItem cannot be watched for.
    property int tick: 0

    // Where the layer lies on the screen, in its 0..1 space: both corners
    // mapped, so a scaled or moved element still finds its ground. Read
    // again as the element or its parent moves, as the screen's way in
    // zooms (LockScreen.enter), and at the owner's tick.
    readonly property rect area: {
        void [root.target.x, root.target.y, root.target.width, root.target.height, root.target.scale,
              root.target.parent?.x, root.target.parent?.y, root.target.parent?.scale, root.tick,
              root.screenItem.enter];
        const w = Math.max(1, root.screenItem.width);
        const h = Math.max(1, root.screenItem.height);
        const a = root.target.mapToItem(root.screenItem, 0, 0);
        const b = root.target.mapToItem(root.screenItem, root.target.width, root.target.height);
        return Qt.rect(a.x / w, a.y / h, (b.x - a.x) / w, (b.y - a.y) / h);
    }
    readonly property size px: Qt.size(1 / Math.max(1, root.target.width), 1 / Math.max(1, root.target.height))

    fragmentShader: Qt.resolvedUrl("../shaders/lockink.frag.qsb")
}
