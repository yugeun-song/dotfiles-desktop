pragma Singleton

import Quickshell
import Quickshell.Bluetooth
import qs.services

Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool present: root.adapter !== null
    readonly property bool enabled: root.adapter?.enabled ?? false

    // Once an adapter has been seen, losing it is "no reading", not "no
    // Bluetooth". Powered off keeps the adapter and is a real reading.
    property bool everPresent: false
    onPresentChanged: if (root.present) root.everPresent = true

    // States what was seen, not why: quickshell cannot tell bluetoothd down
    // from a dongle unplugged.
    readonly property string unknown: root.everPresent && !root.present
                                      ? "The adapter stopped being reported" : ""

    // defaultAdapter's devices, matching present/enabled/icon().
    readonly property var adapterDevices: root.adapter?.devices?.values ?? []

    readonly property var connectedDevices: root.adapterDevices.filter(d => d.connected)
    readonly property var pairedDevices: root.adapterDevices.filter(d => d.paired)

    readonly property int connectedCount: root.connectedDevices.length
    readonly property string firstName: root.connectedDevices[0]?.deviceName ?? root.connectedDevices[0]?.name ?? ""

    function icon(): string {
        if (!root.present || !root.enabled)
            return Theme.iconBtOff;
        return root.connectedCount > 0 ? Theme.iconBtLinked : Theme.iconBt;
    }
}
