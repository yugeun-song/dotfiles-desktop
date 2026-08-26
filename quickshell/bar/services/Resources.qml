pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // -1, not 0. An idle CPU genuinely reads 0%, so zero cannot also stand
    // for "nothing has been sampled yet": it put a confident 0% on the bar for
    // the first second of every login, and left it there for good if /proc
    // ever stopped being readable.
    property real cpuUsage: -1
    property real memUsage: -1
    property real memUsedGb: -1
    property real memTotalGb: -1
    property var previousCpu: null

    // When each half was last accepted, for Theme.stale(). Two stamps rather
    // than one: the two readings come from different files and either can fail
    // on its own, so a good CPU sample must not vouch for a memory sample that
    // never arrived.
    property double cpuAsOf: 0
    property double memAsOf: 0

    readonly property int cpuPercent: Math.round(cpuUsage * 100)
    readonly property int memPercent: Math.round(memUsage * 100)

    FileView {
        id: statFile
        path: "/proc/stat"
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
    }

    FileView {
        id: kernelFile
        path: "/proc/sys/kernel/osrelease"
        // Read synchronously: an async read cannot finish before
        // Component.onCompleted returns, and the value is read once from there.
        blockLoading: true
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
    }

    property string kernel: "unknown"
    property real uptimeSeconds: 0

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
        uptimeFile.reload();
        root.uptimeSeconds = Number(uptimeFile.text().split(/\s+/)[0] ?? 0);

        const meminfo = memFile.text();
        const total = Number(meminfo.match(/MemTotal:\s+(\d+)/)?.[1] ?? 0);
        // MemAvailable is checked for presence, not coerced. On a kernel that
        // does not publish it the ?? 0 read as "no memory available", which is
        // 100% in use and an accentRed pill.
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
            // The counters are cumulative, so the ratio between two of them is
            // only a busy fraction for the interval that separates them. Across
            // a gap -- a suspend, a stalled read -- it averages the whole span
            // and presents it as the last second, so the interval is thrown
            // away rather than reinterpreted.
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
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }
}
