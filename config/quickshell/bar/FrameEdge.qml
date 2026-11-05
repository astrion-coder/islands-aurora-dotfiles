import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Keeps windows off one side of the frame (Bar.qml draws the frame; this only reserves
// its width, so Hyprland lays windows out inside it). Invisible, and clicks go through.
// The top one reserves down to the bottom of the dynamic island instead, so windows start
// below it (the usual gap under it) and it never covers them; the frame itself stays as
// thick as on the other sides, with the island hanging into the wallpaper above them.
PanelWindow {
    id: root

    required property string edge       // "top", "bottom", "left" or "right"

    anchors {
        top: edge !== "bottom"
        bottom: edge !== "top"
        left: edge !== "right"
        right: edge !== "left"
    }
    readonly property int reserve: edge === "top" ? Theme.barHeight : Theme.frame

    implicitWidth: reserve
    implicitHeight: reserve
    exclusiveZone: reserve
    color: "transparent"
    mask: Region {}

    WlrLayershell.namespace: "frame-edge"
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
}
