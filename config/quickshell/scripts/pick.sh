# Choosing what to take, shared by screenshot.sh and record.sh (sourced, not run).
# The picker is slurp in the shell's colours: SHOT_BASE, SHOT_ACCENT, SHOT_ACCENT2
# (#rrggbb; services/Screenshot.qml passes them). Hyprland shows and hides it without a
# fade (hyprland.lua), so it's never in the picture.

# pick area|window|screen: sets `where` to grim's / wf-recorder's arguments for it,
# -g "X,Y WxH" or -o OUTPUT. Returns 1 if you pressed Esc.
#   area     drag a rectangle
#   window   click a window
#   screen   the screen you're on
pick() {
    local base=${SHOT_BASE:-#141218} accent=${SHOT_ACCENT:-#d0bcff} accent2=${SHOT_ACCENT2:-#efb8c8}
    local slurp=(slurp -d -w 2 -b "${base}99" -c "${accent}ff" -s "${accent}1f" -B "${accent2}29" -F "Noto Sans")
    local geometry

    # (the launcher closes first, so it isn't in the picture)
    sleep 0.45

    case "$1" in
        area)
            geometry=$("${slurp[@]}") || return 1
            ;;
        window)
            # the windows on screen now, for slurp to offer (click one)
            geometry=$(hyprctl -j monitors | python3 -c '
import json, subprocess, sys
shown = {m["activeWorkspace"]["id"] for m in json.load(sys.stdin)}
for c in json.loads(subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True).stdout):
    if c["mapped"] and not c["hidden"] and c["workspace"]["id"] in shown:
        (x, y), (w, h) = c["at"], c["size"]
        print(f"{x},{y} {w}x{h}")' | "${slurp[@]}" -r) || return 1
            ;;
        screen)
            where=(-o "$(hyprctl -j monitors | python3 -c 'import json, sys; print(next(m["name"] for m in json.load(sys.stdin) if m["focused"]))')")
            return 0
            ;;
        *)
            echo "${0##*/}: area, window or screen" >&2
            exit 2
            ;;
    esac
    where=(-g "$geometry")
}

# countdown SECONDS WHAT: counted down in the island ("WHAT in 3"), and out of the way
# before it starts
countdown() {
    if [ "$1" -gt 0 ] 2>/dev/null; then
        for ((i = $1; i > 0; i--)); do
            qs ipc call screenshot tick "$i" "$2" >/dev/null 2>&1
            sleep 1
        done
        qs ipc call screenshot tick 0 "$2" >/dev/null 2>&1
        sleep 0.3
    else
        sleep 0.1     # (a frame for the picker to leave the screen)
    fi
}
