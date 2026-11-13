pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services

// One screen of the see-through lock (lock.qml with LOCK_GLASS; the user,
// 2026-11-12: a lock that leaves the screen showing what it shows). The
// compositor goes on drawing the desktop, live, under the lock
// (session_lock_xray, which lock.sh turns on for this lock alone), and this
// draws over it nothing but a prompt, and that only while someone is at the
// keys or the pointer, and for a moment as the lock takes hold, to say that
// it holds (lock.qml's `awake`): a black pill where the lock screen's field
// is, the lock at its left end, what the field would hold in its middle
// ("Press to unlock", a dot for each character typed, a wrong password's
// words, a lockout's countdown) and Caps Lock's mark at its right end. Black
// with the lock screen's beige, as its notch: under it lies whatever the
// desktop shows, which the compositor draws and this cannot see. Every key
// and click is the lock's, as on the lock screen; no window under it gets
// one.
//
// In the lock screen's measures (LockFrame): as tall as its notch shows and
// at least as wide, at most as wide as its field; the notch's lock glyph,
// the field's words and dots. In the field's place, so that on either lock
// the password goes to the same spot.
LockFrame {
    id: root

    readonly property var island: root.o.island ?? ({})
    readonly property var field: root.o.field ?? ({})

    // The notch as it shows (LockNotch): its shape less what hyprlock.conf
    // pushes above the screen's edge.
    readonly property real pillH: root.whole(root.tall((root.island.size?.[1] ?? 0) - Math.max(0, root.island.position?.[1] ?? 0)))
    readonly property real leastW: root.wide(root.island.size?.[0] ?? 0, root.island.even ?? false)
    readonly property real mostW: Math.min(root.width * 0.9, root.wide(root.field.size?.[0] ?? 0, root.field.even ?? false))
    // The field's words and dots as the lock screen sizes them (LockField).
    readonly property real fieldH: root.tall(root.field.size?.[1] ?? 0)
    readonly property real wordsSize: Math.max(1, root.fieldH * 0.33)
    readonly property real dot: Math.max(2, root.fieldH * (root.field.dots_size ?? 0.13))
    readonly property real dotGap: root.dot * (root.field.dots_spacing ?? 0.35)

    // The lock in a square of the pill's height at its left end, its middle
    // as far in as from the top and the foot, as the notch holds its own; the
    // room round its ink kept at the right end too, past the words or the
    // dots, which sit in the middle of what is left; Caps Lock's mark,
    // while it shows, just inside that right end. Its room is taken off the
    // dots whether it shows or not, so it never changes how many fit; the
    // pill widens for it only where the words or the dots need the space.
    readonly property real pad: Math.max(0, (root.pillH - lockGlyph.inkWidth) / 2)
    readonly property real capsH: root.crisp(root.wordsSize * 0.8)
    readonly property real capsW: root.crisp(root.capsH * 18 / 19.6)
    readonly property real capsRoom: root.wordsSize * 0.5 + root.capsW
    readonly property real room: Math.max(0, root.mostW - root.pillH - root.pad - root.capsRoom)
    readonly property int fits: Math.max(1, Math.floor((root.room + root.dotGap) / (root.dot + root.dotGap)))
    readonly property int count: Math.min(root.fits, root.lockRoot.shownDots)
    // As LockField: the dots of a password handed over first, through the
    // check and the shake; then what the check said, a lockout's countdown
    // before it.
    readonly property string words: root.lockRoot.heldDots > 0 ? ""
        : root.lockRoot.lockoutText !== "" ? root.lockRoot.lockoutText
        : root.lockRoot.failText !== "" ? root.lockRoot.failText
        : root.count === 0 ? (root.field.placeholder ?? "Press to unlock") : ""
    readonly property real middleW: root.words !== "" ? Math.min(root.room, wordsText.implicitWidth)
                                                     : root.count * root.dot + Math.max(0, root.count - 1) * root.dotGap
    readonly property real capsTaken: root.lockRoot.capsLock ? root.capsRoom : 0
    readonly property real pillW: root.whole(Math.max(root.leastW, Math.min(root.mostW, root.pillH + root.middleW + root.capsTaken + root.pad)))
    // The middle's left edge, the words and the dots centred in what the
    // lock, the end and the mark leave.
    function middleX(w: real): real {
        return root.crisp(root.pillH + (pill.width - root.pillH - root.pad - root.capsTaken - w) / 2);
    }

    // ---- the keys and the pointer ------------------------------------------
    // The keys as on the lock screen (lock.qml's key()), each one showing the
    // prompt; so does any motion, press or turn of the wheel, so that a hand
    // on the mouse finds the screen locked.
    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            event.accepted = true;
            root.lockRoot.wake();
            root.lockRoot.key(event);
        }
        Keys.onReleased: event => root.lockRoot.keyReleased(event)
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onPositionChanged: root.lockRoot.wake()
        onPressed: root.lockRoot.wake()
        onWheel: root.lockRoot.wake()
    }

    // ---- the prompt ----------------------------------------------------------
    Item {
        id: pill

        x: root.crisp((root.width - pill.width) / 2)
        y: root.crisp(root.yOf(root.field, root.pillH))
        width: root.pillW
        height: root.pillH
        opacity: root.lockRoot.awake ? 1 : 0
        scale: root.lockRoot.awake ? 1 : 0.96
        visible: pill.opacity > 0

        // In and out at a toast's pace (Theme.notif*); wider with each dot.
        Behavior on opacity {
            NumberAnimation {
                duration: root.lockRoot.awake ? Theme.notifEnterMs : Theme.notifLeaveMs
                easing.type: root.lockRoot.awake ? Easing.OutCubic : Easing.InCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.lockRoot.awake ? Theme.notifEnterMs : Theme.notifLeaveMs
                easing.type: root.lockRoot.awake ? Easing.OutCubic : Easing.InCubic
            }
        }
        Behavior on width {
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        transform: Translate {
            id: shift
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.islandColor
        }

        LockGlyph {
            id: lockGlyph

            cx: root.pillH / 2
            cy: root.pillH / 2
            text: Theme.iconLock
            color: Theme.beige
            family: root.family(root.o.lead?.font_family ?? Theme.iconFont)
            size: root.points(root.o.lead?.font_size ?? 16)
        }

        Text {
            id: wordsText

            x: root.middleX(wordsText.width)
            y: root.crisp((root.pillH - wordsText.height) / 2)
            width: Math.min(wordsText.implicitWidth, root.room)
            visible: root.words !== ""
            elide: Text.ElideRight
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            text: root.words
            color: Theme.beige
            font.family: root.family(root.field.font_family)
            font.weight: root.weight(root.field.font_family)
            font.pixelSize: root.wordsSize
        }

        Row {
            id: dotsRow

            x: root.middleX(dotsRow.width)
            y: root.crisp((root.pillH - root.dot) / 2)
            visible: root.words === ""
            spacing: root.dotGap

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

        // Caps Lock's mark, the lock screen's (LockField), inside the right
        // end. Its picture is white and only its shape counts there, LockInk
        // giving it a colour; here it is tinted the beige.
        Image {
            id: capsShape

            x: root.crisp(pill.width - root.pad - root.capsW)
            y: root.crisp((root.pillH - root.capsH) / 2)
            width: root.capsW
            height: root.capsH
            source: "capslock.svg"
            // In item pixels: Qt scales an SVG by the window's ratio itself.
            sourceSize: Qt.size(capsShape.width, capsShape.height)
            smooth: true
            visible: false
        }

        MultiEffect {
            anchors.fill: capsShape
            source: capsShape
            colorization: 1
            colorizationColor: Theme.beige
            opacity: root.lockRoot.capsLock ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }
    }

    // ---- a wrong password ---------------------------------------------------
    // The prompt shakes as the lock screen's dots do (LockShake).
    Connections {
        target: root.lockRoot

        function onShakesChanged() {
            shaking.restart();
        }
    }

    LockShake {
        id: shaking

        targets: [shift]
        reach: root.tall(14)
    }
}
