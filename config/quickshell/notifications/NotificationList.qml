import QtQuick
import QtQuick.Layouts
import qs.services
import qs.widgets

// The open island's unread notifications, newest first, with "clear all". Scrolls once
// there are more than fit.
ColumnLayout {
    id: root

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Label {
            text: "Notifications"
            font.weight: Font.Bold
        }
        Label {
            text: Notifs.count
            color: Theme.muted
        }
        Item { Layout.fillWidth: true }
        MouseArea {
            id: clear
            implicitWidth: clearLabel.implicitWidth + 20
            implicitHeight: 24
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Notifs.dismissAll()

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(1, 1, 1, clear.containsMouse ? 0.18 : 0.08)
            }
            Label {
                id: clearLabel
                anchors.centerIn: parent
                text: "Clear all"
                color: Theme.subtle
                font.pixelSize: 12
            }
        }
    }

    Flickable {
        Layout.fillWidth: true
        Layout.preferredWidth: 320          // (sets the list's width)
        Layout.preferredHeight: Math.min(items.implicitHeight, 340)
        contentHeight: items.implicitHeight
        interactive: contentHeight > height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: items
            width: parent.width
            spacing: 6

            Repeater {
                model: Notifs.list

                NotificationItem {}
            }
        }
    }
}
