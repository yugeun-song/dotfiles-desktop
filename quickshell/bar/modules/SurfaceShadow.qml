import QtQuick
import QtQuick.Effects
import qs.services

// The shadow of a surface that floats over what lies behind it (Theme.shadowOf;
// the user, 2026-11-11, after a desktop they named): laid under `target`, a
// sibling before it, as large and as round as it, following it as it moves,
// scales and fades. RectangularShadow draws it in one pass, with no texture of
// its own. A surface that lies flat on the screen (the bar, the pill in it, the
// desktop widgets, the lock screen) has none.
RectangularShadow {
    id: root

    required property Item target
    // menu, toast, panel or dialog: the higher a surface stands, the deeper.
    property string kind: "panel"
    readonly property var role: Theme.shadowOf(root.kind)

    x: root.target.x
    y: root.target.y
    width: root.target.width
    height: root.target.height
    scale: root.target.scale
    transformOrigin: root.target.transformOrigin
    radius: root.target.radius ?? 0
    opacity: root.target.opacity
    visible: root.target.visible && root.target.opacity > 0
    blur: root.role.blur
    offset: Qt.vector2d(0, root.role.offset)
    color: root.role.color
}
