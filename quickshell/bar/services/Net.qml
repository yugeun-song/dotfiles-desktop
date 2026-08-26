pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking
import qs.services

Singleton {
    id: root

    readonly property var devices: Networking.devices?.values ?? []

    // quickshell chooses a backend once, while the Networking singleton is
    // being built, and never retries. So this is not a live statement about the
    // daemon: it says the bar came up with nothing to read from, and that it
    // will not start reading on its own if NetworkManager is started later.
    //
    // An empty device list deliberately does not count as unknown. Devices are
    // enumerated over DBus asynchronously and take a second or two to arrive,
    // so "nothing listed yet" is what every login looks like.
    readonly property string unknown: Networking.backend === NetworkBackendType.None
                                      ? "NetworkManager was not running when the bar started"
                                      : ""

    readonly property var wifiDevice: root.devices.find(d => d.type === DeviceType.Wifi) ?? null

    // Wired comes from the same model as Wi-Fi now. It used to be scraped out
    // of /sys/class/net, which took whichever interface the glob reached first,
    // counted anything with a device symlink and no wireless directory as
    // ethernet -- a wwan modem among them -- and read carrier, which is the
    // cable rather than the route. NetworkManager builds a device only for its
    // own Ethernet type, so bridges, tunnels, veth pairs and modems cannot be
    // mistaken for an uplink here.
    readonly property var wiredDevice: root.devices.find(d => d.type === DeviceType.Wired) ?? null

    readonly property bool wifiRadioOn: Networking.wifiEnabled
    readonly property bool wifiConnected: root.wifiDevice?.connected ?? false
    // connected is the device's own activation state, so it is the link traffic
    // is on. hasLink is only the cable being plugged in. The two are kept apart
    // because a cable into a dead switch satisfies one and not the other.
    readonly property bool wiredConnected: root.wiredDevice?.connected ?? false
    readonly property bool wiredHasLink: root.wiredDevice?.hasLink ?? false

    readonly property var wifiNetwork: {
        const networks = root.wifiDevice?.networks?.values ?? [];
        return networks.find(n => n.connected) ?? null;
    }

    readonly property string ssid: root.wifiNetwork?.name ?? ""
    // quickshell normalises this to 0.0..1.0 (wifi.hpp: "from 0.0 to 1.0";
    // wireless.cpp divides NetworkManager's 0..100 Strength by 100), so the
    // percentage has to be reconstructed. Reading it raw pins the value at 0
    // or 1 and leaves the icon on its weakest bar no matter how good the link.
    //
    // -1 for "no figure", never 0. Zero is a real strength, and coercing to it
    // put the weakest-bar icon and a "connected 0%" tooltip on a green pill in
    // the moment between the device reporting connected and its network doing
    // the same.
    readonly property int signal: root.wifiNetwork
                                  ? Math.round(root.wifiNetwork.signalStrength * 100)
                                  : -1

    // A wired link wins when both are up: that is the route traffic takes.
    readonly property bool preferWired: root.wiredConnected

    function wifiIcon(): string {
        if (!root.wifiRadioOn)
            return Theme.iconWifiOff;
        if (!root.wifiConnected)
            return Theme.iconWifiDown;
        if (root.signal >= 75)
            return Theme.iconWifi4;
        if (root.signal >= 50)
            return Theme.iconWifi3;
        if (root.signal >= 25)
            return Theme.iconWifi2;
        return Theme.iconWifi1;
    }
}
