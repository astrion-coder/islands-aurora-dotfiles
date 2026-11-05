import QtQuick
import Quickshell
import qs.services
import qs.widgets

// Sound: speaker or Bluetooth icon and the volume. Click: volume mixer; right click:
// sound menu (volume, mute, Bluetooth on/off and devices); middle click: mute;
// scroll: volume.
Pill {
    id: root

    property real wheelSteps: 0

    implicitWidth: 31 + volume.implicitWidth + 10
    cursorShape: Qt.PointingHandCursor
    tooltip: Audio.name + (Audio.btBattery >= 0 ? `, battery at ${Audio.btBattery}%` : "")

    Icon {
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        name: (Audio.bluetooth ? "bluetooth" : "volume") + (Audio.muted ? "-muted" : "")
        color: Audio.muted ? Theme.muted : Theme.accent
    }

    Label {
        id: volume
        x: 31
        anchors.verticalCenter: parent.verticalCenter
        text: Math.round(Audio.volume * 100) + "%"
        color: Audio.muted ? Theme.muted : Theme.fg
        halo: true
    }

    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton)
            bar.openMixer();
        else if (mouse.button === Qt.RightButton)
            bar.togglePopup("sound", root);
        else
            Audio.toggleMute();
    }

    // 5% per notch; touchpads send many small steps
    onWheel: wheel => {
        wheelSteps += wheel.angleDelta.y / 120;
        const notches = Math.trunc(wheelSteps);
        if (notches !== 0) {
            wheelSteps -= notches;
            Audio.setVolume(Math.round((Audio.volume + 0.05 * notches) * 20) / 20);
        }
    }
}
