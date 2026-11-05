import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.services
import qs.widgets

// One unread notification in the open island. Click: the app's default action (and it's
// read); right click or ×: close it; its buttons: the app's other actions.
Rectangle {
    id: root

    required property Notification modelData
    readonly property Notification n: modelData
    readonly property bool critical: n.urgency === NotificationUrgency.Critical
    readonly property var defaultAction: n.actions.find(a => a.identifier === "default") ?? null
    readonly property var buttons: n.actions.filter(a => a.identifier !== "default")
    readonly property var progress: typeof n.hints.value === "number" ? n.hints.value : null

    width: parent?.width ?? 320
    implicitHeight: content.implicitHeight + 20
    radius: 14
    color: root.critical ? Theme.alpha(Theme.error, 0.16) : Theme.alpha(Theme.fg, mouse.containsMouse ? 0.10 : 0.06)
    border.width: root.critical ? 1 : 0
    border.color: Theme.alpha(Theme.error, 0.5)
    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: root.defaultAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: event => {
            if (event.button === Qt.LeftButton && root.defaultAction)
                root.defaultAction.invoke();
            root.n.dismiss();
        }
    }

    RowLayout {
        id: content
        x: 12
        y: 10
        width: parent.width - 24
        spacing: 12

        // (no icon, or one that can't be found: the text starts at the edge instead)
        IconImage {
            readonly property string icon: Notifs.icon(root.n)
            Layout.alignment: Qt.AlignTop
            visible: icon !== "" && status !== Image.Error
            source: icon
            implicitSize: 30
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    text: root.n.summary || root.n.appName
                    color: root.critical ? Theme.error : Theme.fg
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Label {
                    text: Notifs.ago(root.n)
                    color: Theme.muted
                    font.pixelSize: 11
                    visible: !mouse.containsMouse && !close.containsMouse
                }
                // close
                MouseArea {
                    id: close
                    visible: mouse.containsMouse || containsMouse
                    implicitWidth: 18
                    implicitHeight: 18
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.n.dismiss()

                    Rectangle {
                        anchors.fill: parent
                        radius: 9
                        color: Qt.rgba(1, 1, 1, close.containsMouse ? 0.18 : 0.08)
                    }
                    Label {
                        anchors.centerIn: parent
                        text: "×"
                        color: Theme.subtle
                        font.pixelSize: 13
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.n.body
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                font.pixelSize: 12
                font.weight: Font.Normal
                color: Theme.alpha(Theme.fg, 0.8)
                linkColor: Theme.accent
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            // progress (downloads, ...)
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.progress !== null
                implicitHeight: 5
                radius: 2.5
                color: Qt.rgba(1, 1, 1, 0.15)

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(100, root.progress ?? 0)) / 100
                    height: parent.height
                    radius: 2.5
                    color: root.critical ? Theme.error : Theme.accent
                }
            }

            // the app's actions
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: root.buttons.length > 0
                spacing: 6

                Repeater {
                    model: root.buttons

                    MouseArea {
                        id: action
                        required property var modelData
                        implicitWidth: actionLabel.implicitWidth + 20
                        implicitHeight: 24
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            modelData.invoke();
                            root.n.dismiss();
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Qt.rgba(1, 1, 1, action.containsMouse ? 0.18 : 0.10)
                        }
                        Label {
                            id: actionLabel
                            anchors.centerIn: parent
                            text: action.modelData.text
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }
}
