#!/bin/bash
# Set up calendar sync with your Mac and phone, over Tailscale. Run it once; it asks for
# what it needs. Running it again repairs and re-syncs (--new-password to change the
# password).
#
#   your Mac / phone  --CalDAV, HTTPS, tailnet only-->  tailscale serve (:8443)
#     --> Radicale (calendar server, this machine only, 127.0.0.1:5232)
#     <-- vdirsyncer (every 5 min, and on each change) -->  ~/.local/share/calendars/
#     <-- khal --> the island's calendar
#
# Needs: sudo pacman -S --needed khal vdirsyncer radicale python-bcrypt tailscale
# and this machine on your tailnet (sudo systemctl enable --now tailscaled; sudo tailscale up).
set -euo pipefail

PORT=8443
say() { printf '\033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- what's needed
missing=()
for cmd in khal vdirsyncer radicale tailscale; do
    command -v "$cmd" >/dev/null || missing+=("$cmd")
done
python3 -c 'import bcrypt' 2>/dev/null || missing+=(python-bcrypt)
[ ${#missing[@]} -eq 0 ] || die "First install: sudo pacman -S --needed ${missing[*]}"

tailscale status >/dev/null 2>&1 \
    || die "This machine isn't on your tailnet yet: sudo systemctl enable --now tailscaled && sudo tailscale up"
host=$(tailscale status --json | python3 -c 'import json, sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
[ -n "$host" ] || die "Couldn't find this machine's tailnet name (is MagicDNS on? Tailscale admin console > DNS)"

# ---------------------------------------------------------------- your account
if [ -s ~/.config/radicale/users ] && [ -s ~/.config/vdirsyncer/radicale-password ] && [ "${1:-}" != "--new-password" ]; then
    user=$(cut -d: -f1 ~/.config/radicale/users)
    pass=$(cat ~/.config/vdirsyncer/radicale-password)
    say "Using your account \"$user\" (--new-password to change the password)"
else
read -rp "Calendar username [$USER]: " user
user=${user:-$USER}
while true; do
    read -rsp "Choose a password for it: " pass; echo
    read -rsp "Again: " pass2; echo
    [ -n "$pass" ] && [ "$pass" = "$pass2" ] && break
    echo "They don't match (or it's empty); try again."
done

umask 077
mkdir -p ~/.config/radicale ~/.config/vdirsyncer ~/.local/share/radicale ~/.local/share/vdirsyncer/status
# Radicale keeps only a hash of the password; vdirsyncer needs the password itself
printf '%s:%s\n' "$user" "$(printf '%s' "$pass" | python3 -c 'import bcrypt, sys; print(bcrypt.hashpw(sys.stdin.buffer.read(), bcrypt.gensalt()).decode())')" \
    > ~/.config/radicale/users
printf '%s' "$pass" > ~/.config/vdirsyncer/radicale-password
umask 022
fi

cat > ~/.config/vdirsyncer/config <<EOF
# Written by calendar-sync-setup.sh: syncs ~/.local/share/calendars/ (what khal and the
# island read) with the calendar server on this machine. Every calendar on either side
# appears on the other; if both change the same event, the server's (your Mac's) wins.
[general]
status_path = "~/.local/share/vdirsyncer/status/"

[pair calendars]
a = "calendars_local"
b = "calendars_server"
collections = ["from a", "from b"]
metadata = ["displayname", "color"]
conflict_resolution = "b wins"

[storage calendars_local]
type = "filesystem"
path = "~/.local/share/calendars/"
fileext = ".ics"

[storage calendars_server]
type = "caldav"
url = "http://127.0.0.1:5232/"
username = "$user"
password.fetch = ["command", "cat", "$HOME/.config/vdirsyncer/radicale-password"]
EOF

# ---------------------------------------------------------------- the server
say "Starting the calendar server..."
systemctl --user daemon-reload
systemctl --user enable radicale.service >/dev/null
systemctl --user restart radicale.service
for _ in $(seq 50); do
    curl -s -o /dev/null http://127.0.0.1:5232/ && break
    sleep 0.1
done
curl -s -o /dev/null http://127.0.0.1:5232/ || die "Radicale didn't start: journalctl --user -u radicale"

say "Making it reachable from your tailnet (https://$host:$PORT)..."
serve=(tailscale serve --bg --https="$PORT" http://127.0.0.1:5232)
errors=$(mktemp)
trap 'rm -f "$errors"' EXIT
if ! "${serve[@]}" 2>"$errors"; then
    if grep -qi 'access denied\|permission\|operator' "$errors"; then
        echo "(Tailscale needs root for this once; it will ask for your password)"
        sudo tailscale set --operator="$USER"
        "${serve[@]}" || die "tailscale serve failed (see above)"
    else
        cat "$errors" >&2
        die "tailscale serve failed. If it says HTTPS or Serve isn't enabled, follow its link, then run this again."
    fi
fi

# ---------------------------------------------------------------- the firewall
# OpenSnitch holds new connections until they're allowed (and a "deny python" answer to
# one of its prompts blocks every Python program, vdirsyncer included), so vdirsyncer
# couldn't reach the server: allow connections on this machine to the server's port,
# ahead of other rules. OpenSnitch is restarted to load it (it doesn't always notice a
# new rule file; restarting also drops rules you gave a limited time, like "until
# restart").
if systemctl is-active --quiet opensnitchd 2>/dev/null; then
    rule=/etc/opensnitchd/rules/allow-calendar-server.json
    if ! sudo grep -qs 'calendar-sync rule 2' "$rule"; then
        say "Allowing the calendar server through OpenSnitch (it will ask for your password)..."
        python3 - "$(date -Iseconds)" <<'RULE' | sudo tee "$rule" >/dev/null
import json, sys
checks = [
    {"type": "simple", "operand": "dest.ip", "sensitive": False, "data": "127.0.0.1", "list": None},
    {"type": "simple", "operand": "dest.port", "sensitive": False, "data": "5232", "list": None},
]
print(json.dumps({
    "created": sys.argv[1],
    "updated": sys.argv[1],
    "name": "allow-calendar-server",
    "description": "calendar-sync rule 2: programs on this machine reaching the calendar server (Radicale, 127.0.0.1:5232); see calendar-sync-setup.sh",
    "enabled": True,
    "precedence": True,
    "nolog": False,
    "action": "allow",
    "duration": "always",
    # (the list both ways: as OpenSnitch's own interface saves it)
    "operator": {"type": "list", "operand": "list", "sensitive": False, "data": json.dumps(checks), "list": checks},
}, indent=2))
RULE
        sudo chmod 600 "$rule"
        sudo systemctl restart opensnitchd
        sleep 3
    fi
fi

# ---------------------------------------------------------------- syncing
# (each step gives up after a minute rather than hanging)
step() {
    timeout 60 "$@" || die "\"$*\" didn't finish. If a firewall is asking about python or vdirsyncer, allow it (127.0.0.1, port 5232) and run this again."
}
say "First sync..."
"$(dirname "$0")/calendar-events.py" calendars >/dev/null      # (at least one calendar: "Personal")
{ yes || true; } | step vdirsyncer -v WARNING discover calendars

# Calendars made here (like "Personal") reach the server without a name, and the server
# then offers its path ("you/personal") as one, which would replace theirs here: give
# them their names on the server first.
quoted=${pass//\\/\\\\}; quoted=${quoted//\"/\\\"}       # (for curl's config syntax)
dav() { curl -s -K - -H 'Content-Type: application/xml' "$@" <<<"user = \"$user:$quoted\""; }
for d in ~/.local/share/calendars/*/; do
    col=$(basename "$d")
    name=$(cat "$d/displayname" 2>/dev/null || true)
    [ -n "$name" ] && [ "$name" != "$user/$col" ] || continue
    current=$(dav -X PROPFIND -H 'Depth: 0' --data '<?xml version="1.0"?><propfind xmlns="DAV:"><prop><displayname/></prop></propfind>' \
        "http://127.0.0.1:5232/$user/$col/" | sed -n 's:.*<displayname>\([^<]*\)</displayname>.*:\1:p')
    if [ "$current" = "$user/$col" ]; then
        xml=$(printf '%s' "$name" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        dav -o /dev/null -X PROPPATCH --data "<?xml version=\"1.0\" encoding=\"utf-8\"?><D:propertyupdate xmlns:D=\"DAV:\"><D:set><D:prop><D:displayname>$xml</D:displayname></D:prop></D:set></D:propertyupdate>" \
            "http://127.0.0.1:5232/$user/$col/"
    fi
done

step vdirsyncer -v WARNING metasync
step vdirsyncer -v WARNING sync
systemctl --user enable --now calendar-sync.timer >/dev/null
echo "Calendars here now:"
khal printcalendars | sed 's/^/  /'

cat <<EOF

$(say "Done. This machine's calendars are on the server; now add it on your Mac and phone.")

Server address:  https://$host:$PORT/
Username:        $user
Password:        the one you just chose

Mac (on Tailscale):
  1. Calendar > Settings > Accounts > + > Other CalDAV Account...
     Account Type: Manual; then the username, password and server address above.
  2. To move your "On My Mac" calendars over: select one, File > Export > Export...,
     then File > Import..., pick that file and choose a calendar in the new account
     ("Personal", or one you make with File > New Calendar). When everything's there,
     you can delete the "On My Mac" one.
  3. In the account's settings, set "Refresh Calendars" to every minute or 5 minutes.

iPhone (with Tailscale on):
  Settings > Apps > Calendar > Calendar Accounts > Add Account > Other >
  Add CalDAV Account; the same server, username and password.
EOF
