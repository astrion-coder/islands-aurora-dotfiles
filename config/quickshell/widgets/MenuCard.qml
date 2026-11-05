import QtQuick
import QtQuick.Layouts
import qs.services

// A frosted menu: a column of MenuItems / MenuSeparators. Scrolls when it would be
// taller than maxHeight.
Card {
    id: root

    default property alias items: column.data
    property real minWidth: 180
    property real maxHeight: 600

    implicitWidth: Math.max(minWidth, column.implicitWidth + 12)
    implicitHeight: Math.min(maxHeight, column.implicitHeight + 12)

    Flickable {
        anchors.fill: parent
        anchors.margins: 6
        contentHeight: column.implicitHeight
        interactive: contentHeight > height
        clip: interactive
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 0
        }
    }
}
