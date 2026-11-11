import QtQuick
import qs.services
import qs.widgets

// The main menu's answer to maths, conversions, time zones and deadlines, worked out as
// you type (MainMode.qml), on top of the list: what you typed on the left, the answer on
// the right. Picked (ringed), Enter pastes it where you were and Alt+1 only copies it;
// a click pastes it.
Item {
    id: root

    property var answer: []     // title, query, caption, answer, caption
    property bool picked: true
    signal chosen

    implicitHeight: 188

    Item {
        id: top
        width: parent.width
        height: title.implicitHeight

        Label {
            id: title
            leftPadding: 6
            text: root.answer[0] ?? ""
            color: Theme.muted
        }
        Label {
            anchors.right: parent.right
            anchors.baseline: title.baseline
            rightPadding: 6
            text: root.picked ? "Enter pastes it, Alt+1 copies it" : "↑ for the answer"
            color: Theme.muted
            font.pixelSize: 13
        }
    }

    Rectangle {
        id: box
        y: top.height + 12
        width: parent.width
        height: root.height - y
        radius: 16
        color: Theme.alpha(Theme.fg, root.picked || click.containsMouse ? 0.10 : 0.06)
        border.width: root.picked ? 1.5 : 0
        border.color: Theme.alpha(Theme.accent, 0.6)

        MouseArea {
            id: click
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.chosen()
        }

        component Side: Column {
            id: side
            property string main
            property string caption
            property color color: Theme.fg
            width: (root.width - 24 * 2 - 16 * 2 - arrow.width) / 2
            spacing: 14

            Label {
                width: side.width
                horizontalAlignment: Text.AlignHCenter
                text: side.main
                textFormat: Text.PlainText
                color: side.color
                font.pixelSize: 34
                font.weight: Font.Bold
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 16
            }
            Label {
                width: side.width
                horizontalAlignment: Text.AlignHCenter
                text: side.caption
                textFormat: Text.PlainText
                color: Theme.muted
                font.pixelSize: 13
                elide: Text.ElideRight
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: 16

            Side {
                anchors.verticalCenter: parent.verticalCenter
                main: root.answer[1] ?? ""
                caption: root.answer[2] ?? ""
            }
            Label {
                id: arrow
                anchors.verticalCenter: parent.verticalCenter
                text: "→"
                color: Theme.muted
                font.pixelSize: 26
                font.weight: Font.Bold
            }
            Side {
                anchors.verticalCenter: parent.verticalCenter
                main: root.answer[3] ?? ""
                caption: root.answer[4] ?? ""
                color: Theme.accent
            }
        }
    }
}
