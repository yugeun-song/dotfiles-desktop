import QtQuick

// A wrong password's shake, as a phone's passcode shakes (the user,
// 2026-11-05): side to side, a little, smaller each time, for under half a
// second. `targets` are the Translates of what shakes: the lock screen's
// dots and notch (LockScreen), the see-through lock's prompt (LockGlass).
SequentialAnimation {
    id: root

    property list<QtObject> targets
    property real reach: 14

    NumberAnimation { targets: root.targets; property: "x"; to: -root.reach; duration: 45; easing.type: Easing.OutSine }
    NumberAnimation { targets: root.targets; property: "x"; to: root.reach * 0.8; duration: 70; easing.type: Easing.InOutSine }
    NumberAnimation { targets: root.targets; property: "x"; to: -root.reach * 0.6; duration: 65; easing.type: Easing.InOutSine }
    NumberAnimation { targets: root.targets; property: "x"; to: root.reach * 0.4; duration: 60; easing.type: Easing.InOutSine }
    NumberAnimation { targets: root.targets; property: "x"; to: -root.reach * 0.2; duration: 55; easing.type: Easing.InOutSine }
    NumberAnimation { targets: root.targets; property: "x"; to: 0; duration: 50; easing.type: Easing.InSine }
}
