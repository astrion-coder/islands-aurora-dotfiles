import QtQuick
import QtQuick.Layouts
import qs.services
import qs.widgets

// An icon and a word before a row of choices or tiles in the launcher's panels
// (ScreenshotPanel.qml, WallpaperPanel.qml); `strong` for a section's heading.
Row {
    id: caption

    property string icon
    property string text
    property bool strong: false

    spacing: 7
    Layout.rightMargin: 4

    Icon {
        anchors.verticalCenter: parent.verticalCenter
        name: caption.icon
        color: caption.strong ? Theme.accent : Theme.muted
        implicitWidth: 16
        implicitHeight: 16
    }
    Label {
        anchors.verticalCenter: parent.verticalCenter
        text: caption.text
        font.pixelSize: caption.strong ? 14 : 13
        font.weight: caption.strong ? Font.Bold : Font.Normal
        color: caption.strong ? Theme.fg : Theme.muted
    }
}
