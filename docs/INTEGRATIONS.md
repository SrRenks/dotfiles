# What reddoted integrates

An inventory of every outside program the desktop touches, what you lose without
it, and how to drop it. Written to be read top-down when deciding what a machine
actually needs.

Two layers, and only the first one is mandatory.

## Layer 1, plumbing

Without these the desktop does not come up, or comes up inert. No profile drops
them.

| Program | Called from | If absent |
| --- | --- | --- |
| `Hyprland` (`hyprctl`) | 27 files: keybinds, rules, bar, OSD, workspaces | nothing can move a window |
| `quickshell` (`qs`) | the shell itself, `rice` CLI, IPC | no shell at all |
| `jq` | `hypr/scripts/startup-run.sh`, `shortcuts-apply.sh` | startup apps and custom shortcuts silently do nothing |
| `ghostty` + `fish` | every keybind that opens a terminal | no terminal |
| `curl` | weather, lyrics, the AI panels | those three panels stay empty |

## Layer 2, features

Each row is independent: dropping it loses that feature and nothing else. Almost
none of them are guarded, the shell does not check `command -v` before calling,
so a missing binary shows as an empty panel or a key that does nothing. That is
the whole reason this document exists.

| Feature | What you see | Calls | Group | Drop it if… |
| --- | --- | --- | --- | --- |
| Battery | cell % in the bar, charge-care in Prefs | `upower`, `/sys` | `session` | never on a laptop |
| Backlight | brightness OSD, mute LEDs | `brightnessctl` | `shell-core` | never |
| Volume | volume OSD, media keys | `wpctl` (wireplumber) | `audio` | never |
| Now playing | media panel, per-player icons | `mpris-proxy` (playerctl) | `shell-core` | you never play audio from the shell |
| Lyrics | scrolling lyrics in the media panel | `lrclib.net` |, (network) | you do not want a request per track |
| Clipboard | `Super+V` history, paste-into-field | `cliphist`, `wl-paste` watcher at login, `wl-copy` | `shell-core` | you live inside the terminal |
| Screenshots | region/window/monitor | `grim`, `slurp` | `shell-core` | never |
| Screenshot editor | annotate before saving | `swappy` | `shell-extras` | you always take it raw → **droppable** |
| Screen recording | `Super+R` | `gpu-screen-recorder` | `shell-extras` | you never record → **droppable** |
| Calculator | type `=2+2` in the launcher | `qalc` | `shell-extras` | you use a real calculator → **droppable** |
| Trash expiry | `trash-empty 30` at login, trash panel | `trash-cli` | `shell-extras` | you never delete through the shell → **droppable** |
| Notifications | OSD popups | `notify-send` (libnotify) | `shell-core` | never |
| Power menu | lock, logout, suspend, reboot | `systemctl` | `session` | never |
| Lock | `Super+L`, fingerprint conversation | PAM, `hypridle` | `session` | never |
| Idle / night light | screen off, blue-light filter | `hypridle`, `hyprsunset` | `session` | never |
| Weather | temperature in the bar | `curl` → `api.open-meteo.com`, **`ipinfo.io/loc`**, `geoclue` | `geo` | you do not want your IP geolocated → **droppable** |
| AI panel | model list, token balance, key test | `api.anthropic.com`, `api.deepseek.com`, `generativelanguage.googleapis.com` + **`gnome-keyring`** (keys live in the secret service, never on disk) | `session` | you do not want three AI APIs touched → **droppable** |
| Updates | "N repo · N aur · N flatpak" in the bar | `pacman`, `checkupdates`, `yay`/`paru`, `flatpak` | `updates` | you update by hand → **droppable** |
| Buds | Nothing / CMF earbuds battery and ANC | BlueZ + vendor protocol | `network` | you have no Nothing earbuds → **droppable** |
| Game mode | keep-list, animations off | `hyprctl` |, (config) | never game → toggle same, no package |
| VPN panel | Clash Verge state | `clash-verge-rev-bin` (AUR) |, (optional) | you do not use Clash → **droppable** |
| ThinkPad | fan curve, LEDs, battery care | `tlp`, `brightnessctl`, `/sys` | `power` | not a ThinkPad → swap the group |
| Deck vitals | Steam Deck strip in the bar | `sh`, `nvidia-smi` if present |, (config) | you have no Deck → **droppable** |
| Startup apps | Prefs → STARTUP | `jq`, `startup.json`, `hyprctl` |, (config) | you do not manage autostart → **droppable** |
| Custom shortcuts | Prefs → SHORTCUTS | `jq`, `shortcuts.json`, `hyprctl` |, (config) | you edit Lua directly → **droppable** |
| Emoji charms | kaomoji/emoji picker | `wl-copy`, bundled `charms.js` | `shell-core` | never used → **droppable** |
| Wallpaper per monitor | `Super+W` | bundled assets |, (config) | never |
| Paste into field | types the clipboard into the focused field | `ydotool` + `input` group + user service | `input` | you never use that bind → **droppable** |
| File manager | `Super+E`, `inode/directory` | `dolphin` | `apps` | you use yazi for everything → swap for yazi |
| Editor app | `Super+Shift+K` | `codium` | `apps` | you only use the terminal → **droppable** |
| Audio settings | `pavucontrol` bind | `pavucontrol` | `apps` | never → **droppable** |
| Qt palette sync | Qt apps follow the wallpaper | `qtengine`, `darkly-bin` (AUR) | `aur-theming` | you only run GTK/terminal apps → **droppable** |
| Cursor | Bibata pointer | `bibata-cursor-theme-bin` (AUR) | `aur-cursor` | you like the default → **droppable** |
| Greeter | Glyph-themed login | `sddm` | `greeter` | you boot straight into Hyprland → **droppable** |

