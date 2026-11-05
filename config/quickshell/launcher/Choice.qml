import QtQuick
import qs.services
import qs.widgets

// A small pill in the launcher's panels (ScreenshotPanel.qml, WallpaperPanel.qml): a word,
// and maybe an icon, lit when it's on; or, never on, a button.
MouseArea {
    id: pill

    property string text
    property string icon: ""
    property bool on: false

    implicitWidth: row.implicitWidth + 22
    implicitHeight: 30
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        radius: Theme.pillRadius
        color: pill.on ? Theme.alpha(Theme.accent, 0.22) : Theme.alpha(Theme.fg, pill.containsMouse ? 0.10 : 0.05)
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: pill.icon !== ""
            name: pill.icon
            implicitWidth: 14
            implicitHeight: 14
            color: pill.on || pill.containsMouse ? Theme.accent : Theme.subtle
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.text
            font.pixelSize: 13
            font.weight: pill.on ? Font.Bold : Font.Medium
            color: pill.on ? Theme.accent : Theme.subtle
        }
    }
}
