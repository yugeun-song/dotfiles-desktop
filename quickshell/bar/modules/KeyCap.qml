import QtQuick
import qs.services

// One chord drawn as a single cap: modifier symbols precede the key inside
// the same cap. The key's side is an unblurred grey rectangle straight below
// the face; a darker cream would merge with the face on a dark desktop.
Item {
    id: root

    // Pre-assembled modifier symbols, e.g. "" or "\u2303\u21E7".
    property string mods: ""
    property string text: ""

    // Set when the glyph came from the icon font rather than from Inter.
    property bool iconGlyph: false
    // The whole cap at this share of the key overlay's: the cheatsheet sets
    // its caps in a list (modules/Cheatsheet.qml).
    property real size: 1

    // Hangul is drawn in the Hangul font by name: left to fontconfig's
    // fallback its taller line made the cap 5 px taller than a latin one. At
    // the latin size, though Pretendard draws a lone jamo smaller than a
    // latin capital: sized up to match, the jamo filled its cap.
    readonly property bool hangul: /[\u3131-\u318E\uAC00-\uD7A3]/.test(root.text)

    readonly property color face: Theme.beige
    readonly property color shadow: Theme.muted
    readonly property color ink: Theme.readableOn(root.face)

    // A length of the overlay's cap at this cap's size; px() itself at 1.
    function sized(base: real): int {
        return Math.max(1, Math.round(Theme.px(base) * root.size));
    }

    // How far the side shows below the face.
    readonly property int drop: root.sized(3)

    implicitWidth: Math.max(label.implicitWidth + root.sized(20), root.sized(42))
    implicitHeight: label.implicitHeight + root.sized(16) + root.drop

    // The latin line's height, given to every text label: one cap height
    // whatever the font.
    FontMetrics {
        id: latinLine

        font.family: Theme.uiFont
        font.pixelSize: root.sized(17)
        font.weight: Font.DemiBold
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height - root.drop
        radius: root.sized(8)
        color: root.shadow
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: parent.height - root.drop
        radius: root.sized(8)
        color: root.face
        border.width: 1
        border.color: Theme.bg

        Row {
            id: label

            anchors.centerIn: parent
            spacing: root.sized(2)

            // Bold, one step above the key: Inter draws modifier marks with
            // thinner strokes, so Bold beside DemiBold looks equal in weight.
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.mods !== ""
                text: root.mods
                font.family: Theme.uiFont
                font.pixelSize: root.sized(17)
                font.weight: Font.Bold
                color: root.ink
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                height: root.iconGlyph ? implicitHeight : Math.ceil(latinLine.height)
                verticalAlignment: Text.AlignVCenter
                text: root.text
                font.family: root.iconGlyph ? Theme.iconFont : root.hangul ? Theme.hangulFont : Theme.uiFont
                // Nerd Font glyphs sit small in their em box; size up to match.
                font.pixelSize: root.iconGlyph ? root.sized(20) : root.sized(17)
                font.weight: Font.DemiBold
                color: root.ink
            }
        }
    }
}
