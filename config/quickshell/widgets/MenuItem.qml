import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services

// One menu row: [mark or icon]  text  [detail] [›]
MouseArea {
    id: root

    property string text
    property string mark             // "✓", "●", ... in the left column
    property string iconSource       // or an icon there
    property bool markColumn: true   // reserve the left column (keeps rows aligned)
    property string detail           // right-aligned, dimmer (battery %, ...)
    property bool submenu: false

    Layout.fillWidth: true
    implicitWidth: row.implicitWidth + 24
    implicitHeight: 31
    hoverEnabled: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Theme.alpha(Theme.accent, 0.18)
        opacity: root.containsMouse && root.enabled ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 100 } }
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 12

        Item {
            visible: root.markColumn
            implicitWidth: 18
            implicitHeight: 18

            Label {
                anchors.centerIn: parent
                visible: root.mark !== ""
                text: root.mark
                color: Theme.accent
            }
            IconImage {
                anchors.centerIn: parent
                visible: root.mark === "" && root.iconSource !== ""
                source: root.iconSource
                implicitSize: 16
            }
        }

        Label {
            Layout.fillWidth: true
            text: root.text
            color: root.enabled ? Theme.fg : Theme.muted
            elide: Text.ElideRight
        }

        Label {
            visible: root.detail !== ""
            text: root.detail
            color: Theme.subtle
        }

        Label {
            visible: root.submenu
            text: "›"
            color: Theme.subtle
        }
    }
}
