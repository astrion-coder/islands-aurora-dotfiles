#!/bin/bash
# Re-theme the system (matugen) whenever the awww wallpaper changes,
# so a plain `awww img <file>` is all that's needed. Started from hyprland.lua.

# One instance per session, and exit once this Hyprland session is gone
# (otherwise old copies keep running after a logout).
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/wallpaper-theme.lock"
flock -n 9 || exit 0
session="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}"

state=${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-theme.last
login_bg=${XDG_CACHE_HOME:-$HOME/.cache}/login/background.jpg

current() { awww query 2>/dev/null | sed -n 's/.*currently displaying: image: //p' | head -n1; }

while [ -d "$session" ]; do
    img=$(current)
    # (the blurred login image shown at startup is not a new wallpaper)
    if [ -n "$img" ] && [ -f "$img" ] && [ "$img" != "$(cat "$state" 2>/dev/null)" ] \
       && [[ "$img" != "$login_bg" ]]; then
        matugen image "$img" --mode dark --source-color-index 0 >/dev/null 2>&1 \
            && printf '%s' "$img" > "$state" \
            && "$HOME/.config/sddm-theme/sync.sh" "$img" >/dev/null 2>&1 \
            && "$HOME/.config/hypr/scripts/kvantum-theme.py" >/dev/null 2>&1   # login/lock screens, Okular's style
    fi
    sleep 1
done
