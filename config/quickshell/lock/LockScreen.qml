import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The lock screen (replaces hyprlock): a session lock with a surface on every screen.
// Lock with `qs ipc call lock lock` (Super+Esc, the power menu, the launcher).
WlSessionLock {
    locked: Lock.locked

    LockSurface {}
}
