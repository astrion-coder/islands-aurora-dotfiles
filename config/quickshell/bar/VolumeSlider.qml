import QtQuick
import QtQuick.Layouts
import qs.services
import qs.widgets

// Volume of the default output: drag or scroll the track; click the icon to mute.
Item {
    id: root

    Layout.fillWidth: true
    implicitWidth: 240
    implicitHeight: 36

    MouseArea {
        id: iconButton
        x: 4
        width: 30
        height: parent.height
        cursorShape: Qt.PointingHandCursor
        onClicked: Audio.toggleMute()

        Icon {
            anchors.centerIn: parent
            implicitWidth: 16
            implicitHeight: 16
            name: (Audio.bluetooth ? "bluetooth" : "volume") + (Audio.muted ? "-muted" : "")
            color: Audio.muted ? Theme.muted : Theme.accent
        }
    }

    Item {
        id: track
        anchors.left: iconButton.right
        anchors.leftMargin: 8
        anchors.right: percent.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 20

        readonly property real level: Math.min(1, Audio.volume)

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 6
            radius: 3
            color: Qt.rgba(1, 1, 1, 0.15)
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(height, parent.width * track.level)
            height: 6
            radius: 3
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Audio.muted ? Theme.muted : Theme.accent }
                GradientStop { position: 1; color: Audio.muted ? Theme.muted : Theme.accent2 }
            }
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width * track.level - width / 2
            width: 14
            height: 14
            radius: 7
            color: Theme.fg
            scale: drag.pressed || drag.containsMouse ? 1.15 : 1
            Behavior on scale { NumberAnimation { duration: 100 } }
        }

        MouseArea {
            id: drag
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => Audio.setVolume((mouse.x - 4) / track.width)
            onPositionChanged: mouse => { if (pressed) Audio.setVolume((mouse.x - 4) / track.width); }
            onWheel: wheel => Audio.setVolume(Math.round((Audio.volume + 0.05 * Math.sign(wheel.angleDelta.y)) * 20) / 20)
        }
    }

    Label {
        id: percent
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: probe.width
        horizontalAlignment: Text.AlignRight
        text: Math.round(Audio.volume * 100) + "%"
        color: Audio.muted ? Theme.muted : Theme.fg

        TextMetrics {
            id: probe
            font: percent.font
            text: "100%"
        }
    }
}
