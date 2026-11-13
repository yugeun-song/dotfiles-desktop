pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.services

// One screen of the lock screen (lock.qml), its numbers read as LockFrame
// reads them.
LockFrame {
    id: root

    // The power button's and panel's pixels per bar pixel (LockPower): the
    // bar's sizes on this screen (Theme.fit), a fifth larger. Sized by the
    // island at first, its words came out under the bar's (9 px on the
    // laptop to the bar's 13), and the user: at least a little larger than
    // what the bar shows (2026-11-05).
    readonly property real footUnit: Theme.fit(root.lockScreen) * 1.2

    // ---- the keys ---------------------------------------------------------
    // An Item, not a text field: no input method sees them, so nothing is
    // composed (fcitx5's Hangul), and the password is never on screen.
    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            event.accepted = true;
            // The power panel takes the arrows, Enter and Escape while it is
            // open; anything typed closes it and goes to the password.
            if (power.open) {
                if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                    power.move(event.key === Qt.Key_Up ? -1 : 1);
                    return;
                }
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && power.selected >= 0) {
                    power.choose(power.selected);
                    return;
                }
                power.close();
                if (event.key === Qt.Key_Escape)
                    return;
            }
            root.lockRoot.key(event);
        }
        Keys.onReleased: event => root.lockRoot.keyReleased(event)
    }

    // ---- the way in ---------------------------------------------------------
    // The desktop as it was frosts over and dims while the lock's ground
    // comes in over it and settles from a slight zoom, the notch comes down
    // out of the edge and the rest follows a beat later, as a phone's and a
    // laptop's lock screens come (the user, 2026-11-06: the old fade looked
    // like a stutter). It was a stutter: the fade started as this screen's
    // items were made, and the first frame came only once the wallpaper was
    // decoded and every effect compiled, half the fade later; recorded on the
    // nested compositor, the desktop went to half the lock, the same frame
    // again, then 85%. So everything is drawn first at a two-hundredths of
    // its strength over the desktop's picture, which looks like the desktop
    // and pays that cost, and the way in starts at the second frame shown.
    property int swaps: 0
    readonly property bool warming: root.swaps < 2
    property real enter: 0

    Connections {
        target: root.Window.window
        enabled: root.warming

        function onFrameSwapped(): void {
            root.swaps += 1;
            if (root.swaps === 2)
                entering.start();
        }
    }

    // Frames that are slow to come do not hold the lock back past this.
    Timer {
        running: root.warming
        interval: 1200
        onTriggered: {
            root.swaps = 2;
            entering.start();
        }
    }

    NumberAnimation {
        id: entering

        target: root
        property: "enter"
        from: 0
        to: 1
        duration: root.lockRoot.enterMs
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1]
    }

    // The desktop as it was, under the lock while it comes in.
    Image {
        id: desk

        anchors.fill: parent
        visible: false
        source: root.lockRoot.captures[root.lockScreen?.name ?? ""]?.url ?? ""
        fillMode: Image.Stretch
        cache: false
    }

    MultiEffect {
        anchors.fill: parent
        source: desk
        visible: desk.status === Image.Ready
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: Math.max(1, Math.round(root.tall(64)))
        blur: root.enter
        brightness: -0.3 * root.enter
    }

    Item {
        id: scene

        anchors.fill: parent
        opacity: root.warming ? 0.002 : 1

        // ---- the ground -----------------------------------------------------
        // Faded and zoomed as one; the ground itself, inside, is what the
        // probe below copies, so the ink is chosen against it as it ends.
        Item {
            anchors.fill: parent
            opacity: root.warming ? 1 : root.enter
            scale: root.warming || root.enter >= 1 ? 1 : 1.04 - 0.04 * root.enter

            Item {
                id: backdrop

                anchors.fill: parent

                // Opaque under all that follows: if the picture fails, black.
                Rectangle {
                    anchors.fill: parent
                    color: root.o.background?.color ?? "black"
                }

                // The wallpaper, blurred and dimmed as hyprlock's background
                // block says; a busy one more (lock-colours.py). hyprlock's
                // passes of its size came to about size x 2^(passes + 1)
                // pixels of radius, matched against its own render of the
                // same picture.
                Image {
                    id: wallpaper

                    anchors.fill: parent
                    visible: false
                    source: root.o.background?.path ? `file://${root.o.background.path}` : ""
                    // Decoded at a quarter of the screen under a heavy blur,
                    // half under a light one: the blur leaves no detail finer
                    // than that, and the full picture cost a screen's worth
                    // of memory each.
                    readonly property real shrink: (root.o.background?.blur_passes ?? 0) >= 3 ? 4 : (root.o.background?.blur_passes ?? 0) > 0 ? 2 : 1
                    sourceSize: Qt.size(Math.round(root.deviceW / shrink), Math.round(root.deviceH / shrink))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: false
                    cache: false
                }

                MultiEffect {
                    anchors.fill: parent
                    source: wallpaper
                    visible: wallpaper.status === Image.Ready
                    autoPaddingEnabled: false
                    blurEnabled: (root.o.background?.blur_passes ?? 0) > 0
                    blurMax: Math.max(1, Math.round(root.tall((root.o.background?.blur_size ?? 0) * Math.pow(2, (root.o.background?.blur_passes ?? 0) + 1))))
                    blur: 1.0
                    saturation: Math.min(1, root.o.background?.vibrancy ?? 0)
                }

                // A video in the picture's place where wallpaper.sh linked
                // one: the picture above is its first frame, shown until the
                // video plays.
                Loader {
                    anchors.fill: parent
                    active: (root.o.background?.video ?? "") !== ""

                    sourceComponent: LockVideo {
                        source: `file://${root.o.background.video}`
                        textureSize: Qt.size(Math.round(root.deviceW / wallpaper.shrink), Math.round(root.deviceH / wallpaper.shrink))
                        blurOn: (root.o.background?.blur_passes ?? 0) > 0
                        blurMax: Math.max(1, Math.round(root.tall((root.o.background?.blur_size ?? 0) * Math.pow(2, (root.o.background?.blur_passes ?? 0) + 1))))
                        saturation: Math.min(1, root.o.background?.vibrancy ?? 0)
                    }
                }

                // brightness multiplies the picture, as a black veil of its
                // rest.
                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: 1 - Math.max(0, Math.min(1, root.o.background?.brightness ?? 1))
                }
            }
        }

        // What lies under every word and surface, for LockInk: the ground at
        // a quarter of the screen, which its blur leaves nothing finer than;
        // live, so a video recolours the ink as it plays.
        ShaderEffectSource {
            id: probe

            sourceItem: backdrop
            live: true
            hideSource: false
            visible: false
            textureSize: Qt.size(Math.max(16, Math.round(root.width / 4)), Math.max(16, Math.round(root.height / 4)))
        }

        // ---- the notch ------------------------------------------------------
        LockNotch {
            id: notch

            anchors.fill: parent
            screenRoot: root
            lockRoot: root.lockRoot
            card: card
            // Above the edge while the rest warms unseen: its curves are
            // drawn whatever the opacity over them (measured: it showed over
            // the desktop's picture), so it waits out of sight instead.
            enter: root.enter
        }

        // ---- the rest: in a beat after the ground, from a slight zoom ----------
        Item {
            id: content

            anchors.fill: parent
            opacity: root.warming ? 1 : Math.max(0, Math.min(1, (root.enter - 0.12) / 0.88))
            scale: root.warming || root.enter >= 1 ? 1 : 0.97 + 0.03 * root.enter

            SystemClock {
                id: clock

                precision: SystemClock.Minutes
            }

            LockLabel {
                screenRoot: root
                block: root.o.date
                text: Qt.formatDateTime(clock.date, root.o.date?.format ?? "ddd, d MMM")
            }

            LockLabel {
                screenRoot: root
                block: root.o.time
                text: Qt.formatDateTime(clock.date, "HH:mm")
            }

            // The weather's glyph in the full-size cut: the Mono one fits it
            // to one narrow cell.
            Row {
                id: weatherRow

                readonly property var block: root.o.weather ?? ({})
                readonly property var w: root.lockRoot.weather
                readonly property real room: root.whole(root.tall(8))

                visible: weatherRow.w !== null
                // The halo's room is padding inside the layer.
                padding: weatherRow.room
                x: root.crisp(root.xOf(weatherRow.block, weatherRow.width - 2 * weatherRow.room) - weatherRow.room)
                y: root.crisp(root.yOf(weatherRow.block, weatherRow.height - 2 * weatherRow.room) - weatherRow.room)
                // What hyprlock's label puts between them: an en space and two.
                spacing: weatherGap.advanceWidth

                layer.enabled: true
                layer.smooth: true
                layer.effect: LockInk {
                    target: weatherRow
                    under: probe
                    screenItem: root
                    haloSize: root.tall(6)
                }

                TextMetrics {
                    id: weatherGap

                    font.family: root.family(weatherRow.block.font_family)
                    font.pixelSize: Math.max(1, root.points(weatherRow.block.font_size ?? 22))
                    text: "   "
                }

                Text {
                    text: weatherRow.w ? Theme.weatherIcon(weatherRow.w.code, weatherRow.w.day) : ""
                    color: Theme.beige
                    font.family: Theme.iconFont.replace(/ Mono$/, "")
                    font.pixelSize: Math.max(1, root.points(weatherRow.block.font_size ?? 22))
                }

                Text {
                    text: weatherRow.w ? `${weatherRow.w.temp}°` : ""
                    color: Theme.beige
                    font.family: root.family(weatherRow.block.font_family)
                    font.weight: root.weight(weatherRow.block.font_family)
                    font.pixelSize: Math.max(1, root.points(weatherRow.block.font_size ?? 22))
                }
            }

            // ---- the card and the field ------------------------------------
            LockCard {
                id: card

                readonly property var block: root.o.card ?? ({})

                height: root.tall(block.size ?? 0)
                width: height * 864 / 259
                x: root.crisp(root.xOf(block, width))
                y: root.crisp(root.yOf(block, height))
                under: probe
                screenItem: root
            }

            LockField {
                id: field

                readonly property var block: root.o.field ?? ({})

                width: root.wide(block.size?.[0] ?? 0, block.even ?? false)
                height: root.tall(block.size?.[1] ?? 0)
                x: root.crisp(root.xOf(block, width))
                y: root.crisp(root.yOf(block, height))
                lockRoot: root.lockRoot
                under: probe
                screenItem: root
                room: root.whole(root.shake + root.tall(8))
                fontFamily: root.family(block.font_family)
                fontWeight: root.weight(block.font_family)
                placeholder: block.placeholder ?? "Press to unlock"
                dotsSize: block.dots_size ?? 0.13
                dotsSpacing: block.dots_spacing ?? 0.35
            }
        }

        // ---- the power button and its panel ---------------------------------
        // Not in hyprlock.conf: hyprlock, the fallback, has neither. In the
        // bar's sizes on this screen, a little larger (footUnit).
        LockPower {
            id: power

            anchors.fill: parent
            screenRoot: root
            lockRoot: root.lockRoot
            under: probe
            unit: root.footUnit
            opacity: root.warming ? 1 : Math.max(0, Math.min(1, (root.enter - 0.25) / 0.75))
        }
    }

    // The ground's probe, which each label's ink reads here (LockLabel).
    readonly property alias under: probe

    // ---- a wrong password -------------------------------------------------
    // The dots and the notch shake (LockShake).
    readonly property real shake: root.tall(14)

    Connections {
        target: root.lockRoot

        function onShakesChanged() {
            shaking.restart();
        }
    }

    LockShake {
        id: shaking

        targets: [notch.offset, field.offset]
        reach: root.shake
    }
}