Writes deserve their own page: [`SIDE-EFFECTS.md`](SIDE-EFFECTS.md) lists every
file, service and sysfs value the desktop changes, including the `pkexec` calls
that own the battery, the fan and the ACPI profile.

## The network surface

The shell talks to six endpoints. Four of them you can turn off without losing
the desktop.

| Endpoint | Feature | Off switch |
| --- | --- | --- |
| `api.open-meteo.com` | weather | Prefs → BAR → widgets: remove `weather` |
| `ipinfo.io/loc` | fallback location when geoclue is absent | same widget; dropping the `geo` group also stops geoclue |
| `lrclib.net` | lyrics in the media panel | Prefs → BAR → widgets: remove `media` |
| `api.anthropic.com` | AI panel model list | Prefs → AI, remove the key |
| `api.deepseek.com` | AI panel balance | same |
| `generativelanguage.googleapis.com` | AI panel model list | same |

Nothing else was found: the shell does not phone home, and the update probe only
runs when the widget is enabled.

## How to drop things

Three levels, cheapest first.

**1. Profiles**, the installer is already a chooser:

```sh
./install.sh --profile minimal    # 57 packages: the desktop, minus the frills
./install.sh --profile standard   # 73: everything the rice ships, optional off
./install.sh --profile full       # + aur theming, cursor, greeter, flatpak, geoclue
```

**2. Individual groups**:

```sh
./install.sh --only base,session,terminal,reddoted,links,wiring
```

The choice is written to `~/.config/dotfiles/groups`, and `deps/check.py` audits
*that* set from then on, a deliberate omission is not reported as a missing
dependency. `python3 deps/check.py --all` ignores the file and audits everything.

**3. The surface itself.** Dropping a package alone leaves a dead panel or a
silent key. After removing one, also:

| Removed | Also do |
| --- | --- |
| `swappy`, `gpu-screen-recorder` | Prefs → SHOT: the page reads both tools to fill "open screenshot" / "open recordings" (~/Videos); without them it just reports nothing |
| `trash-cli` | Prefs → not exposed: edit `glyph/services/*`, or accept `trash-empty` failing at login |
| `qalc` | the launcher's `=` mode just shows nothing |
| AI panels | Prefs → AI: clear the keys (stored in the secret service, so `gnome-keyring` is what actually holds them) |
| Weather / media / AI / updates | Prefs → BAR → **widgets**: the bar is a list (`clock, weather, perf, net, media, battery, audio`); removing one stops its work and its requests |
| `ydotool` | remove the paste-into-field bind in `config/hypr/hyprland/keybinds.lua:247` |
| `dolphin`, `codium`, `pavucontrol` | `config/hypr/variables.lua`: point `fileExplorer`, `apps.editor`, `audioSettings` elsewhere, or set to `nil` to disable the bind |
| `sddm` | nothing; `install.sh --sddm` is the only thing that touches it |

## A practical starting point

Everything above is independent, so prune by what you never press rather than by
what sounds heavy. The three that cost the most and do the least on a machine
like this one:

1. **`shell-extras`**, recorder, screenshot editor, calculator, trash. One
   group, five packages, and nothing in the bar changes shape without them.
2. **`geo` + the weather widget**, two network requests per refresh, one of
   them a third-party IP lookup.
3. **`greeter`**, the machine already boots Hyprland directly; `sddm` is a
   system service you are not using.

The plumbing is not negotiable: `hyprctl`, `qs`, `jq`, `ghostty`, `fish` and
`curl` are how the shell is a shell.
