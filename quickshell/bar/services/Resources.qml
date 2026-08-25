pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property real cpuUsage: 0
    property real memUsage: 0
    property real memUsedGb: 0
    property real memTotalGb: 0
    property var previousCpu: null

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
        const available = Number(meminfo.match(/MemAvailable:\s+(\d+)/)?.[1] ?? 0);
        if (total > 0) {
            root.memTotalGb = total / 1048576;
            root.memUsedGb = (total - available) / 1048576;
            root.memUsage = (total - available) / total;
        }

        const cpuLine = statFile.text().match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/m);
        if (!cpuLine)
            return;

        const fields = cpuLine.slice(1, 8).map(Number);
        const idle = fields[3] + fields[4];
        const total2 = fields.reduce((a, b) => a + b, 0);

        if (root.previousCpu) {
            const deltaTotal = total2 - root.previousCpu.total;
            const deltaIdle = idle - root.previousCpu.idle;
            if (deltaTotal > 0)
                root.cpuUsage = Math.max(0, Math.min(1, (deltaTotal - deltaIdle) / deltaTotal));
        }
        root.previousCpu = {
            total: total2,
            idle: idle
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
