#!/bin/bash
# Login hand-off: start on the exact blurred image the SDDM login screen shows
# (~/.cache/login/background.jpg), then fade into the sharp wallpaper 3.5 s into the
# session. (The screen often stays black for a few seconds after logging in, while the
# monitor switches over from the login screen: any sooner and the fade would play to a
# dark screen.)

blurred=${XDG_CACHE_HOME:-$HOME/.cache}/login/background.jpg
wallpaper=$(cat "${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-theme.last" 2>/dev/null)

awww-daemon --no-cache &
until awww query >/dev/null 2>&1; do sleep 0.05; done

if [ -f "$blurred" ] && [ -f "$wallpaper" ]; then
    awww img "$blurred" --transition-type none
    # (HYPRLAND_INSTANCE_SIGNATURE is "<hash>_<when the session started, in s>_<...>")
    started=$(cut -d_ -f2 <<< "${HYPRLAND_INSTANCE_SIGNATURE:-}")
    if [[ $started =~ ^[0-9]+$ ]]; then
        now=${EPOCHREALTIME/[.,]/}
        left=$(( started * 1000 + 3500 - now / 1000 ))      # ms
        (( left > 0 )) && sleep "$(printf '%d.%03d' $(( left / 1000 )) $(( left % 1000 )))"
    fi
    awww img "$wallpaper" --transition-type fade --transition-duration 1.4 --transition-fps 60
elif [ -f "$wallpaper" ]; then
    awww img "$wallpaper" --transition-type none
fi
wait
