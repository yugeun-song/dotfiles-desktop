import QtQuick
import qs.services

// What is drawn on the grown island and the lock's notch, after the fill
// they take (Appearance.islandFill, lock-colours.py's $island_fill). On
// black, the island's own colours (Theme.island*). On the cream they take
// over a ground too dark for black (the user, 2026-11-11), the same roles
// turned over: text and glyphs in the bar's dark, the greys as far from the
// cream as theirs are from black, a colour deepened until it reads as a
// glyph must (3:1), white as the dark text, and a colour's quieter companion
// nearer the cream, as on black it is nearer black.
QtObject {
    id: root

    property color ground: Theme.islandColor
    readonly property bool light: Appearance.luminance(root.ground) > Appearance.crossover

    readonly property color text: root.light ? Theme.islandCreamInk : Theme.islandText
    // About 5:1 on the cream, a second line's grey.
    readonly property color subtext: root.light ? Appearance.mix(root.ground, root.text, 0.64) : Theme.islandSubtext
    readonly property color fill: root.light ? Appearance.mix(root.ground, root.text, 0.12) : Theme.islandFill
    readonly property color fillHigh: root.light ? Appearance.mix(root.ground, root.text, 0.24) : Theme.islandFillHigh

    function accent(c: color): color {
        if (!root.light)
            return c;
        if (Appearance.contrast(c, Theme.islandText) < 1.1)
            return root.text;
        return Appearance.readable(c, root.ground, 3);
    }

    function dim(c: color): color {
        return root.light ? Appearance.mix(root.ground, c, Theme.islandDimFactor) : Theme.islandDim(c);
    }

    function tint(c: color): color {
        return root.light ? Appearance.mix(root.ground, c, Theme.islandTintFactor) : Theme.islandTint(c);
    }
}
