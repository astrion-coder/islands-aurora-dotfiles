import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Widgets
import qs.services
import qs.widgets

// The open island's media panel: a rounded card on a blurred copy of the cover, with the
// cover and, centred beside it, the title, artist, player and the visualizer; a progress
// bar you can click to seek; and previous / play-pause / next. With no player it says
// nothing's playing. It fills the height it's given, its contents centred in it.
Item {
    id: root

    readonly property var player: Media.player
    readonly property real length: player?.lengthSupported ? player.length : 0
    readonly property int pad: 16

    implicitWidth: 290 + 2 * pad
    implicitHeight: (player ? playing.implicitHeight : nothing.implicitHeight + 24) + 2 * pad

    component Control: MouseArea {
        id: control
        property string icon
        property real size: 34
        property bool primary: false
        implicitWidth: size
        implicitHeight: size
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            visible: control.primary
            scale: control.pressed ? 0.94 : control.containsMouse ? 1.06 : 1
            Behavior on scale { NumberAnimation { duration: 120 } }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.accent }
                GradientStop { position: 1; color: Theme.accent2 }
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            visible: !control.primary
            color: Qt.rgba(1, 1, 1, control.containsMouse ? 0.14 : 0)
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Icon {
            anchors.centerIn: parent
            implicitWidth: control.primary ? 16 : 15
            implicitHeight: implicitWidth
            name: control.icon
            color: control.primary ? Theme.ink : Theme.fg
            filled: true
            weight: 1.8
        }
    }

    // ---------------------------------------------------------------- the card
    ClippingRectangle {
        anchors.fill: parent
        radius: Theme.tabRadius
        color: Theme.alpha(Theme.fg, 0.05)

        // the cover, blurred (larger than the card: a blur fades out at its own edges)
        Image {
            id: backdrop
            anchors.centerIn: parent
            width: parent.width + 120
            height: parent.height + 120
            source: root.player ? Media.art : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 160       // (blurred anyway: small is plenty)
            sourceSize.height: 160
            visible: false
        }
        MultiEffect {
            anchors.fill: backdrop
            source: backdrop
            opacity: backdrop.status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 64
            saturation: 0.2
        }
        // darkened, so the words on it stay readable
        Rectangle {
            anchors.fill: parent
            color: Theme.alpha(Theme.base, 0.5)
            opacity: backdrop.status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: Theme.tabRadius
        color: "transparent"
        border.width: 1
        border.color: Theme.alpha(Theme.fg, 0.08)
    }

    // ---------------------------------------------------------------- something to play
    ColumnLayout {
        id: playing
        visible: root.player !== null
        anchors.centerIn: parent
        width: parent.width - 2 * root.pad
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Art {
                implicitWidth: 76
                implicitHeight: 76
                radius: 14
                source: Media.art
            }

            // (centred beside the cover)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Label {
                    Layout.fillWidth: true
                    text: Media.title || root.player?.identity || "Nothing playing"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: Media.artist
                    color: Theme.subtle
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: root.player?.identity ?? ""
                    color: Theme.muted
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Visualizer {
                    Layout.topMargin: 6
                    count: 24
                    barWidth: 4
                    gap: 3
                    implicitHeight: 18
                }
            }
        }

        // progress (click to jump)
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.length > 0
            spacing: 4

            Item {
                Layout.fillWidth: true
                implicitHeight: 10

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Qt.rgba(1, 1, 1, 0.15)
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * Math.min(1, (root.player?.position ?? 0) / Math.max(root.length, 1))
                    height: 4
                    radius: 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.accent }
                        GradientStop { position: 1; color: Theme.accent2 }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.player?.canSeek ?? false
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: mouse => root.player.position = root.length * mouse.x / width
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: Media.time(root.player?.position ?? 0)
                    color: Theme.subtle
                    font.pixelSize: 12
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: Media.time(root.length)
                    color: Theme.subtle
                    font.pixelSize: 12
                }
            }
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 18

            Control {
                anchors.verticalCenter: parent.verticalCenter
                icon: "previous"
                enabled: root.player?.canGoPrevious ?? false
                opacity: enabled ? 1 : 0.4
                onClicked: root.player.previous()
            }
            Control {
                anchors.verticalCenter: parent.verticalCenter
                icon: Media.playing ? "pause" : "play"
                primary: true
                size: 42
                enabled: root.player?.canTogglePlaying ?? false
                onClicked: root.player.togglePlaying()
            }
            Control {
                anchors.verticalCenter: parent.verticalCenter
                icon: "next"
                enabled: root.player?.canGoNext ?? false
                opacity: enabled ? 1 : 0.4
                onClicked: root.player.next()
            }
        }
    }

    // ---------------------------------------------------------------- nothing
    // (laid out like a song: a cover-sized tile, and the words beside it, left-aligned)
    RowLayout {
        id: nothing
        visible: root.player === null
        anchors.centerIn: parent
        width: parent.width - 2 * root.pad
        spacing: 14

        Rectangle {
            implicitWidth: 76
            implicitHeight: 76
            radius: 14
            color: Theme.alpha(Theme.fg, 0.07)

            Icon {
                anchors.centerIn: parent
                implicitWidth: 30
                implicitHeight: 30
                name: "music"
                color: Theme.muted
                weight: 1.8
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Label {
                Layout.fillWidth: true
                text: "No media playing"
                font.pixelSize: 15
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                text: "Play something in any app"
                color: Theme.subtle
                font.pixelSize: 13
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                text: "and it shows up here"
                color: Theme.muted
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }
    }
}
