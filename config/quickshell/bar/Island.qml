import QtQuick
import QtQuick.Layouts
import qs.services

// One of the bar's pills (the frame's tab around it, Bar.qml, is its background), with an
// optional accent gradient.
Item {
    id: root

    default property alias content: row.data
    property real padding: 6
    property color tint: "transparent"   // gradient colour, from tintStart to tintEnd alpha
    property real tintStart: 0
    property real tintEnd: 0
    property bool lit: false             // the whole island lights up (date / time on hover)
    readonly property bool hovered: hover.hovered
    readonly property real radius: Theme.pillRadius

    implicitWidth: row.implicitWidth + 2 * padding
    implicitHeight: Theme.islandHeight

    // (the tint reaches up to the frame's edge, so it starts on the same line as the frame
    // instead of a little below it)
    Rectangle {
        y: -Theme.tabPad
        width: parent.width
        height: parent.height + Theme.tabPad
        radius: root.radius
        visible: root.tintStart > 0 || root.tintEnd > 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.alpha(root.tint, root.tintStart) }
            GradientStop { position: 1; color: Theme.alpha(root.tint, root.tintEnd) }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.hover
        opacity: root.lit ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    HoverHandler {
        id: hover
    }

    RowLayout {
        id: row
        x: root.padding
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
    }
}
