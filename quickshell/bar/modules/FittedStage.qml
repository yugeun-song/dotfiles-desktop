import QtQuick

// Reference pixels, scaled to the window: sized to the parent over the factor
// and scaled by it, so it fills the window and its content keeps its share of
// the screen (Theme.fit). Overlays lay their card out in here; the bar, of
// fixed height, overrides height.
Item {
    id: root

    required property real fit

    width: parent ? parent.width / root.fit : 0
    height: parent ? parent.height / root.fit : 0
    scale: root.fit
    transformOrigin: Item.TopLeft
}
