import QtQuick
import qs.services

// The recording light: a red dot, breathing, that turns into a stop square (`stop`: when
// you point at it, as clicking it stops the recording). The island shows it while the
// screen records, and so does the screenshot menu (services/Screenshot.qml).
Rectangle {
    id: root

    property real size: 8
    property bool stop: false

    implicitWidth: size
    implicitHeight: size
    radius: stop ? size * 0.22 : size / 2
    color: Theme.error
    Behavior on radius { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    SequentialAnimation on opacity {
        running: root.visible && !root.stop
        loops: Animation.Infinite
        onRunningChanged: if (!running) root.opacity = 1
        NumberAnimation { to: 0.35; duration: 800; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
    }
}
