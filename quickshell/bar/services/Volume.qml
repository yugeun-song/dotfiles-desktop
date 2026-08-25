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

    readonly property int percent: root.audio ? Math.round(root.audio.volume * 100) : -1
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

    onMutedChanged: {
        if (root.seeded)
            root.changed();
    }

    // ---- writing --------------------------------------------------------
    //
    // Used by the bar, not by the keys. Pipewire is the fast path; wpctl is
    // there for the case where the Pipewire service found no sink at all,
    // which is what a machine with a bare ALSA setup looks like.

    function set(value) {
        const clamped = Math.max(0, Math.min(100, Math.round(value)));
        if (root.audio) {
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
        if (root.audio) {
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
