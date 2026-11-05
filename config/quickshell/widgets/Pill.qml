import QtQuick
import qs.services

// A hoverable pill inside an island (cpu, mem, sound, tray icons, ...): lightens on
// hover and shows `tooltip` below the bar after a moment.
MouseArea {
    id: root

    property var bar                 // the Bar window, which draws tooltips
    property string tooltip
    property bool highlighted: containsMouse

    implicitHeight: 28
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.hover
        opacity: root.highlighted ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    onContainsMouseChanged: {
        if (!bar)
            return;
        if (containsMouse && tooltip)
            bar.showTip(root, tooltip);
        else
            bar.hideTip(root);
    }
    onTooltipChanged: if (bar) bar.updateTip(root, tooltip)
}
