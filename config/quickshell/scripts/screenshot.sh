#!/bin/bash
# Take a screenshot (the launcher's screenshot menu, Print, and services/Screenshot.qml):
#   screenshot.sh area|window|screen [DELAY] [EDIT]
#   area     drag a rectangle (Esc cancels)
#   window   click a window
#   screen   the screen you're on
# After DELAY seconds (counted down in the island), it's copied to the clipboard and saved
# to ~/Pictures/Screenshots, and the island says so, with buttons to open it or draw on it
# (satty). EDIT=1 opens it to draw on straight away.
# QR codes and links in it (read with zbar and tesseract, when they're installed:
# qr-codes.py) are shown in the notification: one link opens on a click, a QR code's text
# can be copied; several are listed, and a click (or "Show all") opens them all in the
# launcher's Links & QR Codes menu, which keeps the ones found lately.
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

# QR codes and links written in it, in reading order ("qr" or "text", a tab, the code;
# about 0.7 s for a whole screen, most of it reading the text)
mapfile -d '' found < <(python3 "$here/qr-codes.py" scan "$file" 2>/dev/null)
codes=()
qrs=0 links=0
for item in "${found[@]}"; do
    codes+=("${item#*$'\t'}")
    if [ "${item%%$'\t'*}" = qr ]; then qrs=$((qrs + 1)); else links=$((links + 1)); fi
done
count=${#codes[@]}
qr=${codes[0]-}
link=""
[[ $qr =~ ^https?://[^[:space:]]+$ ]] && link=$qr

# "with a QR code", "with 2 links", "with a QR code and 3 links"
found_what() {
    local parts=()
    (( qrs == 1 )) && parts+=("a QR code")
    (( qrs > 1 )) && parts+=("$qrs QR codes")
    (( links == 1 )) && parts+=("a link")
    (( links > 1 )) && parts+=("$links links")
    printf 'with %s' "${parts[0]}${parts[1]:+ and ${parts[1]}}"
}

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

# say so, with its picture; clicking it opens the picture (or the link, or all of what
# was found), the buttons copy the link or code, list them all, open the picture or draw
# on it
name=$(basename "$file")
if (( count > 1 )); then
    action=$(notify-send -a Screenshot -i "$file" -h "string:image-path:$file" \
        -A default="Show all" -A all="Show all $count" -A picture="Open screenshot" -A edit="Draw on it" \
        -- "Screenshot copied, $(found_what)" "$(lines)")
elif [ -n "$link" ]; then
    shown=$(escape "$link")
    action=$(notify-send -a Screenshot -i "$file" -h "string:image-path:$file" \
        -A default="Open link" -A copy="Copy link" -A picture="Open screenshot" -A edit="Draw on it" \
        -- "Screenshot copied, $(found_what)" "<a href=\"$shown\">$shown</a>")
elif [ -n "$qr" ]; then
    text=${qr//$'\n'/ }
    action=$(notify-send -a Screenshot -i "$file" -h "string:image-path:$file" \
        -A default=Open -A copy="Copy text" -A edit="Draw on it" \
        -- "Screenshot copied, $(found_what)" "$(escape "${text:0:240}")")
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
