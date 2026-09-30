#!/bin/bash
# The whole sound pill: icon class (speaker / bluetooth, muted), volume, and one
# tooltip for all of it (device name, + battery for Bluetooth). Runs continuously,
# checking twice a second and printing only when something changed.

last=""
while true; do
    sink=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null)
    prop() { sed -n "s/.*[ *] $1 = \"\(.*\)\"/\1/p" <<<"$sink" | head -n1; }

    vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
    pct=$(awk '{printf "%d", $2 * 100 + 0.5}' <<<"$vol")
    name=$(prop node.description)

    if [ "$(prop device.api)" = "bluez5" ]; then
        classes='"bluetooth"'
        mac=$(prop api.bluez5.address)
        bat=$(busctl --system get-property org.bluez "/org/bluez/hci0/dev_${mac//:/_}" \
              org.bluez.Battery1 Percentage 2>/dev/null | awk '{print $2}')
        tooltip="$name${bat:+ · battery $bat%}"
    else
        classes='"speaker"'
        tooltip="$name"
    fi
    grep -q MUTED <<<"$vol" && classes="$classes, \"muted\""

    out=$(printf '{"text": "%s%%", "class": [%s], "tooltip": "%s"}' "${pct:-0}" "$classes" "$tooltip")
    [ "$out" != "$last" ] && { echo "$out"; last=$out; }
    sleep 0.5
done
