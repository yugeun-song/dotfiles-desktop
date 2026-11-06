import QtQuick
import qs.services

// One toggle of the control centre, drawn as GNOME's quick settings draw one
// (the user's reference, 2026-11-04): a pill with a glyph, a title and its
// state under it, filled in the accent while on, since a state is a fill on
// a small surface (Theme's line roles). A toggle with more behind it ends in
// a chevron, a target of its own: the body switches, the chevron opens the
// section in place. One with nothing to switch (the power mode) opens it
// from either.
Item {
    id: root

    property string icon: ""
    property string title: ""
    property string detail: ""
    property bool active: false
    property bool expandable: false
    property bool expanded: false
    property bool opensOnly: false

    signal toggled
    signal expandRequested

    implicitHeight: Theme.controlTileHeight

    readonly property bool hovered: body.containsMouse || chevron.containsMouse
    readonly property color ink: root.active ? Theme.menuHighlightText : Theme.fg
    readonly property color faint: root.active ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7) : Theme.surfaceDim

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.active ? (root.hovered ? Qt.lighter(Theme.menuHighlight, 1.08) : Theme.menuHighlight)
                           : (root.hovered ? Theme.surfaceRaisedHover : Theme.surfaceRaised)

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
    }

    Text {
        id: glyph

        anchors.left: parent.left
        anchors.leftMargin: Math.round(root.height * 0.32)
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        font.family: Theme.iconFont
        font.pixelSize: Theme.menuIconSize
        color: root.ink
    }

    Column {
        anchors.left: glyph.right
        anchors.leftMargin: Theme.px(10)
        anchors.right: root.expandable ? chevron.left : parent.right
        anchors.rightMargin: root.expandable ? 0 : Theme.px(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.px(1)

        Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.title
            font.family: Theme.uiFont
            font.pixelSize: Theme.controlTitleSize
            font.weight: Font.Medium
            color: root.ink
        }

        // A network's or a device's name: never markup.
        Text {
            width: parent.width
            visible: text !== ""
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: root.detail
            font.family: Theme.uiFont
            font.pixelSize: Theme.controlStateSize
            color: root.faint
        }
    }

    MouseArea {
        id: body

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: root.expandable ? chevron.left : parent.right
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.opensOnly ? root.expandRequested() : root.toggled()
    }

    // The chevron's own target at the pill's end, lit apart from the body.
    MouseArea {
        id: chevron

        visible: root.expandable
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.expandable ? root.height : 0
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expandRequested()

        Rectangle {
            anchors.centerIn: parent
            width: parent.height - Theme.px(10)
            height: width
            radius: width / 2
            visible: chevron.containsMouse
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.12)
        }

        Text {
            anchors.centerIn: parent
            text: Theme.iconChevron
            font.family: Theme.iconFont
            font.pixelSize: Theme.menuIconSize
            color: root.ink
            // Down while its section is open, as GNOME turns it.
            rotation: root.expanded ? 90 : 0

            Behavior on rotation {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
