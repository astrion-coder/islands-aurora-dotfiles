# Islands Aurora

A complete Hyprland desktop for Arch Linux, themed from your wallpaper. Change the
wallpaper and everything follows: bar, window borders, terminal, apps, launcher,
notifications, login and lock screens.

- **Frosted glass everywhere.** Backgrounds blur, text never does. Apps draw their own
  translucent backgrounds (GTK palette, a Kvantum style for Qt, kitty's opacity), and
  Hyprland blurs what shows through.
- **Scrolling layout.** Windows sit side by side in columns on a strip that scrolls
  horizontally, instead of being split into ever-smaller tiles. `Super+Shift+H/J/K/L`
  swaps a window with its neighbour and both keep their sizes.
- **Screen frame with a tucked-away bar.** A dark frame of even width runs around the
  screen, and the desktop is a rounded box inside it. The whole bar lives in the dynamic
  island, a tab of the frame in the middle showing the date and time. Point at the top
  edge and it stretches out sideways: cpu and memory on its left, tray, sound and power
  on its right. They tuck back in once the pointer leaves. Windows start just below the
  island, so it never covers them (`quickshell/bar/FrameEdge.qml` reserves the space).
  Right-click the sound pill for a volume slider, mute, Bluetooth on/off and your
  Bluetooth devices.
- **Dynamic island.** The middle of the bar shows the date and time, and grows into what's
  happening: notifications, the song playing (with its cover and a live audio
  visualizer), volume changes, a Bluetooth device connecting, battery warnings. Hover it
  for playback controls, the calendar and your unread notifications, in a panel that
  grows out of the frame.
- **Raycast-style launcher.** One menu for apps and commands: clipboard history, emoji,
  file search, a calculator, window switcher, system actions. Type maths, unit and
  currency conversions, time zones or AoE deadlines and press Enter for an answer card.
- **Themed login and lock.** An SDDM theme on the blurred wallpaper and a lock screen
  that looks the same.

The bar, notifications, launcher and lock screen are one [Quickshell](https://quickshell.org)
shell, so they share one look and follow the wallpaper together.
- **zsh with Oh My Zsh and fzf.** zsh becomes your login shell, with autosuggestions,
  syntax highlighting and fzf for files, history and directories.

Everything installs from the official Arch repositories. No AUR. The one exception is
Oh My Zsh, which isn't packaged and is cloned from GitHub.

## Requirements

- Arch Linux: a fresh, terminal-only install is fine
- A normal user account with `sudo` (in the `wheel` group)
- Internet access for `pacman`
- A GPU driver Hyprland can use. `mesa` is installed; NVIDIA users also need `nvidia-open`
  (see the Arch wiki)

## Install

```sh
sudo pacman -S --needed git
git clone <this-repo-url> islands-aurora
cd islands-aurora
./install.sh
sudo reboot
```

Log in on the SDDM screen with your password, and you're in Hyprland.

**Calendar sync (optional).** Only if you want the island's calendar to sync with a Mac
or an iPhone. After that first login, in this order:

1. In the [Tailscale admin console](https://login.tailscale.com/admin/dns), on the *DNS*
   page, turn on MagicDNS and HTTPS certificates (once per tailnet).
2. Put this machine on your tailnet, logging in with the same account as your Mac:
   ```sh
   sudo systemctl enable --now tailscaled
   sudo tailscale up
   ```
3. Set up the calendar server and the first sync:
   ```sh
   ~/.config/quickshell/scripts/calendar-sync-setup.sh
   ```
4. Add the account on your Mac and phone, as in
   [Syncing with your Mac and phone](#syncing-with-your-mac-and-phone).

Do this on **one** machine only: that machine becomes the calendar server. And if you're
reinstalling the machine that already is the server, read
[Reinstalling the server](#reinstalling-the-server) first, or your Mac's calendars can be
emptied.

Options:

| Option | Effect |
|---|---|
| `--with-opensnitch` | Also install the OpenSnitch application firewall (themed shield in the tray) |
| `--no-packages` | Skip `pacman`: only copy configs and generate the theme |
| `--no-sddm` | Don't install or enable the SDDM login screen |
| `--no-zsh` | Keep your current shell and `~/.zshrc` (no Oh My Zsh / fzf setup) |

### What `install.sh` does

1. **Installs packages:** installs everything in [`packages.txt`](packages.txt) with `pacman -Syu --needed`.
2. **Copies configs:** copies [`config/`](config) into `~/.config`. Any config it replaces is backed
   up first to `~/.config-backup-<date>/`. It also creates your first calendar, *Personal*
   (existing calendars are left alone).
3. **Sets up the shell:** clones [Oh My Zsh](https://ohmyz.sh) into `~/.oh-my-zsh` (if it isn't
   there yet), installs [`home/.zshrc`](home/.zshrc) as `~/.zshrc` (backing up the old one) and
   makes zsh your login shell.
4. **Generates the theme:** uses the first image in `~/Pictures/Wallpapers`, or generates a soft
   gradient if there isn't one. [matugen](https://github.com/InioX/matugen) turns that image into
   a palette, which fills in every themed file.
5. **Applies app settings:** sets the dark GTK/KDE preferences, makes zathura the PDF viewer, and
   sets up Okular's highlighters.
6. **Enables services:** NetworkManager, Bluetooth, the polkit agent, a daily exchange-rate update for the
   calculator, and the SDDM login screen. Calendar sync is installed but stays off (no
   server, no Tailscale) until you set it up yourself, as above.

## Keybindings

`Super` is the Windows key.

| Keys | Action |
|---|---|
| `Super+Q` | Terminal (kitty) |
| `Super+E` | File manager (Dolphin) |
| `Super+B` | Firefox |
| `Super+C` | Close window |
| `Super+Space` / `Super+R` | Launcher |
| `Super+Shift+V` | Clipboard history |
| `Super+.` | Emoji picker |
| `Super+F` | File search |
| `Super+X` | System menu (lock, log out, suspend, reboot, shut down) |
| `Super+Shift+P` / `Print` | Screenshot and recording menu, out of the island (while recording: shows it, `Enter` stops it) |
| `Shift+Print` / `Alt+Print` / `Ctrl+Print` | Screenshot of an area / a window / the screen, straight away |
| `Super+W` | Wallpaper picker, out of the island |
| `Super+Escape` | Lock screen |
| `Super+M` | Log out |
| `Super+H/J/K/L` or arrows | Move focus |
| `Super+Shift+H/J/K/L` | Move window |
| `Super+1…0` | Switch workspace |
| `Super+Shift+1…0` | Move window to workspace |
| `Super+V` | Toggle floating |
| `Super+S` | Show / hide the scratchpad (a short line under the island while it's showing) |
| `Super+Shift+S` | Send the window to the scratchpad (`Super+Shift+1…0` sends it back to a desktop) |
| `Super+D` | Restart the shell (bar, notifications, launcher, lock screen) |

## The shell

zsh with Oh My Zsh (`avit` prompt, `git` and `vi-mode` plugins), plus
[zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) and
[zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) from the Arch
repositories. fzf uses `fd`, so it includes hidden files and skips `.git`:

| Keys | Action |
|---|---|
| `Ctrl+R` | Search shell history |
| `Ctrl+T` | Insert files or folders into the command line |
| `Alt+C` | `cd` into a folder |
| `**` then `Tab` | fzf completion, e.g. `nvim **<Tab>`, `cd **<Tab>`, `kill **<Tab>` |
| `→` / `End` | Accept the grey autosuggestion |
| `Esc` | Vi normal mode (`hjkl`, `w`, `b`, `dd`, `ciw`, ...; `i` / `a` back to insert). `y` / `p` use the system clipboard |
| `vv` (normal mode) | Edit the current command in nvim |
| `pacman -Ss <query>` | Browse packages in fzf with details alongside; `Tab` marks several, `Enter` installs them |

Put your own aliases and settings in `~/.zshrc.local`. `~/.zshrc` loads it, and re-running
`install.sh` never touches it, but it does replace `~/.zshrc`.

## The launcher

Open it with `Super+Space` (or `Super+R`) and start typing. It grows out of the frame at
the top of the screen: the dynamic island comes out with the date and time, and the
launcher hangs below it, then it all closes back into the frame.

- **Apps and commands:** type a name. Commands like *Clipboard History*, *Search Emoji*,
  *Search Files*, *Calculator*, *Switch Windows* and *Shut Down* also match partial words
  ("paste", "sleep", "math"). Apps you open often come first. In a sub-menu, `Esc` goes
  back to the main menu; any launcher key pressed again closes it.
- **Moving around:** `↑`/`↓` (or `Tab`, `Ctrl+J`/`Ctrl+K`), `Enter` to choose, or click.
- **Pasting:** whatever the launcher hands back (a clipboard entry, a result, an answer)
  is pasted where your cursor was, as a real paste: `Ctrl+Shift+V` in terminals, `Ctrl+V`
  elsewhere, so pictures paste too and several lines don't run one by one in a terminal.
  It also lands in the clipboard history.
- **Sub-menus:**
  - *Clipboard:* `Enter` pastes an entry into the window you were in (and copies it
    back), `Alt+1` only copies it, `Shift+Delete` removes it. A pane beside
    the list previews the selected entry: pictures full size (with their dimensions),
    links as a card with the page's title, description and image, colours as a swatch,
    and text in full with a character and word count. Fetching a link's preview opens the
    page like a browser would, so a one-time sign-in or reset link could be used up; set
    `fetchLinks: false` in `~/.config/quickshell/launcher/ClipboardMode.qml` to show only
    the address.
  - *Emoji:* search by name or keyword ("lol"). `Enter` types the emoji into the window you
    were in (and copies it), `Alt+1` only copies it.
  - *Files:* searches your home folder (skipping hidden and git-ignored files); `Enter` opens.
  - *Calculator:* the result updates as you type. `Enter` pastes it into the window you were
    in (and copies it), `Alt+1` only copies it, `Ctrl+Enter` saves it to the history
    underneath.
  - *Windows:* `Enter` or a click jumps to the window, switching workspace if needed.
  - *Screenshot* / *Record Screen* (or `Super+Shift+P`, or `Print`): one menu, growing
    out of the island, for both. **Screenshot**: an **Area** (drag a rectangle; `Esc`
    cancels), a **Window** (click one) or the **Screen**, and *draw on it after* (`E`),
    which opens it in [satty](https://github.com/gabm/Satty) to draw and write on.
    **Record**: the same three, and the sound: none, *computer* (what you hear) or *mic*
    (`S` changes it). Under both, a delay (none, 3, 5 or 10 s, counted down in the island;
    `D` changes it). Click a tile, or choose one with the arrows (or `1`-`6`) and press
    `Enter`; the menu goes away as it starts.
    Every screenshot is copied to the clipboard and saved in `~/Pictures/Screenshots`,
    and the island says so, with buttons to open it or draw on it.
    While a recording runs, the island shows a red dot and the time: click it to stop (it
    turns into a stop button when you point at it), or press `Super+Shift+P` and `Enter`.
    The video is saved in `~/Videos/Recordings` (MP4) and copied as a file, so you can
    paste it into a chat or a folder; the island says so, with buttons to open it or show
    it in its folder. It records with [wf-recorder](https://github.com/ammen99/wf-recorder).
    The graphics card encodes it when it can (on Intel that needs `intel-media-driver`,
    on AMD `libva-mesa-driver`), otherwise the processor does.
  - *Change Wallpaper* (or `Super+W`): see [Changing the wallpaper](#changing-the-wallpaper).
- **Answers:** type one of these and press `Enter`. A card shows the result, already copied;
  `Enter` again pastes it into the window you were in, `Alt+1` just closes the card:

| You type | You get |
|---|---|
| `7 * 6`, `sqrt(2)`, `2^10` | maths |
| `5 km to miles`, `30 °C to °F` | unit conversion |
| `100 usd`, `20 eur to gbp` | currency (to your local currency when no target is given), with the date of the rates |
| `15:39 utc`, `3pm est to tokyo`, `now in new york` | time zones |
| `15 oct aoe`, `oct 15 5pm aoe to london` | AoE deadlines in your local time, with a countdown |

The local currency is set as `LOCAL_CURRENCY` near the top of
[`config/quickshell/scripts/evaluate.py`](config/quickshell/scripts/evaluate.py) (default `inr`).
Exchange rates come from `qalc`, and `qalc-rates.timer` refreshes them daily; that's the
only automatic download (apart from Oh My Zsh's own update check).

## The dynamic island

The pill in the middle of the bar changes shape with what's going on:

- **While the screen records:** a red dot and the time, before everything else; click it
  to stop.
- **Normally:** your desktops as page dots (the one you're on is a short bar in the
  accent colour, sliding along as you switch; a red dot is a desktop with a window
  wanting attention; click a dot to go there), then the date and time. Scroll on it to
  go to the next or previous desktop. While something plays, the
  album cover and a live audio visualizer (cava) join them; a small dot appears while an
  app is using the microphone, and a badge counts your unread notifications (red if one
  is critical).
- **For a moment:** new notifications (icon, title and text; low-urgency ones for 3 s,
  normal ones for 5 s, critical ones in red until you open the island), volume changes
  (with a level bar), the sound output switching, Bluetooth devices connecting or
  disconnecting, a new song starting, and on laptops charging / on battery and low
  battery (in red).
- **Click the date and time:** the island opens into the time in large type, the song
  playing (cover, title, artist, a bigger visualizer, a progress bar you can click to
  jump, previous / play-pause / next), the calendar, and beside it your unread
  notifications. It stays open until you click somewhere else or press `Esc`. (Hovering
  the island only stretches it out.) Middle-click plays / pauses.

**Notifications** all come through the island; there are no separate popups. After it
has shown them, they wait in the open island until you deal with them: click one for the
app's default action, use its buttons, close it with `×` or a right click, or press
*Clear all*. Notifications an app marks as temporary, or gives its own timeout, go away
by themselves.

The visualizer moves for any sound, not only music players; the cover and controls need
an app that supports media controls (MPRIS: Firefox, Spotify, mpv with mpv-mpris, ...).

**The calendar** in the open island:

- **Getting around:** `‹` `›` or the scroll wheel go a month back or forward. Click the
  title for the months of the year, and again for years, to jump far; *today* comes
  back. Week numbers are on the left, and days from the months either side can be
  clicked too.
- **Events:** click a day to see its events below the month (a dot marks days that have
  some), each in its calendar's colour. Type into *add an event* and press `Enter`:
  `14:30 dentist`, `9am standup`, `2:30pm-3pm call`, or just a title for an all-day
  event. The buttons beside it choose the calendar (when there's more than one) and make
  the next event repeat weekly, monthly or yearly. Double-click a day to start typing
  straight away. While you type, the island stays open until you press `Esc` or click
  elsewhere. Changes show straight away and go to your Mac and phone right after.
- **Moving events:** drag an event onto another day in the month and it moves there, at
  the same time. Hold it over `‹` or `›` to go to another month on the way; `Esc` lets go
  of it. Hold `Ctrl` as you drop it for a copy instead. For a repeating event, the
  calendar asks whether to move just that day's or all of them (`Enter`: just that
  day's); moving all of them moves the series along, so a weekly Monday meeting dropped
  on a Tuesday repeats on Tuesdays.
- **Changing events:** double-click an event (or click its pencil) and it comes into the
  field the way you'd type it, `09:30–10:00 Standup`: change the time or the title, or
  pick another calendar or repeat with the buttons beside it, and press `Enter`; `Esc`
  leaves it as it was. Taking the time away makes it all day. A repeating event changes
  as a whole.
- **Deleting:** hover an event and click `×`, then *delete*; for a repeating one, *this
  one* (only that day's) or *all*.
- **Undo:** after each change the calendar says what it did, with an *undo* button for a
  few seconds; `Ctrl+Z` undoes changes one by one. Undo puts the event's file back as it
  was, so a change made to the same event on your Mac meanwhile would be undone too.
- **Reminders:** the island announces each event 10 minutes before it starts, and again
  when it starts.
- **Keys** (after clicking in the calendar): `←` `→` a day, `↑` `↓` a week,
  `Page Up` / `Page Down` a month, `Home` today, `Enter` add an event, `Ctrl+Z` undo,
  `Esc` back or close. The list of a day's events scrolls with the wheel.
- **Where events live:** your calendars are folders of `.ics` files in
  `~/.local/share/calendars/` (one per calendar; a *Personal* one to start with), read
  through [khal](https://khal.readthedocs.io). In a terminal, `khal list` and `ikhal`
  show and edit the same events. Changes made here touch only the lines they change in
  an event's file, so the extra details your Mac keeps (places, alerts, ...) stay.

### Syncing with your Mac and phone

The calendars can stay in step with the Calendar app on a Mac and an iPhone, over
[Tailscale](https://tailscale.com), without any cloud: this machine runs a small calendar
server ([Radicale](https://radicale.org)) that only it can reach, Tailscale makes it
reachable over HTTPS from your own devices (and nobody else), and
[vdirsyncer](https://vdirsyncer.pimutils.org) keeps the server and the calendar folders
here in step (every 5 minutes, and straight away when you change something in the
island; what comes in shows in the island as soon as it arrives).

1. **This machine on your tailnet**, if it isn't yet:
   `sudo systemctl enable --now tailscaled`, then `sudo tailscale up` and log in with the
   same account as your Mac. In the Tailscale admin console, *DNS* should have MagicDNS
   and HTTPS certificates turned on.
2. **Run** `~/.config/quickshell/scripts/calendar-sync-setup.sh`. It asks for a username
   and a password for the calendar server, starts it, serves it to your tailnet on port
   8443, does a first sync, and prints the server address (like
   `https://yourmachine.your-tailnet.ts.net:8443/`). With OpenSnitch running, it also adds
   a rule letting programs on this machine reach the calendar server (127.0.0.1, port
   5232); without it, OpenSnitch holds vdirsyncer's connection and nothing syncs. Run the
   script again any time to repair and re-sync (`--new-password` to change the password).
3. **On the Mac:** Calendar → Settings → Accounts → `+` → *Other CalDAV Account…*,
   account type *Manual*, with that username, password and server address. To bring over
   your *On My Mac* calendars: select one, File → Export → Export…, then File → Import…,
   pick the file and choose a calendar of the new account (*Personal*, or one you make
   with File → New Calendar → the new account). Once everything has arrived, the *On My
   Mac* calendar can go. Set the account to refresh every minute or every 5 minutes.
4. **On the iPhone** (with Tailscale on): Settings → Apps → Calendar → Calendar
   Accounts → Add Account → Other → *Add CalDAV Account*, with the same details.

New calendars made on any side appear on the others. If the same event is changed in
two places between syncs, the Mac's (the server's) version wins. The Mac and phone sync
whenever they can reach this machine over Tailscale; changes made while it's off wait
until it's back.

**Only one server.** Run the setup script on one machine only. On a second Linux machine
it would start a second, empty server rather than join the first one.

#### Reinstalling the server

The Mac and phone mirror whatever is on the server, so a reinstalled machine with an
empty server would empty their calendars too. Before wiping the machine:

1. Back up `~/.local/share/radicale/` (the server's calendars). To be extra safe, also
   export each calendar on the Mac (select it, File → Export → Export…).
2. In the [Tailscale admin console](https://login.tailscale.com/admin/machines), remove
   the old machine, so the reinstalled one gets the same name (and the server address
   on your Mac and phone stays right).

After `install.sh`, put `~/.local/share/radicale/` back where it was, *then* run the
setup script. Give it the same username and password as before, so your Mac and phone
keep working, and it carries on with the calendars that are there.

## The lock screen

`Super+Escape` (or *Lock* in the power menu or the launcher) locks the session. The lock
screen looks like the login screen, and checks your password the same way your login does.
It also has suspend, reboot and power-off buttons. After the right password your desktop is
there straight away.

On both, the password never shows, not even as dots: there's no field, just a thin line
under your name that fills out from the middle as you type (full at 12 characters). Every
key sends a bright glint from the middle out to both ends, so you can see you're still
typing once it's full; deleting sends it the other way, from the ends in to the middle. It pulses while the password is checked, and turns red and empties
if it was wrong. Enter unlocks / logs in.

If the shell isn't running when you lock, hyprlock locks instead (same look). If the lock
screen ever crashed, Hyprland would keep the session locked. To get a lock screen back,
switch to a text console (`Ctrl+Alt+F2`), log in, run
`hyprctl --instance 0 dispatch 'hl.dsp.exec_cmd("hyprlock")'`, then switch back
(`Ctrl+Alt+F1`) and unlock there.

## Changing the wallpaper

Press `Super+W` (or pick *Change Wallpaper* in the launcher). The picker grows out of the
island with your pictures from `~/Pictures/Wallpapers` (and folders in it) as a grid,
newest first. The one showing is marked *now*, and comes first if it's from somewhere
else. Type to narrow them down by name or folder, choose with the arrows (or `Tab`), and:

- `Enter` or a click sets it and closes the picker, so you see it come in.
- `Shift+Enter` or a right click sets it and keeps the picker open, to try a few.
- `Ctrl+R` (or *random*) sets one at random; `Ctrl+O` (or *folder*) opens the folder, to
  add more.

Each new wallpaper comes in with a transition picked at random: a **wave** or a **wipe**
sweeping across from any side, a circle **growing** out of the pointer (where you
clicked), the island, the middle or anywhere, a circle **closing in** on one of those, or
now and then a soft **fade**, each with its own angle, size and easing. They run at your
screen's refresh rate; tune them in `~/.config/quickshell/scripts/wallpaper.sh`.

From a terminal or a script:

```sh
qs ipc call wallpaper set ~/Pictures/Wallpapers/your-image.jpg   # or just its name
qs ipc call wallpaper random
~/.config/quickshell/scripts/wallpaper.sh your-image.jpg         # without the shell
~/.config/quickshell/scripts/wallpaper.sh your-image.jpg grow    # always that kind
awww img your-image.jpg                                          # awww's own plain fade
```

Whichever way it's set, a small watcher notices the change and regenerates the whole
palette within a couple of seconds; the shell's colours fade over to it. Apps that are
already open pick up new colours when you restart them; the bar, window borders, terminal
and notifications update right away.

## Customising

| What | Where |
|---|---|
| Keybindings, gaps, blur, dimming, startup apps | `~/.config/hypr/hyprland.lua` (Hyprland's Lua config) |
| Frame, bar, menus, notifications | `~/.config/quickshell/` (`bar/`, `notifications/`); the frame's width and corners and the bar's size in `services/Theme.qml`. Saving a file reloads the shell |
| Dynamic island | `~/.config/quickshell/bar/DynamicIsland.qml`; what it announces in `services/Activities.qml` |
| Calendar | `~/.config/quickshell/bar/Calendar.qml`; events and reminders in `services/Events.qml` (through `scripts/calendar-events.py`); khal in `~/.config/khal/config` |
| Calendar sync | `~/.config/quickshell/scripts/calendar-sync-setup.sh`; the server in `~/.config/radicale/config`, syncing in `~/.config/vdirsyncer/config` (written by the setup) and the `calendar-sync.timer` user service |
| Launcher look / commands | `~/.config/quickshell/launcher/` (`LauncherWindow.qml`; commands in `MainMode.qml`) |
| Wallpaper picker / transitions | `~/.config/quickshell/launcher/WallpaperPanel.qml`; the transitions (and how often each comes up) in `~/.config/quickshell/scripts/wallpaper.sh`, the folder in `services/Wallpaper.qml` |
| Lock screen | `~/.config/quickshell/lock/LockContent.qml` |
| How colours map to each app | `~/.config/matugen/templates/` (edit these, not the generated files) |
| Qt transparency | `WINDOW_TRANSPARENCY` in `~/.config/hypr/scripts/kvantum-theme.py` |
| GTK transparency | `window_bg_color` in `~/.config/matugen/templates/gtk.css` |
| Shell prompt / plugins | `ZSH_THEME` and `plugins` in `~/.zshrc`; your own aliases in `~/.zshrc.local` |
| Login screen | `~/.config/sddm-theme/islands-aurora/Main.qml`, then `sudo ~/.config/sddm-theme/install.sh` |

Fonts: the bar, launcher, notifications, and the login and lock screens use *Noto Sans*
(`noto-fonts`); emoji use *Noto Color Emoji* (`noto-fonts-emoji`). zathura uses
*DroidSansM Nerd Font* (`otf-droid-nerd`). Qt/KDE apps use *Noto Sans 9* (set in
qt5ct/qt6ct). GTK apps and kitty keep their defaults (Adwaita Sans for GTK, the system
monospace font for kitty).

## Notes

- **Hyprland version:** this uses Hyprland's **Lua config** (`hyprland.lua`, Hyprland 0.56+).
  Commands sent with `hyprctl dispatch` use Lua syntax, for example
  `hyprctl dispatch 'hl.dsp.focus({ workspace = 2 })'`.
- **Upgrading from the Waybar / rofi version:** remove the old bar, notification daemon and
  launcher (`sudo pacman -Rns waybar dunst rofi rofi-calc rofi-emoji`). Otherwise dunst can
  still be started for an early notification at login and keep notifications from reaching
  the shell.
- **Solid apps:** Electron apps (Discord, VS Code) and Firefox can't draw see-through
  backgrounds, so they stay solid.
- **Black moment at login:** after you log in the screen stays black for a moment (up to a
  few seconds right after booting) while SDDM hands the screen to Hyprland and the monitor
  switches over; the theme can't draw anything then. The blurred login image follows,
  and at 3.5 s into the session it fades into your wallpaper
  (`~/.config/hypr/scripts/start-wallpaper.sh`).

## Uninstall / restore

Your previous configs are in `~/.config-backup-<date>/`; copy them back into `~/.config`.
To go back to a text login: `sudo systemctl disable sddm`.
