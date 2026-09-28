import QtQuick

// Reference pixels, scaled to the window. Sized to the parent divided by the
// factor and scaled by it, so the result fills the window and everything
// inside keeps the share of the screen it has on the reference output (see
// Theme.fit). Overlays lay their card out in here; a fixed-height user (the
// bar) overrides height.
Item {
    id: root

    required property real fit

    width: parent ? parent.width / root.fit : 0
    height: parent ? parent.height / root.fit : 0
    scale: root.fit
    transformOrigin: Item.TopLeft
}
