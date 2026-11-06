import QtQuick
import qs.services

// A list's scroll bar, there while the list holds more than fits (the user,
// 2026-11-04: to see how far it goes): the handle is as long as the share in
// view and sits where the view is. Drag the handle to scroll, or click the
// track beside it to move a page. For any Flickable, a GridView's included.
Item {
    id: root

    required property Flickable view

    readonly property real ratio: Math.min(1, root.view.visibleArea.heightRatio)
    readonly property bool needed: root.view.contentHeight > root.view.height + 1
    // How far the view can travel, and the handle with it.
    readonly property real travel: Math.max(0, root.view.contentHeight - root.view.height)
    readonly property real room: Math.max(0, root.height - handle.height)

    function scrollTo(fraction: real): void {
        root.view.contentY = root.view.originY + Math.max(0, Math.min(1, fraction)) * root.travel;
    }

    visible: root.needed
    implicitWidth: Theme.px(8)

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.surfaceWell
    }

    Rectangle {
        id: handle

        width: parent.width
        height: Math.max(Theme.px(32), parent.height * root.ratio)
        y: root.travel > 0 ? root.room * ((root.view.contentY - root.view.originY) / root.travel) : 0
        radius: width / 2
        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b,
                       area.dragging ? 0.6 : area.containsMouse ? 0.45 : 0.3)
    }

    MouseArea {
        id: area

        property bool dragging: false
        property real grab: 0

        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor

        onPressed: mouse => {
            if (mouse.y >= handle.y && mouse.y <= handle.y + handle.height) {
                area.dragging = true;
                area.grab = mouse.y - handle.y;
                return;
            }
            // A page towards the click, as a desktop's scroll bars move.
            const page = root.view.height * 0.9;
            const target = root.view.contentY + (mouse.y < handle.y ? -page : page);
            root.scrollTo(root.travel > 0 ? (target - root.view.originY) / root.travel : 0);
        }
        onPositionChanged: mouse => {
            if (area.dragging && root.room > 0)
                root.scrollTo((mouse.y - area.grab) / root.room);
        }
        onReleased: area.dragging = false
        onCanceled: area.dragging = false
    }
}
