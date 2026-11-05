pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Screenshots and screen recordings: the screenshot and recording menu
// (launcher/ScreenshotPanel.qml: Super+Shift+P or Print) and the Shift/Alt/Ctrl+Print keys
// come here. scripts/screenshot.sh and scripts/record.sh do the picking (in the shell's
// colours), the picture or the video, the clipboard and the file, and count a delay
// down in the island. While a recording runs, the island shows a red dot and the time
// (widgets/IslandCompact.qml; click it to stop).
//   qs ipc call screenshot area|window|screen            take one now (the Print keys)
//   qs ipc call screenshot record area|window|screen     start recording, or stop the one going
//   qs ipc call screenshot stop                          stop recording
Singleton {
    id: root

    readonly property var delays: [0, 3, 5, 10]
    property int delay: 0                 // seconds (the menu's choices, kept between uses)
    property bool edit: false             // draw on it straight after
    readonly property var sounds: ["none", "system", "mic"]
    property string sound: "none"         // in a recording: none, what you hear, or the microphone

    // a recording going (record.sh says so; checked again when the shell starts)
    property bool recording: false
    property real startedAt: 0            // ms
    readonly property int elapsed: recording ? Math.max(0, Math.round((clock.date.getTime() - startedAt) / 1000)) : 0
    readonly property string elapsedText: {
        const h = Math.floor(elapsed / 3600), m = Math.floor(elapsed / 60) % 60, s = elapsed % 60;
        const ss = String(s).padStart(2, "0");
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
    }

    // (the picker, in the shell's colours: scripts/pick.sh)
    function run(script, args) {
        Launcher.close();
        Quickshell.execDetached(["env",
            "SHOT_BASE=" + Theme.base, "SHOT_ACCENT=" + Theme.accent, "SHOT_ACCENT2=" + Theme.accent2,
            Quickshell.shellPath("scripts/" + script), ...args]);
    }

    // what: "area", "window" or "screen"
    function take(what, wait, draw) {
        run("screenshot.sh", [what, String(wait ?? 0), draw ? "1" : "0"]);
    }

    // sound: "none", "system" or "mic"
    function record(what, wait, sound) {
        run("record.sh", [what, String(wait ?? 0), sound ?? "none"]);
    }

    function stop() {
        Launcher.close();
        Quickshell.execDetached([Quickshell.shellPath("scripts/record.sh"), "stop"]);
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
        enabled: root.recording
    }

    // one already going (the shell restarted while it recorded)
    Process {
        running: true
        command: ["sh", "-c", 'read -r pid start < "${XDG_RUNTIME_DIR:-/tmp}/shell-recording" && [ "$(cat /proc/$pid/comm)" = wf-recorder ] && echo "$start"']
        stdout: StdioCollector {
            onStreamFinished: {
                const start = parseInt(text);
                if (start > 0) {
                    root.startedAt = start * 1000;
                    root.recording = true;
                }
            }
        }
    }

    IpcHandler {
        target: "screenshot"

        function area(): void {
            root.take("area", 0, false);
        }
        function window(): void {
            root.take("window", 0, false);
        }
        function screen(): void {
            root.take("screen", 0, false);
        }
        // start one (with the menu's sound), or stop the one going
        function record(what: string): void {
            if (root.recording)
                root.stop();
            else
                root.record(what || "area", 0, root.sound);
        }
        function stop(): void {
            root.stop();
        }

        // from the scripts: the countdown ("Screenshot" or "Recording"; 0 clears it before
        // it starts), and a recording starting and ending
        function tick(left: int, what: string): void {
            const video = what === "Recording";
            if (left > 0)
                Activities.show({ kind: "message", icon: video ? "video" : "camera", title: (what || "Screenshot") + " in " + left, detail: "" }, 1500);
            else if (["camera", "video"].includes(Activities.current?.icon))
                Activities.current = null;
        }
        function recordingStarted(): void {
            root.startedAt = Date.now();
            root.recording = true;
        }
        function recordingStopped(): void {
            root.recording = false;
        }
    }
}
