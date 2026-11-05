import QtQuick
import QtQuick.Effects
import qs.services

// Shell text: the shell font with fixed-width digits (numbers don't wobble). On the bar,
// a soft dark halo keeps it legible over bright spots in the wallpaper.
Text {
    property bool halo: false

    color: Theme.fg
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    font.weight: Font.Medium
    font.features: { "tnum": 1 }
    verticalAlignment: Text.AlignVCenter

    layer.enabled: halo
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.55)
        shadowVerticalOffset: 1
        shadowHorizontalOffset: 0
        shadowBlur: 0.25
        blurMax: 8
    }
}
