import QtQuick
import qs.services

// The lock screen's field (lock.qml), hyprlock.conf's input-field as drawn
// there: "Press to unlock" on no box; typing puts a dot for each character
// where the words were, round and centred; a wrong password shakes the dots
// (LockScreen moves `offset`) and then says so in the same place for two
// seconds; a lockout counts down there instead, and takes no keys meanwhile.
// While Caps Lock is on, its mark stands at the trailing end. The words'
// size follows the field's height, as hyprlock sizes them. Its ink is chosen
// per pixel against what lies under it (LockInk).
Item {
    id: root

    required property var lockRoot
    required property var under
    required property Item screenItem
    // Room round the words for the shake and the halo.
    property real room: 24
    property string fontFamily: Theme.uiFont
    property int fontWeight: Font.DemiBold
    property string placeholder: "Press to unlock"
    // A dot's side as a share of the field's height, and the gap between
    // dots as a share of a dot: hyprlock's dots_size and dots_spacing.
    property real dotsSize: 0.13
    property real dotsSpacing: 0.35
    readonly property alias offset: shift

    readonly property real dot: Math.max(2, root.height * root.dotsSize)
    // hyprlock's words for a field this tall, measured on its render.
    readonly property real wordsSize: Math.max(1, root.height * 0.33)

    // Caps Lock's mark (the user, 2026-11-11, after a desktop's password
    // field): a filled arrow over a bar (capslock.svg), a little taller than
    // the words' capitals, at the field's trailing end. With no box to end
    // at, the end is the placeholder's: the mark stays put as dots come, as
    // in a box, and steps out only past words or dots wider than that. Its
    // room is kept off the dots whether it shows or not, so Caps Lock never
    // changes how many dots there are.
    readonly property real capsH: root.screenItem.crisp(root.wordsSize * 0.8)
    readonly property real capsW: root.screenItem.crisp(root.capsH * 18 / 19.6)
    readonly property real capsGap: root.wordsSize * 0.5

    readonly property int fits: Math.max(1, Math.floor((root.width - 2 * (root.capsGap + root.capsW)) / (root.dot * (1 + root.dotsSpacing))))
    readonly property int count: Math.min(root.fits, root.lockRoot.shownDots)
    // The dots of a password handed over first, through the check and the
    // shake; then what the check said, a lockout's countdown before it.
    readonly property string words: root.lockRoot.heldDots > 0 ? ""
        : root.lockRoot.lockoutText !== "" ? root.lockRoot.lockoutText
        : root.lockRoot.failText !== "" ? root.lockRoot.failText
        : root.count === 0 ? root.placeholder : ""

    // The ink's layer, with room round the field for the shake and the
    // halo (a layer's sourceRect larger than its item drew it squeezed),
    // sampled smoothly (LockLabel says why).
    Item {
        id: inked

        x: -root.room
        y: -root.room
        width: root.width + 2 * root.room
        height: root.height + 2 * root.room

        layer.enabled: true
        layer.smooth: true
        layer.effect: LockInk {
            target: inked
            under: root.under
            screenItem: root.screenItem
            haloSize: Math.max(3, root.height * 0.08)
        }

        Item {
            x: root.room
            y: root.room
            width: root.width
            height: root.height

            transform: Translate {
                id: shift
            }

            Text {
                id: wordsText

                anchors.centerIn: parent
                visible: root.words !== ""
                width: root.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                text: root.words
                color: Theme.beige
                font.family: root.fontFamily
                font.weight: root.fontWeight
                font.pixelSize: root.wordsSize
            }

            Row {
                id: dotsRow

                anchors.centerIn: parent
                visible: root.words === ""
                spacing: root.dot * root.dotsSpacing

                Repeater {
                    model: root.count

                    Rectangle {
                        width: root.dot
                        height: root.dot
                        radius: root.dot / 2
                        color: Theme.beige
                        // A check under way: the dots quieter until PAM answers.
                        opacity: root.lockRoot.checking ? 0.55 : 1
                    }
                }
            }

            // Its middle on the field's, as the dots' and the words'
            // capitals'; on the screen's pixels, as everything inked here.
            Image {
                id: capsMark

                readonly property real reach: Math.max(placeholderInk.advanceWidth,
                                                       root.words !== "" ? wordsText.implicitWidth : dotsRow.width)

                x: root.screenItem.crisp(Math.min(root.width - root.capsW, (root.width + capsMark.reach) / 2 + root.capsGap))
                y: root.screenItem.crisp((root.height - root.capsH) / 2)
                width: root.capsW
                height: root.capsH
                source: "capslock.svg"
                // In item pixels: Qt draws it at the screen's scale itself.
                sourceSize: Qt.size(root.capsW, root.capsH)
                smooth: true
                opacity: root.lockRoot.capsLock ? 1 : 0
                visible: capsMark.opacity > 0

                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    TextMetrics {
        id: placeholderInk

        font: wordsText.font
        text: root.placeholder
    }
}
