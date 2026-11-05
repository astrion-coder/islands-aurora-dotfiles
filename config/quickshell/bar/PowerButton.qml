import QtQuick
import qs.services
import qs.widgets

// Round power button: lock, log out, suspend, reboot, shut down.
Island {
    id: root

    required property var bar

    padding: 0
    tint: Theme.accent2
    tintStart: 0.10
    tintEnd: 0.30

    Pill {
        implicitWidth: Theme.islandHeight
        implicitHeight: Theme.islandHeight
        cursorShape: Qt.PointingHandCursor
        onClicked: root.bar.togglePopup("power", root)

        Icon {
            anchors.centerIn: parent
            implicitWidth: 13
            implicitHeight: 13
            name: "power"
            color: Theme.accent2
            weight: 2.4
        }
    }
}
