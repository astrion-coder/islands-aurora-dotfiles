import QtQuick
import qs.services
import qs.widgets

// Maths, conversions, time zones and deadlines from the main menu: what you typed on the
// left, the answer on the right (already copied). Enter pastes it where you were, Alt+1
// only copies it, Esc goes back.
Column {
    id: root

    property var answer: []     // title, query, caption, answer, caption

    spacing: 12

    Item {
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
            rightPadding: 6
            text: "copied, Enter pastes it"
            color: Theme.muted
            font.pixelSize: 13
        }
    }

    Rectangle {
        width: parent.width
        height: 150
        radius: 16
        color: Theme.alpha(Theme.fg, 0.08)

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
