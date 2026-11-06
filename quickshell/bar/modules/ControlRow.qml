import QtQuick
import qs.services

// A row of a section opened in place, set as a dropdown's row (MenuRow): lit
// in the accent under the pointer, its check standing in for the glyph, but
// rounded to the well it sits in, a step in from the panel's own corners,
// which MenuRow's corners are not cut for.
Item {
    id: root

    property string icon: ""
    property string label: ""
    property string detail: ""
    property bool checked: false
    // A row that only tells (Wi-Fi off, no devices): faint and never lit.
    property bool quiet: false

    readonly property bool lit: hover.hovered && !root.quiet

    signal activated

    implicitHeight: Theme.controlRowHeight

    Rectangle {
        anchors.fill: parent
        visible: root.lit
        radius: Theme.controlRowRadius
        color: Theme.menuHighlight
    }

    Text {
        x: Theme.menuRowPad
        anchors.verticalCenter: parent.verticalCenter
        visible: root.checked || root.icon !== ""
        text: root.checked ? Theme.iconCheck : root.icon
        font.family: Theme.iconFont
        font.pixelSize: Theme.menuIconSize
        color: root.lit ? Theme.menuHighlightText
             : root.checked ? Theme.accentGreen
             : root.quiet ? Theme.muted : Theme.fg
    }

    // Names come from networks and devices: plain text, never markup.
    Text {
        id: detailText

        visible: root.detail !== ""
        anchors.right: parent.right
        anchors.rightMargin: Theme.menuRowPad
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.detail
        font.family: Theme.uiFont
        font.pixelSize: Theme.menuItemTextSize
        color: root.lit ? Theme.menuHighlightText : Theme.muted
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: Theme.menuRowPad + Theme.menuLeadWidth
        anchors.right: detailText.visible ? detailText.left : parent.right
        anchors.rightMargin: detailText.visible ? Theme.px(12) : Theme.menuRowPad
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.label
        font.family: Theme.uiFont
        font.pixelSize: Theme.menuItemTextSize
        color: root.lit ? Theme.menuHighlightText : root.quiet ? Theme.muted : Theme.fg
    }

    HoverHandler {
        id: hover

        enabled: !root.quiet
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.quiet
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.activated()
    }
}
