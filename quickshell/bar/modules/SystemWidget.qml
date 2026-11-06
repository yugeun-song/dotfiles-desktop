pragma ComponentBehavior: Bound

import QtQuick
import qs.services

// The machine's widget, in WidgetCard's reference pixels: one reading a row,
// as a watchlist lists stocks (the user, 2026-11-05): the name small at the
// left, with how much of how much under it where that says something; a
// chart of the recent past in the middle (Trace); the value huge at the
// right. No glyphs. In the user's order: processor, RAM, received, sent, GPU
// load, VRAM, battery, then the disk and the tmpfs at the foot; the GPU's two
// where the GPU reports them, the battery where there is one. Four rows in the small and
// medium cards, all nine in the large, the default. The readings are
// services/SystemReadings.qml's, taken while one of these is drawn and kept
// for a moment away (see there); this counts itself in while it exists.
Item {
    id: root

    required property string size
    required property var options

    Component.onCompleted: SystemReadings.users += 1
    Component.onDestruction: SystemReadings.users -= 1

    readonly property var r: SystemReadings

    // value: a share 0..1, or bytes a second for the network's; -1 unknown.
    readonly property var rows: {
        const out = [];
        const share = (used, size) => size > 0 ? Math.max(0, Math.min(1, used / size)) : -1;
        const of = (used, size) => `${root.r.bytes(used)} / ${root.r.bytes(size)}`;
        const o = root.options;
        if (o.cpu === true)
            out.push({ key: "cpu", label: "CPU", value: Resources.cpuUsage, minSpan: 0.04,
                       alert: Resources.cpuUsage >= Theme.loadAlertFraction });
        if (o.memory === true)
            out.push({ key: "ram", label: "RAM", value: Resources.memUsage, minSpan: 0.02,
                       detail: Resources.memTotal > 0 && Resources.memUsage >= 0 ? of(Resources.memUsage * Resources.memTotal, Resources.memTotal) : "",
                       alert: Resources.memUsage >= Theme.loadAlertFraction });
        if (o.network === true) {
            out.push({ key: "rx", label: "Network Rx", short: "Rx", value: root.r.rxRate, rate: true, minSpan: 2048, alert: false });
            out.push({ key: "tx", label: "Network Tx", short: "Tx", value: root.r.txRate, rate: true, minSpan: 2048, alert: false });
        }
        if (o.gpu === true && root.r.busyFound)
            out.push({ key: "gpu", label: "GPU load", short: "GPU", value: root.r.gpuLoad, minSpan: 0.04,
                       alert: root.r.gpuLoad >= Theme.loadAlertFraction });
        if (o.vram === true && root.r.vramFound) {
            const v = root.r.vramUsed >= 0 ? share(root.r.vramUsed, root.r.vramTotal) : -1;
            out.push({ key: "vram", label: "VRAM", value: v, minSpan: 0.02,
                       detail: root.r.vramUsed >= 0 ? of(root.r.vramUsed, root.r.vramTotal) : "", alert: v >= Theme.loadAlertFraction });
        }
        if (o.battery === true && Power.present)
            out.push({ key: "battery", label: Power.charging ? "Charging" : "Battery", value: Power.percent / 100, minSpan: 0.02,
                       alert: !Power.charging && Power.percent <= 20 });
        if (o.disk === true && root.r.disk) {
            const v = share(root.r.disk.used, root.r.disk.size);
            out.push({ key: "disk", label: "Disk", value: v, minSpan: 0.01, detail: of(root.r.disk.used, root.r.disk.size),
                       alert: v >= Theme.loadAlertFraction });
        }
        if (o.tmpfs === true && root.r.tmp) {
            const v = share(root.r.tmp.used, root.r.tmp.size);
            out.push({ key: "tmpfs", label: "tmpfs", value: v, minSpan: 0.01, detail: of(root.r.tmp.used, root.r.tmp.size),
                       alert: v >= Theme.loadAlertFraction });
        }
        return out;
    }

    readonly property int capacity: root.size === "large" ? 9 : 4
    readonly property var shown: root.rows.slice(0, root.capacity)
    readonly property int count: root.shown.length
    readonly property real innerW: root.width - Theme.widgetPad * 2
    readonly property real innerH: root.height - Theme.widgetPad * 2
    readonly property real rowGap: 4
    // Rows as tall as the card allows, to a limit: a short list stands in
    // the middle rather than growing huge.
    readonly property real pitch: root.count > 0 ? Math.min(46, (root.innerH - (root.count - 1) * root.rowGap) / root.count) : 0
    readonly property real listTop: Theme.widgetPad + (root.innerH - (root.count * root.pitch + Math.max(0, root.count - 1) * root.rowGap)) / 2
    readonly property bool narrow: root.innerW < 250
    readonly property real nameW: root.narrow ? root.innerW * 0.36 : 104
    readonly property real valueW: root.narrow ? root.innerW * 0.34 : 74
    readonly property real unitW: 26
    // The value large, the rest not far below it (the user, 2026-11-05: the
    // figures a little smaller, the names, sizes and units a little larger,
    // the gap between them not wide): the figures' height, at most, and the
    // small type's sizes.
    readonly property real figureH: 22
    readonly property int nameSize: 15
    readonly property int detailSize: 12
    readonly property int unitSize: 14

    Text {
        visible: root.count === 0
        anchors.centerIn: parent
        text: "Nothing to show"
        font.family: Theme.uiFont
        font.pixelSize: Theme.widgetTitleSize
        color: Theme.muted
    }

    Repeater {
        model: root.shown

        Item {
            id: row

            required property var modelData
            required property int index

            readonly property bool known: row.modelData.value >= 0
            readonly property var reading: row.modelData.rate && row.known ? root.r.rate(row.modelData.value) : null
            readonly property string detail: row.modelData.detail ?? ""
            readonly property real chartX: root.nameW + 8
            readonly property real chartW: row.width - row.chartX - 10 - root.valueW - root.unitW

            x: Theme.widgetPad
            y: root.listTop + row.index * (root.pitch + root.rowGap)
            width: root.innerW
            height: root.pitch

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: root.nameW
                spacing: 1

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.narrow && row.modelData.short ? row.modelData.short : row.modelData.label
                    font.family: Theme.uiFont
                    font.pixelSize: root.nameSize
                    font.weight: Font.Medium
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.85)
                }

                Text {
                    visible: row.detail !== "" && !root.narrow
                    width: parent.width
                    elide: Text.ElideRight
                    text: row.detail
                    font.family: Theme.uiFont
                    font.pixelSize: root.detailSize
                    font.features: { "tnum": 1 }
                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.5)
                }
            }

            Trace {
                visible: row.chartW >= 30
                x: row.chartX
                y: 5
                width: Math.max(0, row.chartW)
                height: parent.height - 10
                values: root.r.trails[row.modelData.key]?.v ?? []
                minSpan: row.modelData.minSpan
            }

            HeroText {
                id: figure

                x: parent.width - root.unitW - root.valueW
                width: root.valueW
                height: Math.min(parent.height - 6, root.figureH)
                anchors.verticalCenter: parent.verticalCenter
                text: !row.known ? "--" : row.reading ? row.reading.text : `${Math.round(row.modelData.value * 100)}`
                probe: "100"
                horizontal: "right"
                tabular: true
                color: row.modelData.alert ? Theme.accentRed : Theme.fg
            }

            Text {
                visible: row.known
                x: parent.width - root.unitW + 3
                anchors.baseline: parent.top
                anchors.baselineOffset: figure.y + figure.figureBaseline
                text: row.reading ? row.reading.unit : "%"
                font.family: Theme.uiFont
                font.pixelSize: root.unitSize
                font.weight: Font.Medium
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.6)
            }
        }
    }
}
