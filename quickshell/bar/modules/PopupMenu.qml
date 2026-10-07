pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// Menu anchored to a bar item. Entries: { label, icon, detail, checked,
// action } or { separator: true }. The menu closes before `action` runs, so a
// window it opens does not fight the menu for focus.
Item {
    id: root

    property var entries: []
    property Item anchorItem: root.parent
    property bool open: false
    property int minimumWidth: Theme.px(250)

    readonly property int edge: Theme.barAtBottom ? Edges.Top : Edges.Bottom
    readonly property int clearance: Theme.pillMargin + Theme.tooltipGap

    // Measured with hidden Text items, not a TextMetrics reused in a loop (that
    // is a binding loop). Only the wrapper is hidden: a Column ignores
    // invisible children in its implicit size.
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

                    // Callers pass strings through (an input method's engine name); never markup.
                    textFormat: Text.PlainText
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

            // grabFocus lets the compositor close this on an outside click;
            // sync that back into `open` or the next click only resets it.
            visible: root.open
            onVisibleChanged: {
                if (!popup.visible)
                    root.dismiss();
            }

            // The menu's share of the bar's screen, as on the reference output.
            readonly property real fit: Theme.fit(root.QsWindow.window?.screen)

            color: "transparent"
            grabFocus: true
            implicitWidth: Math.round(body.implicitWidth * popup.fit)
            implicitHeight: Math.round(body.implicitHeight * popup.fit)

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

                scale: popup.fit
                transformOrigin: Item.TopLeft
                implicitWidth: root.menuWidth
                implicitHeight: column.implicitHeight + Theme.px(14)
                radius: Theme.tooltipRadius
                color: Theme.surfaceBg
                border.width: Theme.surfaceBorder
                border.color: Theme.surfaceLine

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

                            // Anchored, not a Row: icon left, detail right, the
                            // label elides in between instead of running under.
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
                                textFormat: Text.PlainText
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
                                textFormat: Text.PlainText
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
