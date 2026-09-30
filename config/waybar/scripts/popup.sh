#!/bin/bash
# Toggle an app as a dropdown under the bar: close it if its window is open,
# otherwise launch it. Placement (float/size/position) comes from the
# "bar-popups" window rule in hyprland.lua.
# Usage: popup.sh <window-class> <command...>

class=$1; shift
pids=$(hyprctl clients -j | python3 -c "
import json, sys
print(' '.join(str(c['pid']) for c in json.load(sys.stdin) if c['class'] == sys.argv[1]))" "$class")

# Also catch an instance still starting up (no window yet), so fast clicks
# don't stack copies
pids="$pids $(pgrep -x "$(basename "$1")")"

if [ -n "${pids// /}" ]; then
    kill $pids
else
    command -v "$1" >/dev/null || { notify-send "Not installed" "$1" 2>/dev/null; exit 1; }
    setsid "$@" >/dev/null 2>&1 &
fi
