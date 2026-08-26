pragma Singleton

import Quickshell
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property var device: UPower.displayDevice

    // upower's own word that the aggregate device has answered. quickshell
    // hands out this object before it has queried it, rather than hand out
    // null, so every figure on it reads as a default-constructed zero until
    // the first reply lands. Without this the properties below cannot tell a
    // machine with no battery from one that has not been asked yet.
    //
    // It is a latch, set once and never cleared, so it says nothing about
    // whether upower is still alive. See `unknown` below.
    readonly property bool known: root.device?.ready ?? false

    readonly property bool present: root.known && root.device.isPresent && root.device.isLaptopBattery

    // UPower reports percentage as a 0..1 fraction, not a percentage. The
    // convention is not shared: healthPercentage below is already 0..100.
    //
    // -1, never 0, while there is no answer: zero is a flat battery.
    readonly property int percent: root.known ? Math.round(root.device.percentage * 100) : -1
    readonly property int state: root.device?.state ?? UPowerDeviceState.Unknown
    readonly property bool charging: root.state === UPowerDeviceState.Charging || root.state === UPowerDeviceState.PendingCharge
    readonly property bool full: root.state === UPowerDeviceState.FullyCharged
    readonly property bool onBattery: UPower.onBattery

    // Wh, from the raw Joule-per-second style figures UPower reports. Also -1
    // rather than 0 unread: "0.0 of 53.0 Wh" is a claim about the cell, and a
    // draw of 0 W is a claim about the machine.
    readonly property real energyNow: root.known ? root.device.energy : -1
    readonly property real energyFull: root.known ? root.device.energyCapacity : -1
    readonly property real rate: root.known ? Math.abs(root.device.changeRate) : -1

    // Health comes off the real battery: the synthetic display device never
    // publishes Capacity, and quickshell reads healthSupported as "capacity is
    // not zero", so asking the display device hides the line for good.
    //
    // Only the single-battery case. UPower.devices is filled in the order the
    // devices answer, so with two cells the first match is not the one the
    // aggregate percentage above describes, and the tooltip would print one
    // battery's health beside the other's charge. Two batteries drop the
    // health line rather than attribute it to the wrong cell.
    readonly property var batteries: (UPower.devices?.values ?? []).filter(d => d.isLaptopBattery)
    readonly property var battery: root.batteries.length === 1 ? root.batteries[0] : null

    // A device only enters UPower.devices once it has answered, so a laptop
    // battery listed there is proof this machine has one. The aggregate device
    // is a separate object with its own query, which can fail on its own --
    // and when it did, `present` stayed false and the pill quietly left,
    // telling a laptop owner that their machine is a desktop.
    //
    // This is the only unreadable state upower exposes. There is no signal for
    // the daemon dying: `ready` is never cleared, the aggregate device is a
    // value member that never becomes null, and the last values simply stay
    // put, so an outage cannot be told apart from a charge that has not moved.
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
