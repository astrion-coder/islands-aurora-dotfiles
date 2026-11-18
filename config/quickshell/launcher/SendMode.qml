import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "fuzzy.js" as Fuzzy

// Sending a file (Launcher.sendFile: Ctrl+Enter on one in Files or the Shared Box) to one of
// your devices over Taildrop, or into the Shared Box, for any of them to download. Enter
// sends it; the island says how it went (scripts/shared-box.py send).
Mode {
    id: root

    readonly property string script: Quickshell.shellPath("scripts/shared-box.py")
    readonly property string name: Launcher.sendFile.split("/").pop()
    property var devices: []        // { address, name, os, online }
    property bool looking: false

    prompt: "send"
    placeholder: "send " + name + " to…"
    hint: looking ? "finding your devices…"
        : devices.length === 0 ? "No devices can take files over Taildrop right now (is Tailscale on?)"
        : current?.box ? "Enter puts it in the Shared Box, to download on any of your devices"
        : current && !current.online ? "It's offline: Taildrop needs it on, with Tailscale running"
        : "Enter sends it over Taildrop"
    rows: Fuzzy.filter([{ box: true, title: "The Shared Box", subtitle: "any of your devices can download it", icon: "folder-download" }]
                       .concat(devices.map(d => ({
                           address: d.address,
                           title: d.name,
                           subtitle: d.online ? d.os : d.os + ", offline",
                           online: d.online,
                           icon: /android|ios/i.test(d.os) ? "smartphone" : /macos|windows|linux/i.test(d.os) ? "computer-laptop" : "network-server"
                       }))), query)

    function opened() {
        devices = [];
        looking = true;
        finder.running = true;
    }

    function activate(row, how) {
        if (!row || Launcher.sendFile === "")
            return;
        if (row.box)
            Quickshell.execDetached([script, "add-file", Launcher.sendFile]);
        else
            Quickshell.execDetached([script, "send", Launcher.sendFile, row.address, row.title]);
        Launcher.close();
    }

    // the devices Taildrop can send to ("100.x.y.z<TAB>name<TAB>status"), with their names
    // and systems from tailscale status
    Process {
        id: finder
        command: ["sh", "-c", "tailscale file cp --targets; echo '<<status>>'; tailscale status --json"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.looking = false;
                const [targets, status] = text.split("<<status>>");
                let peers = {};
                try {
                    peers = JSON.parse(status).Peer ?? {};
                } catch (e) {}
                const byAddress = {};
                for (const p of Object.values(peers))
                    for (const ip of p.TailscaleIPs ?? [])
                        byAddress[ip] = p;
                root.devices = targets.split("\n").filter(l => l.includes("\t")).map(line => {
                    const [address, short, state] = line.split("\t");
                    const p = byAddress[address] ?? {};
                    return {
                        address: address,
                        name: p.HostName || short,
                        os: { android: "Android", macOS: "Mac", iOS: "iPhone", windows: "Windows", linux: "Linux" }[p.OS] ?? (p.OS || ""),
                        online: p.Online ?? !/offline/.test(state ?? "")
                    };
                }).sort((a, b) => b.online - a.online || a.name.localeCompare(b.name));
            }
        }
    }
}
