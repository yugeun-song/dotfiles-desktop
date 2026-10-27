pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // -1 = not sampled yet; 0% is a real reading.
    property real cpuUsage: -1
    property real memUsage: -1
    property var previousCpu: null

    // Separate stamps for Theme.stale(): the two files can fail independently.
    property double cpuAsOf: 0
    property double memAsOf: 0

    readonly property int cpuPercent: Math.round(cpuUsage * 100)
    readonly property int memPercent: Math.round(memUsage * 100)

    // blockAllReads: text() waits for the read reload() just started.
    // blockLoading covers only the first load; after it, text() gave the read
    // before (CPU and memory a second old). A /proc read takes microseconds.
    FileView {
        id: statFile
        path: "/proc/stat"
        blockAllReads: true
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        blockAllReads: true
    }

    // The distribution, for the badge; "linux" when /etc/os-release is
    // missing or has no ID.
    property string distroId: "linux"
    // ID_LIKE's words, for a derivative the badge has no mark of its own for.
    property var distroLike: []

    FileView {
        id: osRelease
        path: "/etc/os-release"
        blockLoading: true
    }

    function sample() {
        statFile.reload();
        memFile.reload();

        const meminfo = memFile.text();
        const total = Number(meminfo.match(/MemTotal:\s+(\d+)/)?.[1] ?? 0);
        // Require MemAvailable; defaulting it to 0 would read as 100% in use.
        const availableField = meminfo.match(/MemAvailable:\s+(\d+)/);
        if (total > 0 && availableField) {
            const available = Number(availableField[1]);
            root.memUsage = (total - available) / total;
            root.memAsOf = Date.now();
        }

        const cpuLine = statFile.text().match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/m);
        if (!cpuLine)
            return;

        const fields = cpuLine.slice(1, 8).map(Number);
        const idle = fields[3] + fields[4];
        const total2 = fields.reduce((a, b) => a + b, 0);

        const now = Date.now();
        if (root.previousCpu) {
            const deltaTotal = total2 - root.previousCpu.total;
            const deltaIdle = idle - root.previousCpu.idle;
            // Discard deltas across a gap (suspend, stalled read): they would
            // average the whole span and present it as the last second.
            const elapsed = now - root.previousCpu.at;
            if (deltaTotal > 0 && elapsed < 3000) {
                root.cpuUsage = Math.max(0, Math.min(1, (deltaTotal - deltaIdle) / deltaTotal));
                root.cpuAsOf = now;
            }
        }
        root.previousCpu = {
            total: total2,
            idle: idle,
            at: now
        };
    }

    Component.onCompleted: {
        osRelease.reload();
        const release = osRelease.text();
        const id = release.match(/^ID=["']?([A-Za-z0-9._-]+)["']?\s*$/m);
        if (id)
            root.distroId = id[1].toLowerCase();
        const like = release.match(/^ID_LIKE=["']?([A-Za-z0-9._ -]+)["']?\s*$/m);
        root.distroLike = like ? like[1].toLowerCase().split(/\s+/).filter(w => w !== "") : [];
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }
}
