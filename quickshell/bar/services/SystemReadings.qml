pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The system widget's readings (modules/SystemWidget.qml), taken in one place
// however many of it are drawn, and only while one is: every two seconds,
// the file systems every thirty.
//
// What is kept and what goes (the user, 2026-11-05: keep what a moment away
// should not lose, drop boldly what idle memory need not hold):
//   - hidden for a moment (another workspace, a window over the desktop, the
//     editor, the lock): the windows, their textures and every timer and
//     process go as before; the charts' last minute and a half stays, a few
//     numbers, unread meanwhile, so a workspace switch does not empty them;
//   - hidden longer than the charts span: by then nothing in them is recent,
//     so they go at that moment rather than on return;
//   - no system widget placed on any screen: everything goes, the GPU's
//     probe with it.
// A rate after a gap starts over: one across the gap would be its average.
//
// Where the GPU reports itself (sysfs):
//   - its own memory, where the driver writes mem_info_vram_total and
//     mem_info_vram_used (amdgpu, radeon), the card with the most when there
//     are two, so a discrete one wins over an integrated one's carve-out;
//     Intel's integrated GPUs have none (they share the system's memory);
//   - its load: amdgpu's gpu_busy_percent, else the time the render engine
//     spends idle, xe's gtidle or i915's RC6 residency, a load as one minus
//     its share of the time between two readings.
// NVIDIA's driver tells either only through nvidia-smi, which wakes a
// sleeping card, so it is not asked; and a card whose runtime power state is
// suspended is read as idle without touching it, since a read of its load
// would wake it.
Singleton {
    id: root

    // System widgets drawn now, each counting itself in and out.
    property int users: 0
    readonly property bool sampling: root.users > 0
    readonly property bool placed: Widgets.placed("system")

    readonly property int interval: 2000
    readonly property int slowEvery: 15
    readonly property int trailLength: 45
    readonly property real span: root.interval * root.trailLength

    // A stand-in for /sys/class/drm, for the tests.
    readonly property string drmDir: Quickshell.env("BAR_DRM_DIR") || "/sys/class/drm"
    property bool probed: false
    property string vramDir: ""
    property real vramTotal: 0
    readonly property bool vramFound: root.vramDir !== "" && root.vramTotal > 0
    property string busyPath: ""
    property string busyKind: ""
    property string busyPower: ""
    readonly property bool busyFound: root.busyPath !== ""

    property real gpuLoad: -1
    property var gpuLast: null
    property real vramUsed: -1
    property real rxRate: -1
    property real txRate: -1
    property var netLast: null
    property var disk: null
    property var tmp: null
    // Each reading's recent past by key: { t: [ms], v: [value] }.
    property var trails: ({})
    property int ticks: 0

    onSamplingChanged: {
        if (root.sampling) {
            expiry.stop();
            root.trim(Date.now());
            root.netLast = null;
            root.gpuLast = null;
            root.ticks = 0;
            if (!root.probed && !probe.running)
                probe.running = true;
        } else {
            expiry.restart();
        }
    }
    onPlacedChanged: {
        if (!root.placed)
            root.forget(true);
    }

    function forget(all: bool): void {
        root.trails = ({});
        root.netLast = null;
        root.gpuLast = null;
        root.rxRate = -1;
        root.txRate = -1;
        root.gpuLoad = -1;
        root.vramUsed = -1;
        root.disk = null;
        root.tmp = null;
        if (all) {
            root.probed = false;
            root.vramDir = "";
            root.vramTotal = 0;
            root.busyPath = "";
            root.busyKind = "";
            root.busyPower = "";
        }
    }

    function trim(now: real): void {
        const next = {};
        for (const key of Object.keys(root.trails)) {
            const tr = root.trails[key];
            let i = 0;
            while (i < tr.t.length && tr.t[i] < now - root.span)
                i++;
            if (i < tr.t.length)
                next[key] = { t: tr.t.slice(i), v: tr.v.slice(i) };
        }
        root.trails = next;
    }

    // /proc/net/dev's byte counts, the loopback and the virtual links left
    // out: a bridge, a container's veth or a tunnel would count the same
    // bytes twice.
    function netTotals(text: string): var {
        let rx = 0;
        let tx = 0;
        for (const line of text.split("\n")) {
            const at = line.indexOf(":");
            if (at < 0)
                continue;
            const name = line.slice(0, at).trim();
            if (/^(lo|docker|veth|br-|virbr|vnet|tun|tap|wg|tailscale|zt|vboxnet|vmnet)/.test(name))
                continue;
            const f = line.slice(at + 1).trim().split(/\s+/);
            if (f.length < 9)
                continue;
            rx += Number(f[0]) || 0;
            tx += Number(f[8]) || 0;
        }
        return { rx: rx, tx: tx };
    }

    // df's lines for / and /tmp; /tmp counts only when it is a tmpfs.
    function mounts(text: string): var {
        const out = { disk: null, tmp: null };
        for (const line of text.split("\n").slice(1)) {
            const f = line.trim().split(/\s+/);
            if (f.length < 4)
                continue;
            const at = { size: Number(f[1]), used: Number(f[2]) };
            if (!(at.size > 0) || !(at.used >= 0))
                continue;
            if (f[3] === "/")
                out.disk = at;
            else if (f[3] === "/tmp" && f[0] === "tmpfs")
                out.tmp = at;
        }
        return out;
    }

    // Sizes in powers of 1024 with df -h's letters, so they read as df shows them.
    function bytes(n: real): string {
        const units = ["B", "K", "M", "G", "T"];
        let v = Math.max(0, n);
        let i = 0;
        while (v >= 999.5 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return `${v >= 99.5 || i === 0 ? Math.round(v) : v.toFixed(1)}${units[i]}`;
    }

    // A rate as three figures at most and its unit.
    function rate(bps: real): var {
        const units = ["B/s", "K/s", "M/s", "G/s"];
        let v = Math.max(0, bps);
        let i = 0;
        while (v >= 999.5 && i < units.length - 1) {
            v /= 1024;
            i++;
        }
        return { text: v >= 9.95 || i === 0 ? `${Math.round(v)}` : v.toFixed(1), unit: units[i] };
    }

    // One line per finding: "vram <bytes> <device dir>" and
    // "busy <percent|idle> <file> <device dir>".
    readonly property string script: [
        "for d in \"$1\"/card[0-9]*/device; do",
        "  [ -d \"$d\" ] || continue",
        "  [ -r \"$d/mem_info_vram_total\" ] && [ -r \"$d/mem_info_vram_used\" ] && printf 'vram %s %s\\n' \"$(cat \"$d/mem_info_vram_total\")\" \"$d\"",
        "  if [ -r \"$d/gpu_busy_percent\" ]; then printf 'busy percent %s %s\\n' \"$d/gpu_busy_percent\" \"$d\"; continue; fi",
        "  c=${d%/device}",
        "  for f in \"$d/tile0/gt0/gtidle/idle_residency_ms\" \"$c/gt/gt0/rc6_residency_ms\" \"$c/power/rc6_residency_ms\"; do",
        "    if [ -r \"$f\" ]; then printf 'busy idle %s %s\\n' \"$f\" \"$d\"; break; fi",
        "  done",
        "done",
        "exit 0"
    ].join("\n")

    Process {
        id: probe

        command: ["sh", "-c", root.script, "sh", root.drmDir]

        stdout: StdioCollector {
            onStreamFinished: {
                let best = 0;
                let dir = "";
                let busy = null;
                for (const line of this.text.split("\n")) {
                    const v = /^vram (\d{1,20}) (\/.*)$/.exec(line);
                    if (v && Number(v[1]) > best) {
                        best = Number(v[1]);
                        dir = v[2];
                    }
                    const b = /^busy (percent|idle) (\/\S*) (\/\S*)$/.exec(line);
                    // A load in per cent over one worked out from idle time;
                    // else the first card's.
                    if (b && (!busy || (busy.kind === "idle" && b[1] === "percent")))
                        busy = { kind: b[1], path: b[2], device: b[3] };
                }
                root.vramTotal = best;
                root.vramDir = dir;
                if (busy) {
                    root.busyKind = busy.kind;
                    root.busyPath = busy.path;
                    root.busyPower = `${busy.device}/power/runtime_status`;
                }
                root.probed = true;
            }
        }
    }

    FileView {
        id: powerFile

        path: root.busyFound ? root.busyPower : ""
        blockAllReads: true
        printErrors: false
    }

    FileView {
        id: busyFile

        path: root.busyFound ? root.busyPath : ""
        blockAllReads: true
        printErrors: false
    }

    FileView {
        id: vramUsedFile

        path: root.vramFound ? `${root.vramDir}/mem_info_vram_used` : ""
        blockAllReads: true
        printErrors: false
    }

    FileView {
        id: netFile

        path: root.sampling ? "/proc/net/dev" : ""
        blockAllReads: true
        printErrors: false
    }

    Process {
        id: df

        command: ["df", "-B1", "--output=fstype,size,used,target", "--", "/", "/tmp"]

        stdout: StdioCollector {
            onStreamFinished: {
                const m = root.mounts(this.text);
                root.disk = m.disk;
                root.tmp = m.tmp;
            }
        }
    }

    function sampleGpu(now: real): void {
        if (busyFile.path === "")
            return;
        powerFile.reload();
        if (powerFile.text().trim() === "suspended") {
            root.gpuLast = null;
            root.gpuLoad = 0;
            return;
        }
        busyFile.reload();
        const v = Number(busyFile.text().trim());
        if (!Number.isFinite(v)) {
            root.gpuLoad = -1;
        } else if (root.busyKind === "percent") {
            root.gpuLoad = Math.max(0, Math.min(1, v / 100));
        } else {
            const last = root.gpuLast;
            root.gpuLast = { idle: v, at: now };
            if (last && now > last.at)
                root.gpuLoad = Math.max(0, Math.min(1, 1 - (v - last.idle) / (now - last.at)));
        }
    }

    function sampleNet(now: real): void {
        if (netFile.path === "")
            return;
        netFile.reload();
        const t = root.netTotals(netFile.text());
        const last = root.netLast;
        root.netLast = { rx: t.rx, tx: t.tx, at: now };
        if (!last || now <= last.at)
            return;
        // A counter that went back (an interface gone) reads as nothing sent.
        const s = (now - last.at) / 1000;
        root.rxRate = Math.max(0, t.rx - last.rx) / s;
        root.txRate = Math.max(0, t.tx - last.tx) / s;
    }

    // Every reading's latest goes in on every tick, so the slow ones (the
    // file systems) keep the same time axis.
    function push(now: real): void {
        const share = (used, size) => size > 0 ? Math.max(0, Math.min(1, used / size)) : -1;
        const latest = {
            cpu: Resources.cpuUsage,
            ram: Resources.memUsage,
            disk: root.disk ? share(root.disk.used, root.disk.size) : -1,
            tmpfs: root.tmp ? share(root.tmp.used, root.tmp.size) : -1,
            rx: root.rxRate,
            tx: root.txRate,
            gpu: root.gpuLoad,
            vram: root.vramUsed >= 0 && root.vramFound ? share(root.vramUsed, root.vramTotal) : -1,
            battery: Power.present ? Power.percent / 100 : -1
        };
        const next = {};
        for (const key of Object.keys(latest)) {
            const old = root.trails[key] ?? { t: [], v: [] };
            if (!(latest[key] >= 0)) {
                if (old.t.length > 0)
                    next[key] = old;
                continue;
            }
            const drop = old.t.length >= root.trailLength ? 1 : 0;
            next[key] = { t: old.t.slice(drop).concat([now]), v: old.v.slice(drop).concat([latest[key]]) };
        }
        root.trails = next;
    }

    function sample(): void {
        const now = Date.now();
        root.sampleGpu(now);
        root.sampleNet(now);
        if (vramUsedFile.path !== "") {
            vramUsedFile.reload();
            const v = Number(vramUsedFile.text().trim());
            root.vramUsed = Number.isFinite(v) && v >= 0 ? v : -1;
        }
        if (root.ticks % root.slowEvery === 0 && !df.running)
            df.running = true;
        root.push(now);
        root.ticks += 1;
    }

    Timer {
        interval: root.interval
        repeat: true
        running: root.sampling
        triggeredOnStart: true
        onTriggered: {
            root.sample();
            // A second reading half a second after the first, so a rate and
            // the GPU's load show at once rather than an interval later.
            if (root.ticks === 1)
                quick.restart();
        }
    }

    Timer {
        id: quick

        interval: 500
        onTriggered: {
            if (root.sampling)
                root.sample();
        }
    }

    // Hidden longer than the charts span: they hold nothing recent.
    Timer {
        id: expiry

        interval: root.span
        onTriggered: {
            if (!root.sampling)
                root.forget(false);
        }
    }
}
