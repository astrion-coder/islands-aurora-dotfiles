#!/bin/bash
# Files sent to this PC over Taildrop (from your phone's or Mac's share menu: Tailscale ->
# this PC), taken in as they arrive (taildrop-receive.service): each goes to your
# Downloads folder (a name that's there already gets a number: "photo (1).jpg"), into the
# Shared Box, and the island says so (shared-box.py; without it running, a plain
# notification). Set up by shared-box-setup.sh.
set -u

here=$(dirname "$(readlink -f "$0")")
inbox="${XDG_DATA_HOME:-$HOME/.local/share}/shared-box/incoming"
downloads=$(xdg-user-dir DOWNLOAD 2>/dev/null)
[ -n "$downloads" ] && [ "$downloads" != "$HOME" ] || downloads="$HOME/Downloads"
mkdir -p "$inbox" "$downloads"

# "name.ext", or "name (1).ext", ... if it's taken
free_name() {
    local name=$1 base ext n=1
    [ -e "$downloads/$name" ] || { printf '%s' "$downloads/$name"; return; }
    base=${name%.*} ext=${name##*.}
    [ "$base" = "$name" ] && ext="" || ext=".$ext"
    while [ -e "$downloads/$base ($n)$ext" ]; do n=$((n + 1)); done
    printf '%s' "$downloads/$base ($n)$ext"
}

while true; do
    # (waits for files; into a folder of our own first, so it's clear which ones just came)
    if ! tailscale file get --wait --conflict=rename "$inbox" >/dev/null 2>&1; then
        sleep 15            # (Tailscale isn't up, or not yet)
        continue
    fi
    for file in "$inbox"/* "$inbox"/.[!.]*; do
        [ -f "$file" ] || continue
        dest=$(free_name "$(basename "$file")")
        mv -n -- "$file" "$dest" || continue
        "$here/shared-box.py" received "$dest" 2>/dev/null \
            || notify-send -a "Shared Box" -- "Received $(basename "$dest")" "Over Taildrop, in Downloads"
    done
done
