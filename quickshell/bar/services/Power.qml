pragma Singleton

import Quickshell
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property var device: UPower.displayDevice

    // The display device exists before it is queried and reads all zeros until
    // then; `ready` tells no-battery from not-yet-asked. It latches and never
    // clears, so it says nothing about upower still being alive.
    readonly property bool known: root.device?.ready ?? false

    readonly property bool present: root.known && root.device.isPresent && root.device.isLaptopBattery

    // percentage is 0..1 (healthPercentage is 0..100). -1 while unknown: 0 is a
    // flat battery.
    readonly property int percent: root.known ? Math.round(root.device.percentage * 100) : -1
    readonly property int state: root.device?.state ?? UPowerDeviceState.Unknown
    readonly property bool charging: root.state === UPowerDeviceState.Charging || root.state === UPowerDeviceState.PendingCharge
    readonly property bool full: root.state === UPowerDeviceState.FullyCharged
    readonly property bool onBattery: UPower.onBattery

    // Wh and W. -1 while unknown, since 0 is a real reading.
    readonly property real energyNow: root.known ? root.device.energy : -1
    readonly property real energyFull: root.known ? root.device.energyCapacity : -1
    readonly property real rate: root.known ? Math.abs(root.device.changeRate) : -1

    // Health comes from the real battery: the display device has no Capacity,
    // and quickshell derives healthSupported from it. Single battery only;
    // with two, device order is arbitrary and health could name the wrong cell.
    readonly property var batteries: (UPower.devices?.values ?? []).filter(d => d.isLaptopBattery)
    readonly property var battery: root.batteries.length === 1 ? root.batteries[0] : null

    // A battery in UPower.devices proves one exists even if the display device
    // query failed, which would otherwise hide the pill as if on a desktop.
    // The only detectable failure: a dead upower just leaves stale values.
    readonly property string unknown: root.batteries.length > 0 && !root.known
                                      ? "upower has not answered yet" : ""

    readonly property bool healthKnown: root.battery?.healthSupported ?? false
    readonly property int health: Math.round(root.battery?.healthPercentage ?? 0)

    readonly property real secondsToEmpty: root.device?.timeToEmpty ?? 0
    readonly property real secondsToFull: root.device?.timeToFull ?? 0

    function humanTime(seconds: real): string {
        if (seconds <= 0)
            return "";
        const total = Math.round(seconds / 60);
        const hours = Math.floor(total / 60);
        const minutes = total % 60;
        return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
    }

    function stateLabel(): string {
        switch (root.state) {
        case UPowerDeviceState.Charging:
            return "charging";
        case UPowerDeviceState.Discharging:
            return "discharging";
        case UPowerDeviceState.Empty:
            return "empty";
        case UPowerDeviceState.FullyCharged:
            return "full";
        case UPowerDeviceState.PendingCharge:
            return "pending charge";
        case UPowerDeviceState.PendingDischarge:
            return "pending discharge";
        default:
            return "unknown";
        }
    }
}
