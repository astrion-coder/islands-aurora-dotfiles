pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire

// The default output: volume, mute, and whether it's a Bluetooth device (with its battery).
Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property string name: sink?.description ?? ""
    readonly property bool bluetooth: (sink?.properties["device.api"] ?? "") === "bluez5"

    readonly property string btAddress: sink?.properties["api.bluez5.address"] ?? ""
    readonly property var btDevice: Bluetooth.devices.values.find(d => d.address === root.btAddress) ?? null
    // percent, or -1 when the device doesn't report it
    readonly property int btBattery: btDevice?.batteryAvailable ? Math.round(btDevice.battery <= 1 ? btDevice.battery * 100 : btDevice.battery) : -1

    // an app is recording from the microphone (the island shows a dot)
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool micInUse: (micLinks.linkGroups ?? []).some(g => g.source === root.source && g.state === PwLinkState.Active)
    PwNodeLinkTracker {
        id: micLinks
        node: root.source
    }
    // (a link's state only stays current while it's tracked)
    PwObjectTracker {
        objects: micLinks.linkGroups ?? []
    }

    // volume and mute can only be read and set on tracked nodes
    PwObjectTracker {
        objects: [root.sink]
    }

    function setVolume(v) {
        if (sink?.audio)
            sink.audio.volume = Math.max(0, Math.min(1, v));
    }

    function toggleMute() {
        if (sink?.audio)
            sink.audio.muted = !sink.audio.muted;
    }
}
