import QtQuick
import qs.services

// A glyph of the lock set by its ink's middle, not its box's: icons sit
// unevenly in their em boxes. The notch's lock and marks (LockNotch) and the
// see-through lock's prompt (LockGlass) place theirs by it. A file of its
// own, not an inline component of LockNotch, whose bound components no other
// file may make.
Text {
    id: glyph

    property real cx: 0
    property real cy: 0
    property string family: Theme.iconFont
    property real size: 16
    readonly property real inkWidth: ink.tightBoundingRect.width

    x: glyph.cx - (ink.tightBoundingRect.x + ink.tightBoundingRect.width / 2)
    y: glyph.cy - (glyph.baselineOffset + ink.tightBoundingRect.y + ink.tightBoundingRect.height / 2)
    textFormat: Text.PlainText
    font.family: glyph.family
    font.pixelSize: Math.max(1, glyph.size)

    TextMetrics {
        id: ink

        font: glyph.font
        text: glyph.text
    }
}
