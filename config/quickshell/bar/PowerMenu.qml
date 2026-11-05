import QtQuick
import Quickshell.Hyprland
import qs.services
import qs.widgets

MenuCard {
    id: root

    required property var bar

    minWidth: 160

    MenuItem {
        markColumn: false
        text: "Lock"
        onClicked: {
            root.bar.closePopup();
            Lock.lock();
        }
    }
    MenuItem {
        markColumn: false
        text: "Log out"
        onClicked: {
            root.bar.closePopup();
            Hyprland.dispatch("hl.dsp.exit()");   // Lua Hyprland syntax
        }
    }
    MenuItem {
        markColumn: false
        text: "Suspend"
        onClicked: root.bar.run(["systemctl", "suspend"])
    }
    MenuSeparator {}
    MenuItem {
        markColumn: false
        text: "Reboot"
        onClicked: root.bar.run(["systemctl", "reboot"])
    }
    MenuItem {
        markColumn: false
        text: "Shut down"
        onClicked: root.bar.run(["systemctl", "poweroff"])
    }
}
