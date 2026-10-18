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
- **Floating "island" bar.** Waybar pills for workspaces, window title, clock, stats,
  tray, sound and power, with line icons redrawn in the current palette.
- **Raycast-style launcher.** One rofi menu for apps and commands: clipboard history,
  emoji, file search, window switcher, system actions. Type maths, unit and currency
  conversions, time zones or AoE deadlines and press Enter for an answer card.
- **Themed login and lock.** An SDDM theme on the blurred wallpaper and a matching
  hyprlock screen.
- **zsh with Oh My Zsh and fzf.** zsh becomes your login shell, with autosuggestions,
  syntax highlighting and fzf for files, history and directories, coloured from the wallpaper.

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
   up first to `~/.config-backup-<date>/`.
3. **Sets up the shell:** clones [Oh My Zsh](https://ohmyz.sh) into `~/.oh-my-zsh` (if it isn't
   there yet), installs [`home/.zshrc`](home/.zshrc) as `~/.zshrc` (backing up the old one) and
   makes zsh your login shell.
4. **Generates the theme:** uses the first image in `~/Pictures/Wallpapers`, or generates a soft
   gradient if there isn't one. [matugen](https://github.com/InioX/matugen) turns that image into
   a palette, which fills in every themed file.
5. **Applies app settings:** sets the dark GTK/KDE preferences, makes zathura the PDF viewer, and
   sets up Okular's highlighters.
6. **Enables services:** NetworkManager, Bluetooth, the polkit agent, a daily exchange-rate update for the
   calculator, and the SDDM login screen.

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
| `Super+Escape` | Lock screen |
| `Super+M` | Log out |
| `Super+H/J/K/L` or arrows | Move focus |
| `Super+Shift+H/J/K/L` | Move window |
| `Super+1…0` | Switch workspace |
| `Super+Shift+1…0` | Move window to workspace |
| `Super+V` | Toggle floating |
| `Super+S` | Scratchpad |
| `Super+D` | Restart the bar |

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

Open it with `Super+Space` and start typing:

- **Apps and commands:** type a name. Commands like *Clipboard History*, *Search Emoji*,
  *Search Files*, *Calculator*, *Switch Windows* and *Shut Down* also match partial words
  ("paste", "sleep", "math"). In a sub-menu, `Esc` goes back to the main menu.
- **Answers:** type one of these and press `Enter`. A card shows the result, already copied:

| You type | You get |
|---|---|
| `7 * 6`, `sqrt(2)`, `2^10` | maths |
| `5 km to miles`, `30 °C to °F` | unit conversion |
| `100 usd`, `20 eur to gbp` | currency (to your local currency when no target is given), with the date of the rates |
| `15:39 utc`, `3pm est to tokyo`, `now in new york` | time zones |
| `15 oct aoe`, `oct 15 5pm aoe to london` | AoE deadlines in your local time, with a countdown |

The local currency is set as `LOCAL_CURRENCY` near the top of
[`config/rofi/scripts/evaluate.py`](config/rofi/scripts/evaluate.py) (default `inr`).
Exchange rates come from `qalc`, and `qalc-rates.timer` refreshes them daily; that's the
only automatic download (apart from Oh My Zsh's own update check).

## Changing the wallpaper

```sh
awww img ~/Pictures/Wallpapers/your-image.jpg
```

That's all you need to run. A small watcher notices the change and regenerates the whole
palette within a couple of seconds. Apps that are already open pick up new colours when you
restart them; the bar, window borders, terminal and notifications update right away.

## Customising

| What | Where |
|---|---|
| Keybindings, gaps, blur, dimming, startup apps | `~/.config/hypr/hyprland.lua` (Hyprland's Lua config) |
| Bar layout / look | `~/.config/waybar/config.jsonc`, `~/.config/waybar/style.css` |
| Launcher look / commands | `~/.config/rofi/theme.rasi`, `~/.config/rofi/scripts/commands.sh` |
| How colours map to each app | `~/.config/matugen/templates/` (edit these, not the generated files) |
| Qt transparency | `WINDOW_TRANSPARENCY` in `~/.config/hypr/scripts/kvantum-theme.py` |
| GTK transparency | `window_bg_color` in `~/.config/matugen/templates/gtk.css` |
| Shell prompt / plugins | `ZSH_THEME` and `plugins` in `~/.zshrc`; your own aliases in `~/.zshrc.local` |
| Login screen | `~/.config/sddm-theme/islands-aurora/Main.qml`, then `sudo ~/.config/sddm-theme/install.sh` |

Fonts: the bar uses *Noto Sans* (`noto-fonts`). The launcher, login
and lock screens and zathura use *DroidSansM Nerd Font* (`otf-droid-nerd`). Qt/KDE apps use *Noto Sans 9* (set in qt5ct/qt6ct). GTK apps, kitty
and dunst keep their defaults (Adwaita Sans for GTK, the system monospace font for kitty).

## Notes

- **Hyprland version:** this uses Hyprland's **Lua config** (`hyprland.lua`, Hyprland 0.56+).
  Commands sent with `hyprctl dispatch` use Lua syntax, for example
  `hyprctl dispatch 'hl.dsp.focus({ workspace = 2 })'`.
- **Solid apps:** Electron apps (Discord, VS Code) and Firefox can't draw see-through
  backgrounds, so they stay solid.
- **Black moment at login:** after you log in there's a brief black moment while SDDM hands the
  screen to Hyprland. That's the monitor switching display sessions, and the theme can't hide it.

## Uninstall / restore

Your previous configs are in `~/.config-backup-<date>/`; copy them back into `~/.config`.
To go back to a text login: `sudo systemctl disable sddm`.
