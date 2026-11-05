import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
import "fuzzy.js" as Fuzzy

// Open windows; Enter (or a click) focuses one, switching workspace if needed.
Mode {
    id: root

    prompt: "windows"
    placeholder: "search windows…"
    rows: Fuzzy.filter(Hyprland.toplevels.values
        .filter(t => t.wayland)
        .map(t => {
            const app = t.wayland.appId;
            return {
                title: t.title || app,
                subtitle: t.workspace ? "workspace " + t.workspace.name : "",
                meta: app,
                icon: DesktopEntries.heuristicLookup(app)?.icon ?? app,
                address: t.address,
                toplevel: t.wayland
            };
        }), query)

    function opened() {
        Hyprland.refreshToplevels();
    }

    function activate(row, how) {
        if (!row)
            return;
        Launcher.close();
        // Hyprland focuses it itself (it can ignore a window's own request to be focused)
        if (row.address)
            Hyprland.dispatch(`hl.dsp.focus({ window = "address:${row.address.startsWith("0x") ? "" : "0x"}${row.address}" })`);
        else
            row.toplevel.activate();
    }
}
