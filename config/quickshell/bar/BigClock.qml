import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.widgets

// The time, large, beside the island's calendar: hours and minutes, the seconds ticking
// beside them, then the day and the date, and where the day falls in the year.
ColumnLayout {
    id: root

    property bool running: true              // (ticks only while it's on show)
    readonly property date now: clock.date
    readonly property int dayOfYear: Math.round((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(now.getFullYear(), 0, 1)) / 86400000) + 1
    readonly property int week: {
        const t = new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        return Math.ceil(((t - Date.UTC(t.getUTCFullYear(), 0, 1)) / 86400000 + 1) / 7);
    }

    spacing: 0

    SystemClock {
        id: clock
        enabled: root.running
        precision: SystemClock.Seconds
    }

    Row {
        spacing: 6

        Label {
            id: time
            text: Qt.formatTime(root.now, "HH:mm")
            font.pixelSize: 64
            font.weight: Font.Bold
            font.letterSpacing: -1.5
            lineHeight: 0.9
        }
        Label {
            anchors.baseline: time.baseline
            text: Qt.formatTime(root.now, "ss")
            font.pixelSize: 22
            font.weight: Font.Bold
            color: Theme.accent
        }
    }

    Label {
        Layout.topMargin: 6
        text: Qt.formatDate(root.now, "dddd")
        font.pixelSize: 19
        font.weight: Font.Bold
        color: Theme.accent2
    }
    Label {
        text: Qt.formatDate(root.now, "d MMMM yyyy")
        font.pixelSize: 16
        color: Theme.subtle
    }

    // how far through the year
    Item {
        Layout.topMargin: 14
        Layout.fillWidth: true
        implicitHeight: 4

        Rectangle {
            anchors.fill: parent
            radius: 2
            color: Theme.alpha(Theme.fg, 0.10)
        }
        Rectangle {
            width: parent.width * root.dayOfYear / (new Date(root.now.getFullYear(), 1, 29).getMonth() === 1 ? 366 : 365)
            height: parent.height
            radius: 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.accent }
                GradientStop { position: 1; color: Theme.accent2 }
            }
        }
    }
    Label {
        Layout.topMargin: 6
        text: `week ${root.week}, day ${root.dayOfYear} of the year`
        font.pixelSize: 13
        color: Theme.muted
    }
}
