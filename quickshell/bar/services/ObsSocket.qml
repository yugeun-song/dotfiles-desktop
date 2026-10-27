import QtQuick
import QtWebSockets
import qs.services

// The socket to OBS's WebSocket server, for Obs.qml, which says why it is
// its own file and made only while OBS is open. obs-websocket speaks JSON on
// the subprotocol named here.
WebSocket {
    id: root

    url: `ws://127.0.0.1:${Obs.port > 0 ? Obs.port : 4455}`
    requestedSubprotocols: ["obswebsocket.json"]
    active: false

    function send(text: string): void {
        if (root.status === WebSocket.Open)
            root.sendTextMessage(text);
    }

    onTextMessageReceived: message => Obs.receive(message)

    onStatusChanged: {
        if (root.status === WebSocket.Closed || root.status === WebSocket.Error)
            Obs.lost();
    }
}
