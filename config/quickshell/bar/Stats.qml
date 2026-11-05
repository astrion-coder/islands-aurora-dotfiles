import QtQuick
import QtQuick.Layouts
import qs.services
import qs.widgets

// cpu and memory use. (Tinted like the tray group on the island's other side, mirrored:
// strongest at its outer edge.)
Island {
    id: root

    required property var bar

    tint: Theme.accent
    tintStart: 0.28

    component Stat: Pill {
        id: stat
        property string label
        property string value
        bar: root.bar
        implicitWidth: row.implicitWidth + 20
        Layout.topMargin: 4
        Layout.bottomMargin: 4

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8

            Label {
                text: stat.label
                color: Theme.alpha(Theme.fg, 0.55)
                halo: true
            }
            Label {
                text: stat.value
                halo: true
            }
        }
    }

    Stat {
        label: "cpu"
        value: Math.round(SysStats.cpu) + "%"
    }

    Stat {
        label: "mem"
        value: SysStats.memUsed.toFixed(1) + "G"
        tooltip: `${SysStats.memUsed.toFixed(1)}G / ${SysStats.memTotal.toFixed(1)}G`
                 + ` (${Math.round(100 * SysStats.memUsed / Math.max(SysStats.memTotal, 1))}%)`
    }
}
