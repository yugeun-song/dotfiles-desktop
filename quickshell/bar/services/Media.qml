pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// What is playing, and whether the player card is open.
//
// A singleton because two surfaces need it: the chip in the bar, which the
// pointer enters, and the card it opens, which the pointer then moves into.
// Neither can see the other's hover, so both report here and the union
// decides.
Singleton {
    id: root

    // Whatever is playing, or failing that whatever has a track loaded. One
    // rule in one place, so the chip and the card cannot disagree about which
    // player is "the" one.
    readonly property var player: {
        const players = Mpris.players?.values ?? [];
        return players.find(p => p.isPlaying) ?? players.find(p => (p.trackTitle ?? "") !== "") ?? null;
    }

    readonly property string title: root.player?.trackTitle ?? ""
    readonly property string artist: root.player?.trackArtist ?? ""
    readonly property bool present: root.title !== ""
    readonly property bool playing: root.present && (root.player?.isPlaying ?? false)

    // Set independently by the chip and the card.
    property bool chipHovered: false
    property bool cardHovered: false

    property bool open: false

    readonly property bool wanted: root.chipHovered || root.cardHovered

    onWantedChanged: {
        if (root.wanted) {
            close.stop();
            root.open = true;
        } else {
            close.restart();
        }
    }

    // A grace period on the way out only: the pointer leaves one surface a
    // frame before it enters the other, and closing on that shut the card
    // every time the pointer crossed into it.
    Timer {
        id: close

        interval: 200
        onTriggered: root.open = false
    }
}
