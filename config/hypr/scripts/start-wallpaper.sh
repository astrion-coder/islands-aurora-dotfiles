#!/bin/bash
# Login hand-off: start on the exact blurred image the SDDM login screen shows
# (~/.cache/login/background.jpg), then fade into the sharp wallpaper.

blurred=${XDG_CACHE_HOME:-$HOME/.cache}/login/background.jpg
wallpaper=$(cat "${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-theme.last" 2>/dev/null)

awww-daemon --no-cache &
until awww query >/dev/null 2>&1; do sleep 0.05; done

if [ -f "$blurred" ] && [ -f "$wallpaper" ]; then
    awww img "$blurred" --transition-type none
    sleep 0.6
    awww img "$wallpaper" --transition-type fade --transition-duration 1.4 --transition-fps 60
elif [ -f "$wallpaper" ]; then
    awww img "$wallpaper" --transition-type none
fi
wait
