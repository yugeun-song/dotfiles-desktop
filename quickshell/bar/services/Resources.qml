pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // -1 = not sampled yet; 0% is a real reading.
    property real cpuUsage: -1
    property real memUsage: -1
    property real memUsedGb: -1
    property real memTotalGb: -1
    property var previousCpu: null

    // Separate stamps for Theme.stale(): the two files can fail independently.
    property double cpuAsOf: 0
    property double memAsOf: 0

    readonly property int cpuPercent: Math.round(cpuUsage * 100)
    readonly property int memPercent: Math.round(memUsage * 100)

    // blockLoading: text() waits for the read reload() just started. Without
    // it, text() gave the read before, and every sample was a second old.
    // A /proc read takes microseconds.
    FileView {
        id: statFile
        path: "/proc/stat"
        blockLoading: true
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        blockLoading: true
    }

    FileView {
        id: kernelFile
        path: "/proc/sys/kernel/osrelease"
        // Synchronous: read once in Component.onCompleted.
        blockLoading: true
    }

    // Read when the badge's tooltip is about to show (readUptime), not every
    // second: nothing else shows it, and each read is a reader thread and
    // three lines in the bar's log, which lives in tmpfs for the session.
    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        blockLoading: true
    }

    function readUptime() {
        uptimeFile.reload();
        root.uptimeSeconds = Number(uptimeFile.text().split(/\s+/)[0] ?? 0);
    }

    property string kernel: "unknown"
    property real uptimeSeconds: 0

    // The distribution, for the badge and its tooltip; "linux" when
    // /etc/os-release is missing or has no ID.
    property string distroId: "linux"
    property string distroName: "Linux"

    FileView {
        id: osRelease
        path: "/etc/os-release"
        blockLoading: true
    }

    readonly property string uptimeText: {
        const total = Math.floor(root.uptimeSeconds / 60);
        const days = Math.floor(total / 1440);
        const hours = Math.floor((total % 1440) / 60);
        const minutes = total % 60;
        if (days > 0)
            return `${days}d ${hours}h`;
        return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
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
            root.memTotalGb = total / 1048576;
            root.memUsedGb = (total - available) / 1048576;
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
        kernelFile.reload();
        const value = kernelFile.text().trim();
        if (value !== "")
            root.kernel = value;
        osRelease.reload();
        const release = osRelease.text();
        const id = release.match(/^ID=["']?([A-Za-z0-9._-]+)["']?\s*$/m);
        if (id)
            root.distroId = id[1].toLowerCase();
        const pretty = release.match(/^PRETTY_NAME=["']?([^"'\n]+)["']?\s*$/m)
                       ?? release.match(/^NAME=["']?([^"'\n]+)["']?\s*$/m);
        if (pretty)
            root.distroName = pretty[1];
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }
}
