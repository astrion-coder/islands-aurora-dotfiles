pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.Notifications
import Quickshell.Services.UPower

// What the island shows for a moment: notifications, volume changes, the sound output
// switching, Bluetooth devices connecting, a new song, battery events.
// `current`: { kind: "notification" | "volume" | "track" | "message", notification, icon,
// title, detail, warn } or null.
Singleton {
    id: root

    property var current: null

    // ms: how long; 0 keeps it until the island is opened
    function show(activity, ms) {
        if (!ready && activity.kind !== "notification")
            return;
        current = activity;
        if (ms > 0) {
            hide.interval = ms;
            hide.restart();
        } else {
            hide.stop();
        }
    }

    // the island was opened: the notification is in its list now
    function seen() {
        if (current?.kind === "notification")
            current = null;
    }

    Timer {
        id: hide
        onTriggered: root.current = null
    }

    // services report their first values while the shell starts: not news
    property bool ready: false
    Timer {
        interval: 3000
        running: true
        onTriggered: root.ready = true
    }

    // ---------------------------------------------------------------- notifications

    Connections {
        target: Notifs
        function onArrived(n) {
            root.show({ kind: "notification", notification: n, warn: n.urgency === NotificationUrgency.Critical }, Notifs.showFor(n));
            // closed meanwhile (by you elsewhere, or by its app): stop showing it
            n.closed.connect(() => {
                if (root.current?.notification === n)
                    root.current = null;
            });
        }
    }

    // ---------------------------------------------------------------- sound

    property real switched: 0       // when the output last changed

    Connections {
        target: Audio
        function onSinkChanged() {
            root.switched = Date.now();
            if (Audio.sink)
                root.show({ kind: "message", icon: Audio.bluetooth ? "bluetooth" : "volume", title: Audio.name, detail: "sound output" }, 2500);
        }
        // (a new output reports its volume too: keep showing which output it is)
        function onVolumeChanged() {
            if (Date.now() - root.switched > 1000)
                root.show({ kind: "volume" }, 1600);
        }
        function onMutedChanged() {
            root.show({ kind: "volume" }, 1600);
        }
    }

    Connections {
        target: Media
        function onTrackStarted() {
            root.show({ kind: "track" }, 3500);
        }
    }

    // ---------------------------------------------------------------- bluetooth

    Instantiator {
        model: Bluetooth.devices

        Connections {
            required property var modelData
            target: modelData
            function onConnectedChanged() {
                root.show({
                    kind: "message",
                    icon: "bluetooth",
                    title: modelData.name || modelData.deviceName,
                    detail: modelData.connected ? "connected" : "disconnected"
                }, 2500);
            }
        }
    }

    // ---------------------------------------------------------------- battery (laptops)

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isLaptopBattery && battery.isPresent
    readonly property int percent: battery ? Math.round(battery.percentage <= 1 ? battery.percentage * 100 : battery.percentage) : 0
    readonly property bool charging: battery !== null && battery.state !== UPowerDeviceState.Discharging
    property int warnedAt: 101

    onChargingChanged: {
        if (!hasBattery)
            return;
        warnedAt = 101;
        show({ kind: "message", icon: charging ? "charging" : "battery", title: charging ? "Charging" : "On battery", detail: percent + "%" }, 2500);
    }

    onPercentChanged: {
        if (!hasBattery || charging)
            return;
        for (const level of [15, 5]) {
            if (percent <= level && warnedAt > level) {
                warnedAt = level;
                show({ kind: "message", icon: "battery", title: "Battery low", detail: percent + "%", warn: true }, 5000);
            }
        }
    }
}
