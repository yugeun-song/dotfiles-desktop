pragma ComponentBehavior: Bound
import QtQuick
import qs.services

// A group of the cheatsheet (modules/Cheatsheet.qml): its name in tracked
// capitals over the well its rows sit in (Theme's line roles: a group in the
// well, no line between rows). One chord a line, as the user asked
// (2026-11-04): an action's name once, its chords under one another at the
// right, "or" before each after the first.
Column {
    id: group

    required property var data_
    property real columnWidth: 0

    width: group.columnWidth
    spacing: Theme.px(8)

    // A cap's height, as KeyCap computes it at the list's size (its line, its
    // padding, its side): every chord's line is this tall, so a row's words
    // can sit level with its first one before any cap is laid out.
    function capSized(base: real): int {
        return Math.max(1, Math.round(Theme.px(base) * Theme.shortcutCapSize));
    }

    readonly property real capHeight: Math.ceil(capFont.height) + group.capSized(16) + group.capSized(3)

    FontMetrics {
        id: capFont

        font.family: Theme.uiFont
        font.pixelSize: group.capSized(17)
        font.weight: Font.DemiBold
    }

    Text {
        text: group.data_.name.toUpperCase()
        font.family: Theme.uiFont
        font.pixelSize: Theme.px(11)
        font.weight: Font.DemiBold
        font.letterSpacing: Theme.px(1.5)
        color: Theme.muted
    }

    Rectangle {
        width: group.columnWidth
        height: rows.implicitHeight + Theme.px(8)
        radius: Theme.px(12)
        color: Theme.surfaceWell

        Column {
            id: rows

            x: Theme.px(4)
            y: Theme.px(4)
            width: parent.width - Theme.px(8)

            Repeater {
                model: group.data_.rows

                Item {
                    id: row

                    required property var modelData
                    required property int index

                    width: rows.width
                    height: Math.max(Theme.px(38), chords.implicitHeight + Theme.px(12))

                    // Rows told apart by a fill, every other one.
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.px(8)
                        visible: row.index % 2 === 1
                        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.03)
                    }

                    // Level with the first chord, however many follow.
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.px(12)
                        anchors.right: chords.left
                        anchors.rightMargin: Theme.px(12)
                        y: chords.y + Math.round((group.capHeight - implicitHeight) / 2)
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: row.modelData.what
                        font.family: Theme.uiFont
                        font.pixelSize: Theme.menuItemTextSize
                        color: Theme.fg
                    }

                    Grid {
                        id: chords

                        anchors.right: parent.right
                        anchors.rightMargin: Theme.px(10)
                        y: Math.round((row.height - chords.implicitHeight) / 2)
                        columns: 1
                        rowSpacing: Theme.px(6)
                        horizontalItemAlignment: Grid.AlignRight

                        Repeater {
                            model: row.modelData.chords

                            Row {
                                id: alternative

                                required property var modelData
                                required property int index

                                spacing: Theme.px(8)

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: alternative.index > 0
                                    text: "or"
                                    font.family: Theme.uiFont
                                    font.pixelSize: Theme.px(11)
                                    color: Theme.surfaceFaint
                                }

                                ShortcutChord {
                                    anchors.verticalCenter: parent.verticalCenter
                                    keys: alternative.modelData
                                    to: row.modelData.to
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
