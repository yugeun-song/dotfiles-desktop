pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Output volume of the default sink.
//
// This service only observes. The volume keys are bound in Hyprland straight
// to wpctl, so they keep working when this shell is not running, and every
// change lands here regardless of who made it: a key press, a mixer, or an
// application setting its own stream. Driving the keys from here instead
// would mean volume changed by anything else passed unremarked.
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: root.sink?.audio ?? null
    readonly property bool present: root.audio !== null

    // The audio object exists before Pipewire has said anything about it, and
    // until the node is bound `volume` reads its default of 0. present answers
    // "is there a sink", known answers "has it been read"; folding the two
    // published a confident 0% for a sink that was playing at 24, and that
    // fake reading was what consumed `seeded` below, so the first real value
    // arrived looking like a change and raised the OSD that flag exists to
    // prevent. Reproduced against live Pipewire: -1, then 0, then 24.
    readonly property bool known: root.present && (root.sink?.ready ?? false)

    // -1 for unread, and never a number that was not measured. Clamped here
    // rather than at the display: Pipewire allows a node past 1.0 -- the
    // volume keys pass -l 1.0, an external mixer need not -- and Osd.qml caps
    // whatever it is handed, so 150 reached the screen as a settled 100.
    readonly property int percent: root.known
                                   ? Math.min(100, Math.round(root.audio.volume * 100))
                                   : -1
    readonly property bool muted: root.audio?.muted ?? false

    signal changed

    // Binding to a node's audio properties requires holding the object;
    // without the tracker `volume` and `muted` never leave their defaults.
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    // The first value that arrives is the current state, not a change. Firing
    // then would greet every login with an OSD nobody asked for.
    property bool seeded: false

    onPercentChanged: {
        if (root.percent < 0)
            return;
        if (!root.seeded) {
            root.seeded = true;
            return;
        }
        root.changed();
    }

    // known as well as seeded. muted has no sentinel to fall back on, so it
    // reads false while the sink is unbound; firing on it alone showed the OSD
    // with a percentage nobody had read yet. Nothing is lost by waiting: the
    // reading lands a moment later and raises the OSD with the number in it.
    onMutedChanged: {
        if (root.seeded && root.known)
            root.changed();
    }

    // ---- writing --------------------------------------------------------
    //
    // Used by the bar, not by the keys. Pipewire is the fast path; wpctl is
    // there for the case where there is nothing here to write to -- no sink at
    // all, which is what a machine with a bare ALSA setup looks like, or a
    // sink whose properties have not arrived. The second case is why these
    // branch on `known` rather than on the object: an unbound node hands back
    // its defaults, so toggleMute would invert a `muted` nobody had read.

    function set(value) {
        const clamped = Math.max(0, Math.min(100, Math.round(value)));
        if (root.known) {
            root.audio.volume = clamped / 100;
            return;
        }
        fallback.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", `${clamped}%`];
        fallback.running = true;
    }

    function step(delta) {
        if (root.percent < 0) {
            fallback.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@",
                                `${Math.abs(delta)}%${delta >= 0 ? "+" : "-"}`, "-l", "1.0"];
            fallback.running = true;
            return;
        }
        root.set(root.percent + delta);
    }

    function toggleMute() {
        if (root.known) {
            root.audio.muted = !root.audio.muted;
            return;
        }
        fallback.command = ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"];
        fallback.running = true;
    }

    Process {
        id: fallback

        onExited: code => {
            if (code !== 0)
                console.warn("[volume] wpctl fallback exited", code);
        }
    }
}
