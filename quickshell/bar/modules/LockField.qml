import QtQuick
import qs.services

// The lock screen's field (lock.qml), hyprlock.conf's input-field as drawn
// there: "Press to unlock" on no box; typing puts a dot for each character
// where the words were, round and centred; a wrong password shakes the dots
// (LockScreen moves `offset`) and then says so in the same place for two
// seconds; a lockout counts down there instead, and takes no keys meanwhile.
// The words' size follows the field's height, as hyprlock sizes them. Its
// ink is chosen per pixel against what lies under it (LockInk).
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
    readonly property int fits: Math.max(1, Math.floor(root.width / (root.dot * (1 + root.dotsSpacing))))
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
                // hyprlock's words for a field this tall, measured on its render.
                font.pixelSize: Math.max(1, root.height * 0.33)
            }

            Row {
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
        }
    }
}
