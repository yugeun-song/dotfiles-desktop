pragma Singleton

import QtQuick
import Quickshell

// Which default output and input a snapshot of the audio devices calls for,
// as the user asked (2026-11-02): a device plugged in takes over sound both
// ways, and once it is pulled out sound goes back to what was in use
// before, the built-in speaker and microphone unless another device is
// still plugged in. Plain values in and out (services/AudioDevices.qml
// takes the snapshots, keeps what carries over and writes the answer), so
// the rules are tested without PipeWire (tests/unit/qml/shell.qml).
//
// Only the configured default is ever named, the value a click in a mixer
// writes (default.configured.audio.sink and .source). WirePlumber still
// picks the device, and falls back by itself when the configured one is
// gone, to the newest earlier choice still there
// (default-nodes/state-default-nodes.lua). Nothing runs inside the audio
// stack, so a fault here costs the switching and never the sound.
//
//   plugged: a USB or Bluetooth device whose card has just appeared becomes
//     the choice, for its output and for its microphone. A webcam's
//     microphone is left out: a camera is rarely plugged in to talk into.
//     A new node of a card seen for longer is the same device changing
//     profile (a Bluetooth headset going to call mode and back), and the
//     configured device among those arriving stays the choice.
//   quiet: nothing counts as plugged in from the first snapshot, nor for a
//     moment after the built-in card's own nodes come anew (WirePlumber or
//     PipeWire restarted, or the session just started): every device then
//     arrives at once, and WirePlumber's restored choice stands.
//   jack first: a choice of the built-in speaker or microphone becomes the
//     same card's jack sink or source. WirePlumber holds such a choice only
//     while the jack's route is available, and otherwise falls back to the
//     speaker, the next choice down, so the jack is followed although its
//     sense never reaches the bar. A phone's rule comes with it: while
//     headphones are in, the speaker cannot be kept as the choice.
//   pulled out: nothing is written; WirePlumber's fallback above.
//   the jack, seen through the default: pulled when the default leaves its
//     sink, still there, with no other output chosen; plugged when the
//     default comes onto it while it was not known to be in, unless the
//     default only fell back to it from a device that went away. Pulled
//     pauses what plays: WirePlumber pauses media players when their sink
//     goes away (linking.pause-playback), but the jack's sink stays and
//     only its route goes, so the speaker would go on aloud.
Singleton {
    id: root

    // How long after its card first shows a device's nodes count as plugged
    // in: its microphone can arrive a settle after its output.
    readonly property int arrivalMs: 2000

    // `was` is the previous snapshot with what step() returned for it
    // (jackIn, cardSince), or null; `now` as AudioDevices.snapshot() makes
    // it: `at`, nodes keyed by name and serial, each { dir, name, label,
    // kind, card, priority, serial, webcam }, and per direction the default
    // and the configured name ("" when that device is gone). `quiet` holds
    // plugged devices back (AudioDevices' moment after a restart).
    function step(was: var, now: var, quiet: bool): var {
        const nodes = Object.keys(now.nodes).map(key => ({ key: key, node: now.nodes[key] }));
        const cardSince = {};
        for (const { node } of nodes) {
            if (node.card !== "" && !(node.card in cardSince))
                cardSince[node.card] = was?.cardSince?.[node.card] ?? now.at;
        }
        const restarted = was !== null
            && nodes.some(({ key, node }) => node.kind === "fallback" && !(key in was.nodes));
        const intents = [];
        for (const dir of ["sink", "source"]) {
            let pick = null;
            let chosenBack = false;
            if (was !== null && !quiet && !restarted) {
                for (const { key, node } of nodes) {
                    if (node.dir !== dir || key in was.nodes)
                        continue;
                    if (node.kind !== "usb" && node.kind !== "bluetooth")
                        continue;
                    if (now.at - cardSince[node.card] >= root.arrivalMs)
                        continue;
                    if (dir === "source" && node.webcam)
                        continue;
                    if (node.name === now[dir].conf)
                        chosenBack = true;
                    // Several at once (a headset brings one per profile):
                    // the one WirePlumber ranks higher, the newer on a tie,
                    // so the pick never rests on key order.
                    if (pick === null || node.priority > pick.priority
                            || (node.priority === pick.priority && node.serial > pick.serial))
                        pick = node;
                }
            }
            if (pick !== null) {
                if (!chosenBack)
                    intents.push({ dir: dir, name: pick.name, why: "plugged" });
                continue;
            }
            const chosen = nodes.find(({ node }) => node.dir === dir && node.name === now[dir].conf);
            if (chosen === undefined || chosen.node.kind !== "fallback")
                continue;
            const jack = nodes.find(({ node }) => node.dir === dir && node.kind === "jack"
                                                  && node.card === chosen.node.card);
            if (jack !== undefined)
                intents.push({ dir: dir, name: jack.node.name, why: "jack first" });
        }
        const jack = root.jackStep(was, now);
        return {
            intents: intents,
            restarted: restarted,
            cardSince: cardSince,
            jack: jack.event,
            jackLabel: jack.label,
            jackIn: jack.jackIn,
            pause: jack.event === "pulled"
        };
    }

    // `jackIn` carries what is known of the jack between snapshots: in once
    // the default has been on it, out once it was pulled, unknown (null)
    // before either. The configured name is no help here: once a USB
    // device that was the choice is gone, quickshell reports no configured
    // device at all.
    function jackStep(was: var, now: var): var {
        const sinkNamed = (snap, name) => Object.values(snap.nodes).find(n => n.dir === "sink" && n.name === name);
        const after = sinkNamed(now, now.sink.def);
        if (was === null)
            return { event: "", label: "", jackIn: after?.kind === "jack" ? true : null };
        const before = sinkNamed(was, was.sink.def);
        const moved = before !== undefined && after !== undefined && before.name !== after.name;
        const chosen = after !== undefined && now.sink.conf === after.name;
        if (moved && before.kind === "jack" && !chosen && sinkNamed(now, before.name) !== undefined)
            return { event: "pulled", label: before.label, jackIn: false };
        if (after?.kind === "jack") {
            const fellBack = before !== undefined && sinkNamed(now, before.name) === undefined;
            const news = moved && was.jackIn !== true && !fellBack;
            return { event: news ? "plugged" : "", label: news ? after.label : "", jackIn: true };
        }
        return { event: "", label: "", jackIn: was.jackIn ?? null };
    }
}
