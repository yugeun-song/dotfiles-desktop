pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The island's event on the lock screen too (the user, 2026-11-02): hyprlock
// covers the bar, so while the screen is locked the event goes to the lock's
// own island instead, as Island.lockCompact sets it out, one at a time.
//
// hyprlock reads its three island labels (hypr/hyprlock.conf, through
// hypr/scripts/lock-island.sh) when it starts and again at each SIGUSR2
// (their cmd[update:0:1]), never on a timer: the bar writes the three files
// and then sends the signal, so the lock screen polls nothing and changes
// only when the island does. SIGUSR1 would unlock the session; the command
// below is the only signal sent, and the e2e defang matches it exactly.
//
// Written only while locked and in the session's tmpfs, so nothing of it
// stays: lock.sh removes the files before each lock and after it. Nothing
// is written with the island switched off (Super+M).
Singleton {
    id: root

    readonly property string dir: Paths.runtimeDir
    readonly property bool active: KeyFeed.locked && Media.islandOn && root.dir !== ""

    // What the lock's island shows now; a string, so that only a change of
    // what it shows asks for a write.
    readonly property var shown: Island.lockCompact(Island.kind, Island.glyph, Island.value, Island.tone)
    readonly property string shownKey: `${root.shown.lead}\u0001${root.shown.trail}\u0001${root.shown.mark}`

    onShownKeyChanged: {
        if (root.active)
            push.restart();
    }
    onActiveChanged: {
        if (root.active)
            push.restart();
    }

    // A held volume key changes the island many times a second; one write
    // and one signal for each pause in that.
    Timer {
        id: push

        interval: 80
        onTriggered: root.publish()
    }

    property bool again: false

    function publish(): void {
        if (!root.active)
            return;
        leadFile.setText(root.shown.lead);
        trailFile.setText(root.shown.trail);
        markFile.setText(root.shown.mark);
        if (refresh.running)
            root.again = true;
        else
            refresh.running = true;
    }

    // Whole files (written beside, then renamed) and written before the
    // signal goes, so hyprlock never reads half of one.
    FileView {
        id: leadFile

        path: root.dir === "" ? "" : root.dir + "/hyprlock-island-lead"
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: trailFile

        path: root.dir === "" ? "" : root.dir + "/hyprlock-island-trail"
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: markFile

        path: root.dir === "" ? "" : root.dir + "/hyprlock-island-mark"
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    // Only a hyprlock older than two seconds: until it has set its handler,
    // SIGUSR2 ends it, and one sent as the lock started killed the locker
    // (2026-11-02). lock.sh starts it with the signal ignored as well; this
    // covers one started some other way. A younger one has just read the
    // files. No hyprlock old enough is pkill's exit 1, and nothing to do.
    Process {
        id: refresh

        command: ["pkill", "--older", "2", "-USR2", "-x", "hyprlock"]

        onExited: {
            if (root.again) {
                root.again = false;
                refresh.running = true;
            }
        }
    }
}
