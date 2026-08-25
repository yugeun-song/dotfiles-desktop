pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// A small menu anchored to a bar item. Entries are plain objects:
//   { label, icon, detail, checked, action }
// `action` is a function called on click. The menu closes first, so an
// action that opens a window does not fight the menu for focus.
Item {
    id: root

    property var entries: []
    property Item anchorItem: root.parent
    property bool open: false
    property int minimumWidth: Theme.px(250)

    readonly property int edge: Theme.barAtBottom ? Edges.Top : Edges.Bottom
    readonly property int clearance: Theme.pillMargin + Theme.tooltipGap

    // Measured by a hidden row of Text items rather than by reusing one
    // TextMetrics in a loop. Assigning metrics.text inside a binding that
    // also reads metrics.width makes the binding re-enter itself, which Qt
    // reports as "Binding loop detected for property contentWidth".
    //
    // Only the wrapper is hidden. A Column leaves invisible children out of
    // its implicit size, so the Text items have to stay visible to count.
    // Nothing imposes a width on them, so each sizes to its own text and no
    // cycle is possible.
    readonly property int menuWidth: Math.max(root.minimumWidth, Math.ceil(measure.implicitWidth) + Theme.iconSize + Theme.px(56))

    Item {
        id: measure

        visible: false
        implicitWidth: measureRow.implicitWidth

        Column {
            id: measureRow

            Repeater {
                model: root.entries

                Text {
                    required property var modelData

                    text: modelData.separator === true ? "" : ((modelData.label ?? "") + "   " + (modelData.detail ?? ""))
                    font.family: Theme.uiFont
                    font.pixelSize: Theme.menuTextSize
                    font.weight: Font.Medium
                }
            }
        }
    }

    signal opened
    signal closed

    function toggle() {
        if (root.open) {
            root.dismiss();
        } else {
            root.open = true;
            root.opened();
        }
    }

    function dismiss() {
        if (!root.open)
            return;
        root.open = false;
        root.closed();
    }

    Loader {
        active: root.open && root.entries.length > 0

        sourceComponent: PopupWindow {
            id: popup

            // grabFocus lets the compositor take the menu away on a click
            // outside it. Following that back into `open` is what keeps the
            // pill's tooltip from staying suppressed and the next click from
            // being spent on toggling `open` back to false.
            visible: root.open
            onVisibleChanged: {
                if (!popup.visible)
                    root.dismiss();
            }

            color: "transparent"
            grabFocus: true
            implicitWidth: body.implicitWidth
            implicitHeight: body.implicitHeight

            anchor {
                window: root.QsWindow.window
                item: root.anchorItem
                rect.x: 0
                rect.y: -root.clearance
                rect.width: root.anchorItem?.width ?? 0
                rect.height: (root.anchorItem?.height ?? 0) + root.clearance * 2
                edges: root.edge
                gravity: root.edge
            }

            Rectangle {
                id: body

                implicitWidth: root.menuWidth
                implicitHeight: column.implicitHeight + Theme.px(14)
                radius: Theme.tooltipRadius
                color: Theme.bgAlt

                Column {
                    id: column

                    anchors.centerIn: parent
                    width: root.menuWidth - Theme.px(14)
                    spacing: 0

                    Repeater {
                        model: root.entries

                        Rectangle {
                            id: row

                            required property var modelData

                            readonly property bool isSeparator: row.modelData.separator === true

                            width: root.menuWidth - Theme.px(14)
                            height: row.isSeparator ? Theme.px(11) : Theme.px(38)
                            radius: Theme.px(9)
                            color: hover.hovered && !row.isSeparator ? Qt.rgba(1, 1, 1, 0.09) : "transparent"

                            Rectangle {
                                visible: row.isSeparator
                                anchors.centerIn: parent
                                width: parent.width - Theme.px(10)
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.1)
                            }

                            // Three items on one line, anchored rather than
                            // laid out in a Row. The name used to sit in a Row
                            // that spanned the full width while the command
                            // hung off the right edge as a sibling, so a long
                            // name simply ran underneath it. Here the command
                            // owns the right, the icon owns the left, and the
                            // name gets whatever is left over and is cut short
                            // when that is not enough.
                            Text {
                                id: rowIcon

                                visible: !row.isSeparator
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.px(12)
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.iconSize
                                horizontalAlignment: Text.AlignHCenter
                                text: row.modelData.checked === true ? Theme.iconCheck : (row.modelData.icon ?? "")
                                font.family: Theme.iconFont
                                font.pixelSize: Theme.px(17)
                                color: row.modelData.checked === true ? Theme.accentGreen : Theme.muted
                            }

                            Text {
                                id: rowDetail

                                visible: !row.isSeparator && (row.modelData.detail ?? "") !== ""
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.px(13)
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.detail ?? ""
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.px(12)
                                color: Theme.muted
                            }

                            Text {
                                visible: !row.isSeparator
                                anchors.left: rowIcon.right
                                anchors.leftMargin: Theme.px(10)
                                anchors.right: rowDetail.visible ? rowDetail.left : parent.right
                                anchors.rightMargin: Theme.px(13)
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: row.modelData.label ?? ""
                                font.family: Theme.uiFont
                                font.pixelSize: Theme.menuTextSize
                                font.weight: Font.Medium
                                color: Theme.fg
                            }

                            HoverHandler {
                                id: hover

                                enabled: !row.isSeparator
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !row.isSeparator
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    const act = row.modelData.action;
                                    root.dismiss();
                                    if (typeof act === "function")
                                        act();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
