#!/bin/bash
# Set up the Shared Box: text, links and files shared between this PC and your phone and
# Mac, over Tailscale (only your own devices, signed in as you, can reach it). Run it
# once; running it again repairs it.
#
#   your phone / Mac --HTTPS, tailnet only--> tailscale serve (:443)
#     --> shared-box.py (its socket, this PC only) <-- the launcher's Shared Box (Super+I)
#   (files go the same way: uploaded from the page, they land in ~/Downloads)
#
# Needs this machine on your tailnet (sudo systemctl enable --now tailscaled; sudo tailscale up).
set -euo pipefail

say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

command -v tailscale >/dev/null || die "First install Tailscale: sudo pacman -S tailscale"
tailscale status >/dev/null 2>&1 \
    || die "This machine isn't on your tailnet yet: sudo systemctl enable --now tailscaled && sudo tailscale up"
host=$(tailscale status --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
[ -n "$host" ] || die "Couldn't find this machine's tailnet name (is MagicDNS on? Tailscale admin console > DNS)"
socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/shared-box.sock"

# ---------------------------------------------------------------- this PC's side
say "Starting the Shared Box..."
# (the box used to take files in over Taildrop: that receiver is no longer needed)
if systemctl --user cat taildrop-receive.service >/dev/null 2>&1; then
    systemctl --user disable --now taildrop-receive.service >/dev/null 2>&1 || true
fi
systemctl --user daemon-reload
systemctl --user enable shared-box.service >/dev/null
systemctl --user restart shared-box.service
for _ in $(seq 50); do
    [ -S "$socket" ] && break
    sleep 0.1
done
[ -S "$socket" ] || die "The Shared Box didn't start: journalctl --user -u shared-box"

# ---------------------------------------------------------------- your tailnet
# (Tailscale only lets root point it at a socket: it asks for your password, once; the
# setting stays, through restarts)
say "Making it reachable from your devices (https://$host/)..."
serve=(tailscale serve --bg --https=443 "unix:$socket")
errors=$(mktemp)
trap 'rm -f "$errors"' EXIT
if ! "${serve[@]}" >/dev/null 2>"$errors"; then
    if grep -qi 'root\|sudo\|access denied\|permission\|operator\|unauthorized' "$errors"; then
        echo "(Tailscale needs root to pass requests to the box's socket; it will ask for your password)"
        sudo "${serve[@]}" >/dev/null || die "tailscale serve failed (see above)"
    else
        cat "$errors" >&2
        die "tailscale serve failed. If it says HTTPS or Serve isn't enabled, follow its link, then run this again."
    fi
fi

# ---------------------------------------------------------------- done
url="https://$host/"
say "Done. The Shared Box is at $url"
if command -v qrencode >/dev/null; then
    echo "Scan this with your phone's camera:"
    qrencode -t ansiutf8 -m 2 "$url"
fi
cat <<INFO

On your phone (with Tailscale on):
  Android: open $url in Chrome, then menu (⋮) > Add to home screen > Install. "Shared Box"
           is then in the share menu of any app: share a link, text or files to it.
  iPhone:  open it in Safari, then Share > Add to Home Screen.
On the Mac: open it in a browser (in Safari: File > Add to Dock, for an app of its own).

On this PC: Super+I (or "Shared Box" in Super+R). Type and press Enter to send; what comes
in from your other devices shows as a notification.

Files: on your phone or Mac, press Files on the page (or, on a computer, drop or paste
them there; on Android, share them to Shared Box). They land in ~/Downloads here, and
your other devices can download them from the box. From this PC: find a file with Super+F
and press Ctrl+Enter, then download it from the box on your phone or Mac.
INFO
