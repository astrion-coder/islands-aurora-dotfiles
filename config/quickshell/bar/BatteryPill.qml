import QtQuick
import Quickshell.Services.UPower
import qs.services
import qs.widgets

// Laptop battery (hidden on desktops). Click switches between percentage and time left.
Pill {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property real percent: device ? (device.percentage <= 1 ? device.percentage * 100 : device.percentage) : 0
    readonly property bool charging: device !== null && device.state !== UPowerDeviceState.Discharging
    readonly property bool critical: percent <= 15 && !charging
    readonly property real seconds: charging ? device?.timeToFull ?? 0 : device?.timeToEmpty ?? 0
    property bool showTime: false

    function duration(s) {
        const h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60);
        return h > 0 ? `${h} h ${m} min` : `${m} min`;
    }

    visible: device !== null && device.isLaptopBattery && device.isPresent
    implicitWidth: 39 + text.implicitWidth + 10
    cursorShape: Qt.PointingHandCursor
    tooltip: seconds > 0 ? (charging ? "Time to full: " : "Time to empty: ") + duration(seconds)
                         : charging ? "Charging" : ""
    onClicked: showTime = !showTime

    // battery outline, filled to the charge level (waybar's five steps)
    Item {
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: 11

        Rectangle {
            anchors.fill: parent
            anchors.margins: 0.75
            radius: 2.25
            color: "transparent"
            border.width: 1.5
            border.color: Theme.subtle
        }
        Rectangle {
            x: 2.5
            y: 2.5
            height: 6
            radius: 1
            width: root.charging || root.percent > 87 ? 17 : root.percent > 62 ? 13
                 : root.percent > 37 ? 8.5 : root.percent > 15 ? 4.5 : 2
            color: root.charging ? Theme.accent : root.percent > 15 ? Theme.accent2 : Theme.error
        }
    }

    // critical and not charging: the text blinks red
    property bool blink: false
    Timer {
        interval: 500
        repeat: true
        running: root.critical
        onTriggered: root.blink = !root.blink
        onRunningChanged: root.blink = false
    }

    Label {
        id: text
        x: 39
        anchors.verticalCenter: parent.verticalCenter
        text: root.showTime && root.seconds > 0 ? root.duration(root.seconds) : Math.round(root.percent) + "%"
        color: root.blink ? Theme.error : Theme.fg
        Behavior on color { ColorAnimation { duration: 400 } }
        halo: true
    }
}
