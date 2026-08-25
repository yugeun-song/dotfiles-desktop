pragma Singleton

import Quickshell
import Quickshell.Bluetooth
import qs.services

Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool present: root.adapter !== null
    readonly property bool enabled: root.adapter?.enabled ?? false

    readonly property var connectedDevices: {
        const devices = Bluetooth.devices?.values ?? [];
        return devices.filter(d => d.connected);
    }

    readonly property var pairedDevices: {
        const devices = Bluetooth.devices?.values ?? [];
        return devices.filter(d => d.paired);
    }

    readonly property int connectedCount: root.connectedDevices.length
    readonly property string firstName: root.connectedDevices[0]?.deviceName ?? root.connectedDevices[0]?.name ?? ""

    function icon(): string {
        if (!root.present || !root.enabled)
            return Theme.iconBtOff;
        return root.connectedCount > 0 ? Theme.iconBtLinked : Theme.iconBt;
    }
}
