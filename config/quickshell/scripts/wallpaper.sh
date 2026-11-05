#!/bin/bash
# Set the wallpaper, with a transition picked at random each time (the shell's picker
# runs this: quickshell/launcher/WallpaperPanel.qml; so can you):
#   wallpaper.sh FILE [wave|wipe|grow|outer|fade]     (a kind: always that kind)
# The kinds, each with its angle, size or starting point picked at random too:
#   wave    a wavy edge sweeping across, from any side
#   wipe    a straight edge sweeping across, from any side
#   grow    a circle spreading out from the pointer (where you clicked), the island, the
#           middle or anywhere
#   outer   a circle closing in on one of those
#   fade    a soft cross-fade (now and then)
# awww draws it; hypr/scripts/wallpaper-theme.sh notices and re-themes everything from it.

file=$1
kind=$2
if [ ! -f "$file" ]; then
    echo "wallpaper.sh: no such picture: $file" >&2
    exit 1
fi

pick() { local all=("$@"); printf '%s' "${all[RANDOM % ${#all[@]}]}"; }

# as smooth as the fastest screen
fps=$(hyprctl -j monitors 2>/dev/null \
      | python3 -c 'import json, sys; print(round(max(m["refreshRate"] for m in json.load(sys.stdin))))' 2>/dev/null)
[[ $fps =~ ^[0-9]+$ ]] || fps=60

# the pointer on its screen, in pixels from the top left ("x,y"; nothing if it's unknown)
pointer() {
    hyprctl -j monitors 2>/dev/null | python3 -c '
import json, subprocess, sys
x, y = (float(v) for v in subprocess.run(["hyprctl", "cursorpos"], capture_output=True, text=True).stdout.split(","))
for m in json.load(sys.stdin):
    w, h = m["width"] / m["scale"], m["height"] / m["scale"]
    if m["x"] <= x < m["x"] + w and m["y"] <= y < m["y"] + h:
        print("%d,%d" % ((x - m["x"]) * m["scale"], (y - m["y"]) * m["scale"]))' 2>/dev/null
}

# where a circle starts (grow) or ends (outer)
spot() {
    local p
    case $(pick pointer pointer island middle anywhere) in
        pointer) if p=$(pointer) && [ -n "$p" ]; then
                     where=(--transition-pos "$p" --invert-y)       # (y from the top)
                     return
                 fi
                 where=(--transition-pos top) ;;
        island)  where=(--transition-pos top) ;;
        middle)  where=(--transition-pos center) ;;
        *)       where=(--transition-pos "0.$((10 + RANDOM % 80)),0.$((10 + RANDOM % 80))") ;;
    esac
}

# (curves: all slow in and out, some more than others)
ease=$(pick .65,0,.35,1 .45,0,.2,1 .7,0,.3,1 .3,.1,.2,1)
angle=$((RANDOM % 360))
case ${kind:-$(pick wave wave wave wipe wipe grow grow grow outer outer fade)} in
    wave)  args=(--transition-type wave --transition-angle "$angle"
                 --transition-wave "$((24 + RANDOM % 30)),$((12 + RANDOM % 20))" --transition-duration 1.7) ;;
    wipe)  args=(--transition-type wipe --transition-angle "$angle" --transition-duration 1.2) ;;
    grow)  spot; args=(--transition-type grow "${where[@]}" --transition-duration 1.6) ;;
    outer) spot; args=(--transition-type outer "${where[@]}" --transition-duration 1.5) ;;
    *)     args=(--transition-type fade --transition-duration 1.1) ;;
esac

exec awww img "$file" "${args[@]}" --transition-bezier "$ease" --transition-fps "$fps"
