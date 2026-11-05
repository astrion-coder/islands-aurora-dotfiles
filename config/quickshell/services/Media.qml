pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// The media player the island follows (MPRIS): the one playing, else the one that played
// last. playerctld (a proxy for the others) is left out so nothing shows twice.
Singleton {
    id: root

    readonly property var players: Mpris.players.values.filter(p => !p.dbusName.endsWith(".playerctld"))
    property var last: null
    readonly property var player: players.find(p => p.isPlaying)
        ?? (players.includes(last) ? last : null)
        ?? players.find(p => p.trackTitle !== "")
        ?? null
    onPlayerChanged: if (player?.isPlaying) last = player

    readonly property bool playing: player?.isPlaying ?? false
    readonly property string title: player?.trackTitle ?? ""
    readonly property string artist: player?.trackArtist ?? ""
    readonly property string art: player?.trackArtUrl ?? ""

    // a new song started (the island shows it for a moment)
    signal trackStarted

    Connections {
        target: root.player
        function onTrackTitleChanged() {
            if (root.player.isPlaying && root.title !== "")
                root.trackStarted();
        }
        function onIsPlayingChanged() {
            if (root.player.isPlaying)
                root.last = root.player;
        }
    }

    // MPRIS doesn't announce the position while playing: ask once a second
    Timer {
        interval: 1000
        repeat: true
        running: root.playing
        onTriggered: root.player.positionChanged()
    }

    function time(seconds) {
        const s = Math.max(0, Math.floor(seconds));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
}
