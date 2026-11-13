#!/bin/bash
# Take a screenshot (the launcher's screenshot menu, Print, and services/Screenshot.qml):
#   screenshot.sh area|window|screen [DELAY] [EDIT]
#   area     drag a rectangle (Esc cancels)
#   window   click a window
#   screen   the screen you're on
# After DELAY seconds (counted down in the island), it's copied to the clipboard and saved
# to ~/Pictures/Screenshots, and the island says so, with buttons to open it or draw on it
# (satty). EDIT=1 opens it to draw on straight away.
# QR codes in it (read with zbar, when it's installed: qr-codes.py) are shown in the
# notification: one link opens on a click, and its text can be copied; several are listed,
# and a click (or "All N codes") opens them all in the launcher's QR Codes menu, which
# keeps the ones found lately.
# (Videos: record.sh. Picking, in the shell's colours: pick.sh.)
here=$(dirname "$(readlink -f "$0")")
. "$here/pick.sh"

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

# QR codes in it, in reading order (about 150 ms for a whole screen; light codes on dark
# backgrounds too, as dark-themed pages and videos show them)
mapfile -d '' codes < <(python3 "$here/qr-codes.py" scan "$file" 2>/dev/null)
count=${#codes[@]}
qr=${codes[0]-}
link=""
[[ $qr =~ ^https?://[^[:space:]]+$ ]] && link=$qr

# (for the notification's text, which may have markup: <a href=...>)
escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' <<< "$1"
}

# a line for each code (the notification shows three): a link to click, or its text,
# shortened to fit on one line; past three, two and "and N more"
lines() {
    local code text max=3 out=""
    (( count > 3 )) && max=2
    for code in "${codes[@]:0:max}"; do
        text=${code//$'\n'/ }
        [[ $code =~ ^https?://[^[:space:]]+$ ]] && text=${code#*://}
        (( ${#text} > 40 )) && text="${text:0:39}…"
        text=$(escape "$text")
        [[ $code =~ ^https?://[^[:space:]]+$ ]] && text="<a href=\"$(escape "$code")\">$text</a>"
        out+=${out:+<br>}$text
    done
    (( count > max )) && out+="<br>and $(( count - max )) more"
    printf '%s' "$out"
}

# all of them, to open or copy one by one (launcher/QrMode.qml)
all_codes() {
    qs ipc call launcher open qr >/dev/null 2>&1
}

# say so, with its picture; clicking it opens the picture (or the QR code's link, or all
# the codes), the buttons copy the QR code, list them all, open the picture or draw on it
name=$(basename "$file")
if (( count > 1 )); then
    action=$(notify-send -a Screenshot -i "$file" -h "string:image-path:$file" \
        -A default="All codes" -A all="All $count codes" -A picture="Open screenshot" -A edit="Draw on it" \
        -- "Screenshot copied, with $count QR codes" "$(lines)")
elif [ -n "$link" ]; then
    shown=$(escape "$link")
    action=$(notify-send -a Screenshot -i "$file" -h "string:image-path:$file" \
        -A default="Open link" -A copy="Copy link" -A picture="Open screenshot" -A edit="Draw on it" \
        -- "Screenshot copied, with a QR code" "<a href=\"$shown\">$shown</a>")
elif [ -n "$qr" ]; then
    text=${qr//$'\n'/ }
    action=$(notify-send -a Screenshot -i "$file" -h "string:image-path:$file" \
        -A default=Open -A copy="Copy text" -A edit="Draw on it" \
        -- "Screenshot copied, with a QR code" "$(escape "${text:0:240}")")
else
    action=$(notify-send -a Screenshot -i "$file" -h "string:image-path:$file" \
        -A default=Open -A edit="Draw on it" \
        -- "Screenshot copied" "Saved as $name in Pictures/Screenshots")
fi
case "$action" in
    default) if (( count > 1 )); then all_codes; else xdg-open "${link:-$file}"; fi ;;
    all) all_codes ;;
    picture) xdg-open "$file" ;;
    copy) wl-copy -- "$qr" ;;
    edit) draw ;;
esac
