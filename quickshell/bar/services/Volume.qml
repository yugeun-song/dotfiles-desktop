pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Default sink volume. Observe-only for the keys: Hyprland binds them to
// hypr/scripts/volume.sh (wpctl first) so they work without the shell, and
// changes from any source show up here.
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: root.sink?.audio ?? null
    readonly property bool present: root.audio !== null

    // present = a sink exists; known = it has been read. Until the node binds,
    // volume reads a default 0, which would be seen as the sink's first value
    // and make the real one raise the island's readout (services/Island.qml).
    readonly property bool known: root.present && (root.sink?.ready ?? false)

    // -1 until read. Capped at 100 although Pipewire allows more; the keys
    // limit to 1.0 but a mixer need not.
    readonly property int percent: root.known
                                   ? Math.min(100, Math.round(root.audio.volume * 100))
                                   : -1
    readonly property bool muted: root.audio?.muted ?? false

    signal changed

    // Without the tracker, volume and muted never leave their defaults.
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    // Each sink's first values are state, not a change: no readout at login,
    // nor when the output moves to a device plugged in or back from one
    // pulled out (services/AudioDevices.qml), where the new sink brings its
    // own level. The sink counts as seen only once the batch that switched
    // it is over, since its level and its mute land one signal after the
    // other; seen on the switch itself, not on its first change, so the
    // first key after a switch still shows.
    property var seededSink: null

    function seedLater(): void {
        const sink = root.sink;
        Qt.callLater(() => {
            if (root.sink === sink && root.known)
                root.seededSink = sink;
        });
    }

    onSinkChanged: root.seedLater()
    onKnownChanged: root.seedLater()

    // muted has no sentinel and reads false while unbound, hence known.
    onPercentChanged: {
        if (root.known && root.seededSink === root.sink)
            root.changed();
    }
    onMutedChanged: {
        if (root.known && root.seededSink === root.sink)
            root.changed();
    }

    // ---- writing --------------------------------------------------------
    // For the bar, not the keys. Writes go through Pipewire once known, else
    // wpctl: an unbound node returns defaults, so toggleMute would invert an
    // unread value.

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
