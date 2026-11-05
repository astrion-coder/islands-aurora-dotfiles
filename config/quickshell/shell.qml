import QtQuick
import Quickshell
import qs.bar
import qs.launcher
import qs.lock

// Islands Aurora shell: a frame around every screen, its bar showing when you point at
// the top edge (notifications come through its dynamic island), the launcher
// (Super+Space) and the lock screen (Super+Esc).
// Colours: colors.css (generated from the wallpaper by matugen). Restart: Super+D.
ShellRoot {
    // each screen: the frame and its bar, and the frame's width kept free of windows
    Variants {
        model: Quickshell.screens

        Scope {
            id: slot
            required property ShellScreen modelData

            Bar { modelData: slot.modelData }
            FrameEdge { screen: slot.modelData; edge: "top" }
            FrameEdge { screen: slot.modelData; edge: "bottom" }
            FrameEdge { screen: slot.modelData; edge: "left" }
            FrameEdge { screen: slot.modelData; edge: "right" }
        }
    }

    LauncherWindow {}
    LockScreen {}
}
