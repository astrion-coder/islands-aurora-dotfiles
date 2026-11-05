import QtQuick
import Quickshell.Wayland

// One screen of the lock screen.
WlSessionLockSurface {
    color: "black"

    LockContent {
        anchors.fill: parent
    }
}
