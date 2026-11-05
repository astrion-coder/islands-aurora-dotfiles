import QtQuick
import Quickshell.Widgets
import qs.services

// Album art, rounded; a music note on the accent gradient when there's none.
ClippingRectangle {
    id: root

    property string source

    color: "transparent"

    Rectangle {
        anchors.fill: parent
        visible: cover.status !== Image.Ready
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.accent }
            GradientStop { position: 1; color: Theme.accent2 }
        }

        Icon {
            anchors.centerIn: parent
            implicitWidth: Math.round(parent.width * 0.5)
            implicitHeight: implicitWidth
            name: "music"
            color: Theme.ink
            weight: 2.4
        }
    }

    Image {
        id: cover
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: root.width * 2
        sourceSize.height: root.height * 2
    }
}
