pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Audio visualizer data: `bars` (0-1, low to high frequencies) from cava, while sound is
// flowing into the default output (any app, not just media players). cava only runs then.
Singleton {
    id: root

    readonly property int count: 24     // matches bars in scripts/cava.conf
    property var bars: zeros()

    readonly property bool active: (links.linkGroups ?? []).some(g => g.target === Audio.sink && g.state === PwLinkState.Active)

    function zeros() {
        return new Array(count).fill(0);
    }

    onActiveChanged: if (!active) bars = zeros()

    PwNodeLinkTracker {
        id: links
        node: Audio.sink
    }
    // (a link's state only stays current while it's tracked)
    PwObjectTracker {
        objects: links.linkGroups ?? []
    }

    Process {
        running: root.active
        command: ["cava", "-p", Quickshell.shellPath("scripts/cava.conf")]
        // one frame per line: "12;40;100;...;"
        stdout: SplitParser {
            onRead: line => {
                const v = line.split(";").filter(s => s !== "").map(n => Math.min(1, Number(n) / 100));
                if (v.length === root.count)
                    root.bars = v;
            }
        }
    }
}
