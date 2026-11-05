import QtQuick
import qs.services

// Audio visualizer: rounded bars, centred, accent to accent2, moving with what's playing
// (cava, via Spectrum). With no sound the bars rest as small dots.
Item {
    id: root

    property int count: 6
    property real barWidth: 3
    property real gap: 2

    // Spectrum's bars, averaged down to `count`
    readonly property var values: {
        const src = Spectrum.bars, per = src.length / count, out = [];
        for (let i = 0; i < count; i++) {
            let sum = 0;
            for (let j = Math.floor(i * per); j < Math.floor((i + 1) * per); j++)
                sum += src[j];
            out.push(Math.pow(sum / Math.max(1, Math.floor((i + 1) * per) - Math.floor(i * per)), 0.8));
        }
        return out;
    }

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }

    implicitWidth: count * barWidth + (count - 1) * gap
    implicitHeight: 16

    Repeater {
        model: root.count

        Rectangle {
            required property int index

            x: index * (root.barWidth + root.gap)
            anchors.verticalCenter: parent.verticalCenter
            width: root.barWidth
            height: Math.max(root.barWidth, (root.values[index] ?? 0) * root.height)
            radius: width / 2
            color: root.mix(Theme.accent, Theme.accent2, root.count > 1 ? index / (root.count - 1) : 0)
            opacity: Spectrum.active ? 1 : 0.45
            Behavior on height { NumberAnimation { duration: 70 } }
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }
    }
}
