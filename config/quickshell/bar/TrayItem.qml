import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.services
import qs.widgets

// A tray icon (nm-applet, OpenSnitch, ...). Left click activates it (or opens its menu,
// for menu-only items), right click opens its menu, middle click is the app's secondary
// action.
Pill {
    id: root

    required property SystemTrayItem modelData

    implicitWidth: 34
    implicitHeight: 28
    cursorShape: Qt.PointingHandCursor
    tooltip: modelData.tooltipTitle || modelData.title || modelData.id

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        visible: root.modelData.status === Status.NeedsAttention
        color: Theme.alpha(Theme.error, 0.35)
    }

    IconImage {
        anchors.centerIn: parent
        implicitSize: 15
        source: root.modelData.icon
        opacity: root.modelData.status === Status.Passive ? 0.5 : 1
    }

    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton)
            modelData.secondaryActivate();
        else if (mouse.button === Qt.RightButton || modelData.onlyMenu) {
            if (modelData.hasMenu)
                bar.togglePopup("tray", root, modelData);
        } else
            modelData.activate();
    }
    onWheel: wheel => modelData.scroll(Math.sign(wheel.angleDelta.y || wheel.angleDelta.x), wheel.angleDelta.y === 0)
}
