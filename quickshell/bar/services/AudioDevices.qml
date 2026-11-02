pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

// The audio devices as PipeWire has them, read as whole snapshots: handed
// to AudioPolicy.qml for the default output and input to configure, and to
// the island for what to tell (services/Island.qml: outputsSettle).
//
// Safety, after the user's worry (2026-11-02) that audio, once tangled,
// stays tangled. The bar is one more PipeWire client and writes what a
// click in a mixer writes, the configured default, through quickshell: no
// process, file, D-Bus call or setting of WirePlumber's, which stays as
// shipped. A configured device that goes away is WirePlumber's own fallback
// to handle, and with the bar stopped or broken sound keeps its last
// choice. Device names come from devices, so they are drawn as plain text
// (IslandEvent.qml) and never reach a shell or the log. A device plugged
// in while the screen is locked is taken only after the unlock, if it is
// still there: one left in an unattended laptop gets no sound and gives no
// microphone.
//
// Timing: PipeWire tells of a node before its properties, of a default
// before or after the node it names, of a device as several nodes. No
// signal is acted on alone. Each restarts a short settle, and the settle
// reads everything afresh, waiting while a node is still unbound, so a
// half-known device is never taken for a new one. A choice is held as an
// intent with a deadline: written, looked at again, written again while it
// has not landed, and dropped once it lands, its device goes or the
// deadline passes.
//
// Signals carry no reads, only a restart of the settle. A node that is both
// the default and the configured default sends its going to two of
// quickshell's slots in turn; a binding that read the other default from
// within the first handed QML the node half torn down, and quickshell
// 0.3.2 crashed (SIGSEGV in lookupSingletonProperty, 2026-11-02, unplugging
// earphones that were both). A settle runs once that is over.
Singleton {
    id: root

    // Devices' sinks and sources, taken by each settle; streams and filters
    // never count.
    property var nodes: []

    // A node's properties stay empty until it is bound (checked against
    // quickshell 0.3.2), and the bus and kind are among them.
    PwObjectTracker {
        objects: root.nodes
    }

    Connections {
        target: Pipewire

        function onReadyChanged(): void {
            settle.restart();
        }
        function onDefaultAudioSinkChanged(): void {
            settle.restart();
        }
        function onDefaultAudioSourceChanged(): void {
            settle.restart();
        }
        function onDefaultConfiguredAudioSinkChanged(): void {
            settle.restart();
        }
        function onDefaultConfiguredAudioSourceChanged(): void {
            settle.restart();
        }
    }

    Connections {
        target: Pipewire.nodes

        function onValuesChanged(): void {
            settle.restart();
        }
    }

    // The unlock lets a device plugged in meanwhile be taken.
    Connections {
        target: KeyFeed

        function onLockedChanged(): void {
            settle.restart();
        }
    }

    Component.onCompleted: settle.restart()

    // Short, as the jack's pause (AudioPolicy.qml) waits on it while the
    // speaker already plays. A device's nodes split over several settles
    // are still one device plugged in: AudioPolicy counts a card as new for
    // a while after it first shows.
    Timer {
        id: settle

        interval: 100
        onTriggered: root.read()
    }

    // A written choice comes back as a change of the configured default; a
    // look this much later finds one that did not land, as no change wakes
    // the settle then.
    Timer {
        id: verify

        interval: 800
        onTriggered: root.read()
    }

    // How long a choice is pursued, and how long after the first snapshot
    // or a restart of the audio stack devices arriving are the state, not
    // something plugged in (AudioPolicy.qml, quiet).
    readonly property int intentMs: 5000
    readonly property int quietMs: 3000

    // The jack rule's breaker: a speaker set back as the choice this many
    // times within jackRewriteMs means someone keeps choosing it (a person
    // in a mixer, an application with a policy of its own), and taking
    // turns would toss sound between the speaker and the headphones. The
    // rule then rests for that direction until the choice is something
    // other than the built-in device, and says so once in the log. Devices
    // plugged in are not counted: each is one event, written once.
    readonly property int jackRewrites: 3
    readonly property int jackRewriteMs: 30000

    property var seen: null
    property real quietUntil: 0
    property var intents: ({})
    property var deferred: ({})
    property var rewrites: ({ sink: [], source: [] })
    property var jackResting: ({ sink: false, source: false })

    // When the wait for unbound nodes began; 0 while none is awaited. A node
    // that never binds is given up on rather than holding everything back.
    property real waitingSince: 0

    // Binding waits on the tracker, which takes the nodes from here, so
    // readiness is looked at again every settle until it holds, rather
    // than through one connection per node.
    function read(): void {
        if (!Pipewire.ready)
            return;
        const fresh = Pipewire.nodes.values.filter(
            n => !n.isStream && (n.type === PwNodeType.AudioSink || n.type === PwNodeType.AudioSource));
        // Replaced only when it differs: a new list is a new set for the
        // tracker, which need not bind again what it holds.
        if (fresh.length !== root.nodes.length || fresh.some((n, i) => n !== root.nodes[i]))
            root.nodes = fresh;
        if (root.nodes.some(n => !n.ready)) {
            if (root.waitingSince === 0)
                root.waitingSince = Date.now();
            if (Date.now() - root.waitingSince < 3000) {
                settle.restart();
                return;
            }
        }
        root.waitingSince = 0;
        const snap = root.snapshot();
        const step = root.apply(snap);
        root.settled(root.islandView(snap, step));
    }

    // The island's view of each settle (outputs only).
    signal settled(var view)

    function dirOf(node: var): string {
        return node.type === PwNodeType.AudioSink ? "sink" : "source";
    }

    // "usb" and "bluetooth" for devices of their own, "jack" and "fallback"
    // for the built-in card's jack and speaker or microphone (the laptop's
    // SOF card keeps a node for each), "" for the rest: HDMI and
    // DisplayPort, and nodes no device backs. Bluetooth's microphone is a
    // loopback WirePlumber makes, with no device.api of its own.
    function kindOf(props: var, dir: string): string {
        if (props["device.api"] === "bluez5" || String(props["bluez5.loopback"]) === "true")
            return "bluetooth";
        if (props["device.api"] !== "alsa")
            return "";
        if (props["device.bus"] === "usb")
            return "usb";
        const icon = props["device.icon_name"] ?? "";
        if (icon === (dir === "sink" ? "audio-headphones" : "audio-headset"))
            return "jack";
        if (icon === (dir === "sink" ? "audio-speakers" : "audio-input-microphone"))
            return "fallback";
        return "";
    }

    function described(node: var): var {
        const props = node.properties;
        const dir = root.dirOf(node);
        return {
            dir: dir,
            name: node.name,
            label: props["node.nick"] || node.nickname || node.description || node.name,
            kind: root.kindOf(props, dir),
            card: props["device.id"] ?? "",
            priority: Number(props["priority.session"] ?? 0),
            serial: Number(props["object.serial"] ?? node.id),
            webcam: props["device.form-factor"] === "webcam"
        };
    }

    // Plain values only. A node is keyed by its serial too: plugged in
    // again, a device is a new node under the same name. A configured
    // device that is gone reads "": quickshell keeps no node for it.
    function snapshot(): var {
        const nodes = {};
        for (const n of root.nodes) {
            if (n.ready)
                nodes[`${n.name}#${n.properties["object.serial"] ?? n.id}`] = root.described(n);
        }
        return {
            at: Date.now(),
            nodes: nodes,
            sink: { def: Pipewire.defaultAudioSink?.name ?? "",
                    conf: Pipewire.preferredDefaultAudioSink?.name ?? "" },
            source: { def: Pipewire.defaultAudioSource?.name ?? "",
                      conf: Pipewire.preferredDefaultAudioSource?.name ?? "" }
        };
    }

    function apply(snap: var): var {
        const now = snap.at;
        const step = AudioPolicy.step(root.seen, snap, root.seen === null || now < root.quietUntil);
        if (root.seen === null || step.restarted)
            root.quietUntil = now + root.quietMs;
        snap.jackIn = step.jackIn;
        snap.cardSince = step.cardSince;
        root.seen = snap;

        for (const intent of step.intents) {
            // A device just plugged in is still being written: until that
            // lands, the speaker it replaces still reads as the choice, and
            // the jack rule must not take its place.
            if (intent.why === "jack first" && root.intents[intent.dir]?.why === "plugged")
                continue;
            if (intent.why === "plugged" && KeyFeed.locked)
                root.deferred[intent.dir] = intent.name;
            else
                root.intents[intent.dir] = { name: intent.name, why: intent.why, until: now + root.intentMs };
        }
        // Unlocked: what was plugged in meanwhile and is still there.
        if (!KeyFeed.locked) {
            for (const dir of ["sink", "source"]) {
                const name = root.deferred[dir];
                if (name === undefined)
                    continue;
                delete root.deferred[dir];
                if (root.intents[dir] === undefined)
                    root.intents[dir] = { name: name, why: "plugged", until: now + root.intentMs };
            }
        }

        // What a player's own pause button does; calls are no MPRIS player
        // and go on through the speaker, and a player sent elsewhere by
        // hand is paused too.
        if (step.pause) {
            for (const player of Mpris.players.values) {
                if (player.isPlaying && player.canPause)
                    player.pause();
            }
        }

        let wrote = false;
        for (const dir of ["sink", "source"]) {
            const chosen = Object.values(snap.nodes).find(n => n.dir === dir && n.name === snap[dir].conf);
            if (chosen?.kind !== "fallback")
                root.jackResting[dir] = false;
            const want = root.intents[dir];
            if (want === undefined)
                continue;
            const node = root.nodes.find(n => n.name === want.name && root.dirOf(n) === dir);
            if (snap[dir].conf === want.name || node === undefined || now > want.until
                    || (want.why === "jack first" && !root.mayRewrite(dir, now))) {
                delete root.intents[dir];
                continue;
            }
            if (dir === "sink")
                Pipewire.preferredDefaultAudioSink = node;
            else
                Pipewire.preferredDefaultAudioSource = node;
            wrote = true;
        }
        if (wrote)
            verify.restart();
        return step;
    }

    function mayRewrite(dir: string, now: real): bool {
        if (root.jackResting[dir])
            return false;
        const recent = root.rewrites[dir].filter(t => now - t < root.jackRewriteMs);
        if (recent.length >= root.jackRewrites) {
            root.rewrites[dir] = [];
            root.jackResting[dir] = true;
            console.warn(`[audio] the built-in ${dir === "sink" ? "speaker" : "microphone"} keeps being chosen back; the jack rule rests until another device is chosen`);
            return false;
        }
        recent.push(now);
        root.rewrites[dir] = recent;
        return true;
    }

    // What Island.outputsStep reads: USB devices with an output, one per
    // card, so a change of profile is no plug; the jack's events as
    // AudioPolicy saw them. Bluetooth is told by Island.btStep.
    function islandView(snap: var, step: var): var {
        const outs = {};
        for (const key in snap.nodes) {
            const n = snap.nodes[key];
            if (n.dir === "sink" && n.kind === "usb" && !(n.card in outs))
                outs[n.card] = { label: n.label, kind: n.kind };
        }
        return { outs: outs, jack: step.jack, jackLabel: step.jackLabel };
    }
}
