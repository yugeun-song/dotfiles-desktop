pragma Singleton

import Quickshell
import Quickshell.Bluetooth
import qs.services

Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool present: root.adapter !== null
    readonly property bool enabled: root.adapter?.enabled ?? false

    // A machine does not lose its radio because bluetoothd stopped. Once an
    // adapter has been seen the pill keeps its place, so one that goes away
    // reads as "no reading" instead of as "this machine has no Bluetooth" --
    // which is what "none" on a muted pill and the tooltip "No Bluetooth
    // adapter" claimed. A radio switched off is not this: Powered going false
    // leaves the adapter in place, and that is a reading.
    property bool everPresent: false
    onPresentChanged: if (root.present) root.everPresent = true

    // States what was seen, not why. An adapter stops being reported both when
    // bluetoothd goes down and when a dongle is unplugged, and quickshell
    // publishes nothing that tells the two apart.
    readonly property string unknown: root.everPresent && !root.present
                                      ? "The adapter stopped being reported" : ""

    // The adapter's own device list, not the global one. present, enabled and
    // icon() all describe defaultAdapter, so a count taken across every adapter
    // in the machine was describing something else on the same pill.
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
