import QtQuick
import qs.services

// A pill button, first for the wallpaper picker's foot
// (modules/WallpaperPicker.qml): the raised face, or the accent for the one
// that keeps a choice; faint while there is nothing to do. A file, not an
// inline component: instantiated with a handler of its signal, the inline
// one would not load ("Pill is not a type", quickshell 0.3.2), as the
// cheatsheet's group had not.
Rectangle {
    id: pill

    required property string label
    property string icon: ""
    property bool primary: false
    property bool usable: true

    signal clicked

    width: pillRow.implicitWidth + Theme.px(28)
    height: Theme.controlButtonSize
    radius: height / 2
    opacity: pill.usable ? 1 : 0.45
    color: pill.primary ? (pillArea.containsMouse && pill.usable ? Qt.lighter(Theme.menuHighlight, 1.08) : Theme.menuHighlight)
                        : (pillArea.containsMouse && pill.usable ? Theme.surfaceRaisedHover : Theme.surfaceRaised)

    Row {
        id: pillRow

        anchors.centerIn: parent
        spacing: Theme.px(6)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: pill.icon !== ""
            text: pill.icon
            font.family: Theme.iconFont
            font.pixelSize: Theme.menuIconSize
            color: pill.primary ? Theme.menuHighlightText : Theme.fg
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.label
            font.family: Theme.uiFont
            font.pixelSize: Theme.menuItemTextSize
            font.weight: pill.primary ? Font.DemiBold : Font.Normal
            color: pill.primary ? Theme.menuHighlightText : Theme.fg
        }
    }

    MouseArea {
        id: pillArea

        anchors.fill: parent
        enabled: pill.usable
        hoverEnabled: true
        cursorShape: pill.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: pill.clicked()
    }
}
