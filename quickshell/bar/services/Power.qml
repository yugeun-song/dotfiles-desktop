pragma Singleton

import Quickshell
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool present: (root.device?.isPresent ?? false) && (root.device?.isLaptopBattery ?? false)

    // UPower reports percentage as a 0..1 fraction, not a percentage. The
    // convention is not shared: healthPercentage below is already 0..100.
    readonly property int percent: Math.round((root.device?.percentage ?? 0) * 100)
    readonly property int state: root.device?.state ?? UPowerDeviceState.Unknown
    readonly property bool charging: root.state === UPowerDeviceState.Charging || root.state === UPowerDeviceState.PendingCharge
    readonly property bool full: root.state === UPowerDeviceState.FullyCharged
    readonly property bool onBattery: UPower.onBattery

    // Wh, from the raw Joule-per-second style figures UPower reports.
    readonly property real energyNow: root.device?.energy ?? 0
    readonly property real energyFull: root.device?.energyCapacity ?? 0
    readonly property real rate: Math.abs(root.device?.changeRate ?? 0)

    // Health comes off the real battery: the synthetic display device never
    // publishes Capacity, and quickshell reads healthSupported as "capacity is
    // not zero", so asking the display device hides the line for good.
    readonly property var battery: UPower.devices?.values.find(d => d.isLaptopBattery) ?? null

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
