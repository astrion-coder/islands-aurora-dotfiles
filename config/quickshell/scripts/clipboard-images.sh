#!/bin/bash
# Images in the clipboard history, for the launcher's previews: decodes each one (once)
# to $XDG_RUNTIME_DIR/quickshell-clipboard/<id>.<ext>. That folder is private to you and
# is emptied when you log out.
dir="${XDG_RUNTIME_DIR:-/tmp}/quickshell-clipboard"
mkdir -p "$dir" && chmod 700 "$dir"

# cliphist lists them as "<id>\t[[ binary data 120 KiB png 1920x1080 ]]"
re=$'^([0-9]+)\t\\[\\[ binary data .* (png|jpeg|jpg|gif|webp|bmp|svg) [0-9]+x[0-9]+ \\]\\]$'
keep=()
while IFS= read -r line; do
    [[ $line =~ $re ]] || continue
    file="$dir/${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    keep+=("$file")
    [ -s "$file" ] || printf '%s' "$line" | cliphist decode > "$file"
done < <(cliphist list)

# images no longer in the history (removed, or dropped as the history grew) go too
for file in "$dir"/*.*; do
    [ -f "$file" ] || continue
    [[ " ${keep[*]} " == *" $file "* ]] || rm -f "$file"
done
