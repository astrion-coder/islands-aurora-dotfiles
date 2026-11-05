#!/bin/bash
# Record the screen (the screenshot and recording menu, Super+Shift+P or Print, through
# services/Screenshot.qml):
#   record.sh area|window|screen [DELAY] [SOUND]    start one (SOUND: none, system, mic)
#   record.sh stop                                  stop it
# Starting one while one is going stops it instead. While it records, the island shows a
# red dot and the time (click it to stop). Then it's saved to ~/Videos/Recordings and
# copied as a file (paste it into a chat or a folder), and the island says so, with
# buttons to open it or show it in its folder.
# The graphics card encodes it when it can (VAAPI: intel-media-driver on Intel), else
# the processor (x264).
. "$(dirname "$(readlink -f "$0")")/pick.sh"

runtime=${XDG_RUNTIME_DIR:-/tmp}
state="$runtime/shell-recording"        # "PID START" while it records
stopped="$state.stopped"                # you stopped it (not a recorder giving up)
log="$runtime/shell-recording.log"      # wf-recorder's, for when it fails

# the recorder that's going, if one is
recorder() {
    local pid start
    read -r pid start 2>/dev/null < "$state" || return 1
    [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = wf-recorder ] && echo "$pid"
}

# stop: Ctrl+C, which has wf-recorder finish the file (the run that started it says so)
if pid=$(recorder); then
    : > "$stopped"
    kill -INT "$pid"
    exit 0
fi
[ "$1" = stop ] && exit 0

command -v wf-recorder >/dev/null || {
    notify-send -a Screenshot "Can't record the screen" "wf-recorder isn't installed: sudo pacman -S wf-recorder"
    exit 1
}

mode=${1:-area}
delay=${2:-0}
sound=${3:-none}

videos=$(xdg-user-dir VIDEOS 2>/dev/null)
dir="${videos:-$HOME/Videos}/Recordings"
mkdir -p "$dir"
name="Recording_$(date +%Y-%m-%d_%H-%M-%S).mp4"
file="$dir/$name"

case "$sound" in
    system) audio=(--audio="$(pactl get-default-sink).monitor") ;;   # what you hear
    mic) audio=(--audio) ;;                                           # the default microphone
    *) audio=() ;;
esac

# the ways to encode it, best first: the graphics card if it works, then the processor
encoders() {
    [ -e /dev/dri/renderD128 ] && ffmpeg -hide_banner -loglevel error \
        -init_hw_device vaapi=va:/dev/dri/renderD128 -filter_hw_device va \
        -f lavfi -i nullsrc=s=256x256:d=0.1 -vf format=nv12,hwupload -c:v h264_vaapi -f null - \
        >/dev/null 2>&1 && echo gpu
    echo cpu
}
ways=$(encoders)

pick "$mode" || exit 0
countdown "$delay" Recording

rm -f "$stopped"
trap 'rm -f "$state" "$stopped"' EXIT
told=0
failed=1
for way in $ways; do
    case "$way" in
        gpu) codec=(-c h264_vaapi) ;;      # (wf-recorder sets up the card itself)
        *) codec=(-c libx264 -x yuv420p -p preset=veryfast -p crf=23) ;;
    esac
    began=${EPOCHREALTIME/./}
    wf-recorder -y "${where[@]}" "${audio[@]}" "${codec[@]}" -f "$file" < /dev/null > "$log" 2>&1 &
    pid=$!
    echo "$pid ${began:0:10}" > "$state"
    if [ "$told" = 0 ]; then
        qs ipc call screenshot recordingStarted >/dev/null 2>&1
        told=1
    fi
    wait "$pid"
    status=$?
    # (one that gives up within two seconds, without you stopping it, couldn't record
    # that way: the next way)
    if [ "$status" -ne 0 ] && [ ! -e "$stopped" ] && [ $((${EPOCHREALTIME/./} - began)) -lt 2000000 ]; then
        continue
    fi
    failed=0
    break
done
rm -f "$state" "$stopped"
qs ipc call screenshot recordingStopped >/dev/null 2>&1

if [ "$failed" = 1 ] || [ ! -s "$file" ]; then
    rm -f "$file"
    why=$(tail -n 2 "$log")
    notify-send -a Screenshot "Recording failed" "${why:-wf-recorder stopped without a video}"
    exit 1
fi

# copied as a file: paste it into a chat or a folder
uri=$(python3 -c 'import pathlib, sys; print(pathlib.Path(sys.argv[1]).as_uri())' "$file")
printf '%s\r\n' "$uri" | wl-copy -t text/uri-list

# how long, and its first frame for the notification
seconds=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null)
seconds=${seconds%.*}
length=$(printf '%d:%02d' $((${seconds:-0} / 60)) $((${seconds:-0} % 60)))
thumb="$runtime/${name%.mp4}.png"
icon=()
ffmpeg -hide_banner -loglevel error -y -i "$file" -frames:v 1 -vf "scale='min(640,iw)':-2" "$thumb" 2>/dev/null &&
    icon=(-i "$thumb" -h "string:image-path:$thumb")

action=$(notify-send -a Screenshot "${icon[@]}" -A default=Open -A folder="Show in folder" \
    "Recording saved" "$length long, in Videos/Recordings. Copied: paste it into a chat or a folder")
case "$action" in
    default) xdg-open "$file" ;;
    folder)
        busctl --user call org.freedesktop.FileManager1 /org/freedesktop/FileManager1 \
            org.freedesktop.FileManager1 ShowItems ass 1 "$uri" "" >/dev/null 2>&1 || xdg-open "$dir"
        ;;
esac
