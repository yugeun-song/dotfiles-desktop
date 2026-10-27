import QtQuick
import qs.services

// One row of a dropdown menu (PopupMenu, BadgePicker's Automatic), as the
// menus the user sent set one (2026-10-27; sizes in Theme.menu*): its
// content Theme.menuRowPad in from both sides, the text centred between top
// and bottom; lit in the accent under the pointer, all of it then in the ink.
// A separator is a hairline reaching a little past the content.
Item {
    id: root

    property string label: ""
    property string icon: ""
    property string detail: ""
    property bool checked: false
    property bool separator: false
    // The menu's, not the row's: an icon or a check box on any row gives
    // every row the leading column, so the labels line up.
    property bool lead: false
    // PopupMenu's rows set Theme.menuItemTextSize.
    property int textSize: Theme.menuTextSize

    readonly property bool lit: hover.hovered && !root.separator

    signal activated

    implicitHeight: root.separator ? Theme.menuSeparatorHeight : Theme.menuRowHeight

    Rectangle {
        anchors.fill: parent
        visible: root.lit
        radius: Theme.menuRowRadius
        color: Theme.menuHighlight
    }

    // Theme.menuRuleInset is from the menu's edge, where this row is not.
    Rectangle {
        visible: root.separator
        x: Theme.menuRuleInset - Theme.menuPad
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 2 * x
        height: Theme.surfaceBorder
        color: Theme.surfaceLine
    }

    // A check stands in for the icon, so a checked row keeps its place.
    Text {
        visible: !root.separator && (root.checked || root.icon !== "")
        x: Theme.menuRowPad
        anchors.verticalCenter: parent.verticalCenter
        text: root.checked ? Theme.iconCheck : root.icon
        font.family: Theme.iconFont
        font.pixelSize: Theme.menuIconSize
        color: root.lit ? Theme.menuHighlightText : root.checked ? Theme.accentGreen : Theme.fg
    }

    Text {
        id: detailText

        visible: !root.separator && root.detail !== ""
        anchors.right: parent.right
        anchors.rightMargin: Theme.menuRowPad
        anchors.verticalCenter: parent.verticalCenter
        // Callers pass strings through (an input method's engine name); never markup.
        textFormat: Text.PlainText
        text: root.detail
        font.family: Theme.uiFont
        font.pixelSize: root.textSize
        color: root.lit ? Theme.menuHighlightText : Theme.muted
    }

    // Anchored, not a Row: the label elides before the detail instead of
    // running under it, should the menu be narrower than its columns.
    Text {
        visible: !root.separator
        anchors.left: parent.left
        anchors.leftMargin: Theme.menuRowPad + (root.lead ? Theme.menuLeadWidth : 0)
        anchors.right: detailText.visible ? detailText.left : parent.right
        anchors.rightMargin: detailText.visible ? Theme.menuDetailGap : Theme.menuRowPad
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: root.label
        font.family: Theme.uiFont
        font.pixelSize: root.textSize
        color: root.lit ? Theme.menuHighlightText : Theme.fg
    }

    HoverHandler {
        id: hover

        enabled: !root.separator
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.separator
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.activated()
    }
}
