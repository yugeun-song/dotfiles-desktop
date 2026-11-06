import QtQuick
import qs.services

// One of the lock screen's labels as hyprlock.conf places it (LockScreen):
// by its middle, or by its top at the top, at the spec's point size; its
// ink chosen per pixel against what lies under it, with a soft halo of the
// other tone where that still reads poorly (LockInk; the user, 2026-11-06).
// The halo's room is padding round the words, inside the layer: a layer's
// sourceRect larger than its item drew the words squeezed. The layer is
// sampled smoothly and the label set on the screen's own pixels: a layer is
// drawn at the screen's scale but sampled nearest by default, and laid
// between two pixels its strokes came out uneven, jagged (the user,
// 2026-11-06: aliased, low resolution; measured on the 1.5 panel).
Text {
    id: label

    required property var screenRoot
    property var block: ({})
    readonly property real room: label.screenRoot.whole(label.screenRoot.tall(8))

    // FreeType's own rasterising, as hyprlock's cairo draws: Qt's default
    // (distance fields) drew the same text a little thinner.
    renderType: Text.NativeRendering
    padding: label.room
    x: label.screenRoot.crisp(label.screenRoot.xOf(label.block, label.implicitWidth - 2 * label.room) - label.room)
    y: label.screenRoot.crisp(label.screenRoot.yOf(label.block, label.implicitHeight - 2 * label.room) - label.room)
    color: Theme.beige
    font.family: label.screenRoot.family(label.block?.font_family ?? "")
    font.weight: label.screenRoot.weight(label.block?.font_family ?? "")
    font.pixelSize: Math.max(1, label.screenRoot.points(label.block?.font_size ?? 16))

    layer.enabled: true
    layer.smooth: true
    layer.effect: LockInk {
        target: label
        under: label.screenRoot.under
        screenItem: label.screenRoot
        haloSize: label.screenRoot.tall(6)
    }
}
