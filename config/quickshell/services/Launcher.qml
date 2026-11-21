pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// The launcher (Raycast-style, replaces rofi): which menu is open. Hyprland's keys call
//   qs ipc call launcher toggle <menu>
// with menu = main | clipboard | emoji | files | calc | qr | shared | windows | system |
// screenshot | record | wallpaper ("record" is the screenshot menu with a recording chosen;
// "qr": the QR codes and links found in screenshots; "shared": the Shared Box).
// Any launcher key pressed while it's open closes it. Esc in a menu opened from another
// one (the main menu, mostly) goes back to it.
Singleton {
    id: root

    property bool open: false
    property string mode: "main"
    // The launcher grows out of the dynamic island on its screen and shrinks back into it
    // when it closes (launcher/LauncherWindow.qml). While that runs it's still on screen:
    property bool shown: false
    property string screenName: ""      // the screen it's on
    property real grow: 0               // 0 = the island's shape, 1 = the launcher's
    property var islands: ({})          // each screen's island, by screen name
    property bool fromMain: false       // (opened from another menu: Esc goes back to it)
    property var trail: []              // the menus Esc goes back through

    function show(menu) {
        mode = menu;
        trail = [];
        fromMain = false;
        open = true;
        shown = true;
    }

    // from another menu: Esc comes back
    function enter(menu) {
        trail = trail.concat([mode]);
        mode = menu;
        fromMain = true;
    }

    function back() {
        if (trail.length > 0) {
            mode = trail[trail.length - 1];
            trail = trail.slice(0, -1);
            fromMain = trail.length > 0;
        } else {
            close();
        }
    }

    function close() {
        open = false;
    }

    // (the islands register themselves, bar/DynamicIsland.qml)
    function addIsland(screen, island) {
        islands = Object.assign({}, islands, { [screen]: island });
    }

    // Put something on the clipboard (`copy`: a shell command, with `value` as "$1") and,
    // unless it's `only` copying, paste it into the window you were in once the launcher
    // has closed (scripts/paste.sh). Either way it lands in the clipboard history.
    function deliver(copy, value, only) {
        close();
        Quickshell.execDetached(["sh", "-c", copy + (only ? "" : '; "$2"'), "sh", value,
                                 Quickshell.shellPath("scripts/paste.sh")]);
    }

    // system actions, shared by the main and system menus
    function system(action) {
        close();
        if (action === "lock")
            Lock.lock();
        else if (action === "logout")
            Hyprland.dispatch("hl.dsp.exit()");     // Lua Hyprland syntax
        else
            Quickshell.execDetached(["systemctl", action]);   // suspend, reboot, poweroff
    }

    IpcHandler {
        target: "launcher"

        function toggle(menu: string): void {
            if (root.open)
                root.close();
            else
                root.show(menu || "main");
        }
        function open(menu: string): void {
            root.show(menu || "main");
        }
        function close(): void {
            root.close();
        }
    }
}
