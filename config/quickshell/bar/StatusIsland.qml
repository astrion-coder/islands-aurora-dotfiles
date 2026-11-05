import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import qs.services
import qs.widgets

// Tray icons, sound and battery in one island.
Island {
    id: root

    required property var bar

    tint: Theme.accent2
    tintEnd: 0.28

    Repeater {
        model: SystemTray.items

        TrayItem {
            bar: root.bar
            Layout.topMargin: 4
            Layout.bottomMargin: 4
        }
    }

    SoundPill {
        bar: root.bar
        Layout.topMargin: 4
        Layout.bottomMargin: 4
    }

    BatteryPill {
        bar: root.bar
        Layout.topMargin: 4
        Layout.bottomMargin: 4
    }
}
