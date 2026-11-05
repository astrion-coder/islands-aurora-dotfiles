import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.services
import qs.widgets

// Right click on the sound pill: volume, mute, the volume mixer, then Bluetooth: the
// trusted devices (✓ = connected, battery on the right; click to connect or
// disconnect), Blueman's device manager and Bluetooth on/off. Toggles keep the menu open
// so you can watch them take effect.
MenuCard {
    id: root

    required property var bar
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: adapter?.enabled ?? false
    readonly property var devices: Bluetooth.devices.values
        .filter(d => d.trusted)
        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))

    minWidth: 270
    maxHeight: bar?.popupMaxHeight ?? 600

    VolumeSlider {}

    MenuItem {
        text: Audio.muted ? "Unmute" : "Mute"
        onClicked: Audio.toggleMute()
    }
    MenuItem {
        text: "Volume mixer"
        onClicked: {
            root.bar.closePopup();
            root.bar.openMixer();
        }
    }

    MenuSeparator { visible: root.adapter !== null }

    Repeater {
        model: root.btOn ? root.devices : []

        MenuItem {
            id: device

            required property var modelData
            property bool failed: false      // the last connection attempt didn't work
            readonly property int btState: modelData.state
            readonly property int battery: modelData.battery <= 1 ? Math.round(modelData.battery * 100) : Math.round(modelData.battery)

            text: modelData.name || modelData.deviceName || modelData.address
            mark: modelData.connected ? "✓" : ""
            detail: btState === BluetoothDeviceState.Connecting ? "connecting…"
                  : btState === BluetoothDeviceState.Disconnecting ? "disconnecting…"
                  : failed ? "couldn't connect"
                  : modelData.connected && modelData.batteryAvailable ? battery + "%" : ""
            onClicked: {
                failed = false;
                if (modelData.connected)
                    modelData.disconnect();
                else
                    modelData.connect();
            }

            property int lastState: btState
            onBtStateChanged: {
                if (lastState === BluetoothDeviceState.Connecting && btState === BluetoothDeviceState.Disconnected) {
                    failed = true;
                    clearFailed.restart();
                }
                lastState = btState;
            }
            Timer {
                id: clearFailed
                interval: 4000
                onTriggered: device.failed = false
            }
        }
    }

    MenuSeparator { visible: root.btOn && root.devices.length > 0 }

    MenuItem {
        visible: root.adapter !== null
        text: "Bluetooth devices"
        onClicked: {
            root.bar.closePopup();
            root.bar.run([root.bar.script("popup.sh"), "blueman-manager", "blueman-manager"]);
        }
    }
    MenuItem {
        visible: root.adapter !== null
        text: root.btOn ? "Turn Bluetooth off" : "Turn Bluetooth on"
        onClicked: root.adapter.enabled = !root.btOn
    }
}
