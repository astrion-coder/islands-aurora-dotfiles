#!/bin/bash
# Take a screenshot (the launcher's screenshot menu, Print, and services/Screenshot.qml):
#   screenshot.sh area|window|screen [DELAY] [EDIT]
#   area     drag a rectangle (Esc cancels)
#   window   click a window
#   screen   the screen you're on
# After DELAY seconds (counted down in the island), it's copied to the clipboard and saved
# to ~/Pictures/Screenshots, and the island says so, with buttons to open it or draw on it
# (satty). EDIT=1 opens it to draw on straight away.
# (Videos: record.sh. Picking, in the shell's colours: pick.sh.)
. "$(dirname "$(readlink -f "$0")")/pick.sh"

mode=${1:-area}
delay=${2:-0}
edit=${3:-0}

pictures=$(xdg-user-dir PICTURES 2>/dev/null)
dir="${pictures:-$HOME/Pictures}/Screenshots"
mkdir -p "$dir"
file="$dir/Screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"

pick "$mode" || exit 0
countdown "$delay" Screenshot

grim "${where[@]}" "$file" || { notify-send -a Screenshot "Screenshot failed" "grim couldn't take it"; exit 1; }

wl-copy -t image/png < "$file"

draw() {
    command -v satty >/dev/null || { notify-send -a Screenshot "Can't draw on it" "satty isn't installed: sudo pacman -S satty"; return; }
    satty --filename "$file" --output-filename "$file" --copy-command wl-copy --early-exit
}

if [ "$edit" = 1 ]; then
    draw
    exit 0
fi

# say so, with its picture; the buttons open it or draw on it
name=$(basename "$file")
action=$(notify-send -a Screenshot -i "$file" -h "string:image-path:$file" \
    -A default=Open -A edit="Draw on it" \
    "Screenshot copied" "Saved as $name in Pictures/Screenshots")
case "$action" in
    default) xdg-open "$file" ;;
    edit) draw ;;
esac
