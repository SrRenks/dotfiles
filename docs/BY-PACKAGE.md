# Dependencies, package by package

Generated from [`deps/deps.toml`](../deps/deps.toml) (what is installed) and
[`deps/usage.toml`](../deps/usage.toml) (who calls it). Regenerate with
`python3 deps/by-package.py`; it fails if a package has no evidence.

| Column | means |
| --- | --- |
| binary | what actually lands in `$PATH` (or the library / font name) |
| called by | the file that calls it, not the feature it resembles |
| if absent | what stops working, and whether it fails loudly or silently |

## Base (`base`)

_Build tools (AUR helper, makepkg), stow (the link engine), plus what every script here calls_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `base-devel` | `makepkg` | install.sh builds yay-bin from the AUR; also compiles any AUR package | no AUR helper → qtengine, darkly-bin and thinkfan cannot be installed |
| `git` | `git` | install.sh (clone reddoted), fisher, ya pkg, install.sh --update | nothing can be fetched or updated |
| `curl` | `curl` | services/Weather.qml (api.open-meteo.com), services/Media.qml (lrclib.net), fisher bootstrap, package-updates.sh | weather, lyrics and the flatpak/aur probe go silent, _the shell also calls it for the AI panels' provider APIs_ |
| `jq` | `jq` | hypr/scripts/{startup-run,shortcuts-apply,special-toggle,minimize-toggle}.sh, package-updates.sh, system/package-updates.sh | autostart, custom shortcuts and the update parser all exit 0 doing nothing, _silent: the scripts test for jq and give up_ |
| `python` | `python3` | deps/query.py and deps/check.py (this repo), Prefs calculators | the installer cannot read its own manifest |
| `stow` | `stow` | install.sh step 7, the only thing that puts configs in $HOME | no links at all |

## Graphics (`graphics`)

_Hyprland + Quickshell rendering. AMD Radeon 780M aboard; swap the second half for intel/nvidia on another machine_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `mesa` | `libGL` | Hyprland and Quickshell render through it; mpv and yazi decode with it | no desktop at all |
| `vulkan-radeon` | `libvulkan` | Hyprland's Vulkan renderer, gpu-screen-recorder | software rendering, recording fails, _machine-specific: intel → vulkan-intel, nvidia → nvidia-utils_ |
| `libva-mesa-driver` | `libva` | hardware video decode in mpv (yazi's video preview) | video previews decode on the CPU |

## Session and shell plumbing (`session`)

_Compositor, idle/night-light/picker, portals, shell, keyring (AI keys go to the secret service via secret-tool), power/battery_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `hyprland` | `hyprctl` | 27 files: keybinds.lua, rules.lua, bar/Bar.qml, Apply.qml, every script | nothing can move, colour or configure a window |
| `hypridle` | `hypridle` | settings/Rules.qml writes ~/.config/demonshot/hypridle.conf and does pkill -x hypridle; exec hypridle -c | screen never blanks or locks on idle |
| `hyprsunset` | `hyprsunset` | keybind (blue-light filter), Prefs | night light does nothing |
| `hyprpicker` | `hyprpicker` | keybind, colour picker from the wallpaper | picker bind does nothing |
| `xdg-desktop-portal-hyprland` | `xdg-desktop-portal-hyprland` | portal for screenshots and screencast | screenshot/recording portals fail; some Flatpak apps cannot capture |
| `xdg-desktop-portal-gtk` | `xdg-desktop-portal-gtk` | file chooser dialogs, settings portal | flatpak apps lose file dialogs and dark mode |
| `quickshell` | `qs` | the shell itself; `rice` CLI; IPC (Super+Shift+F glass toggle) | no shell |
| `polkit-gnome` | `polkit-gnome-authentication-agent-1` | the password prompt behind every pkexec (ACPI profile, TLP charge, ThinkPad helper) | the privileged pages hang with no prompt |
| `gnome-keyring` | `gnome-keyring-daemon` | execs.lua starts it with --components=secrets; the AI panel stores keys here | AI keys cannot be saved |
| `libsecret` | `secret-tool` | prefs/pages/AiPage.qml, secret-tool store/lookup/clear, service glyph-ai | saving an API key silently does nothing |
| `upower` | `upower` | bar battery widget, Prefs BATTERY | no battery percentage, no charge state |
| `xdg-user-dirs` | `xdg-user-dir` | hypr/scripts/shot-quick.sh resolves PICTURES; install.sh runs xdg-user-dirs-update | screenshots fall back to ~/Pictures |

## Audio (`audio`)

_PipeWire stack; wpctl is called by the OSD and the volume keys_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `pipewire` | `pipewire` | the audio server behind wpctl and every player | no sound |
| `pipewire-pulse` | `pipewire-pulse` | PulseAudio compatibility, needed by pavucontrol and playerctl | mixer apps cannot see streams |
| `pipewire-alsa` | `libasound_module_pcm_pipewire` | ALSA compatibility for apps without a Pulse backend | some apps have no audio |
| `wireplumber` | `wpctl` | keybinds (volume up/down/mute), the volume OSD | volume keys do nothing |

## Network and Bluetooth (`network`)

_NetworkManager; nmcli is read by Prefs, bluetoothctl by the buds panel_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `networkmanager` | `nmcli` | network panel in Prefs and the bar | no connection list or toggle |
| `bluez` | `bluetoothctl` | buds/ panel (Nothing / CMF earbuds), bluetooth settings | no Bluetooth at all |
| `bluez-utils` | `bluetoothctl` | same panel, this package is what ships the CLI | the buds panel has no backend |

## Power (`power`)

_TLP is the power manager on this machine (reddot-tlp, fan curve). power-profiles-daemon is the upstream default but conflicts, see [[conflict]]_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `tlp` | `tlp` | prefs/pages/BatteryPage.qml: pkexec tlp setcharge <start> <end> BAT0; services/EdgeService.qml: pkexec tlp fullcharge | charge thresholds page and the bar's fullcharge action |

## Shell core (`shell-core`)

_What the QML shell calls in every session: bar, OSD, media, clipboard, screenshots, notifications. Losing one of these loses a panel, not a feature_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `brightnessctl` | `brightnessctl` | services/Backlight.qml, MuteLeds.qml, ThinkPadLedGuard.qml; brightness OSD | brightness keys, LED mute indicator |
| `playerctl` | `playerctl and mpris-proxy` | services/Media.qml, media keybinds; execs.lua runs mpris-proxy at login | now-playing panel and media keys |
| `wl-clipboard` | `wl-copy, wl-paste` | charms (copy emoji), clip panel, and the login watcher wl-paste --watch cliphist store | clipboard history is never filled; copy actions fail |
| `cliphist` | `cliphist` | clip/Clip.qml, Super+V history, the two wl-paste watchers at login | no clipboard history |
| `grim` | `grim` | hypr/scripts/shot-quick.sh (all three screenshot modes) | no screenshots |
| `slurp` | `slurp` | hypr/scripts/shot-quick.sh region mode | region select does not start |
| `imagemagick` | `magick` | wallpaper pipeline and thumbnails (rice), yazi's zoom plugin | wallpaper thumbnails and image zoom |
| `libnotify` | `notify-send` | 8 files: services/Ai.qml, EdgeService.qml, notifications on state changes | shell notifications silently drop |

## Shell extras (`shell-extras`)

_Features the desktop survives without: screenshot editor, screen recorder, calculator in the launcher, trash expiry, image pipeline_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `swappy` | `swappy` | shot/Editor.qml after a screenshot; Prefs > SYSTEM checks it | annotating a screenshot; the System page reports it missing |
| `gpu-screen-recorder` | `gpu-screen-recorder` | hypr/scripts/rec-toggle.sh, Super+R | no screen recording |
| `libqalculate` | `qalc` | launcher/Launcher.qml mode 3 (= expression); Prefs > SYSTEM checks it | the launcher's calculator mode shows nothing |
| `libvips` | `vips` | image processing in the wallpaper/thumbnail path | wallpaper tones fall back to a slow path |
| `trash-cli` | `trash` | execs.lua runs trash-empty 30 at login; Prefs > SYSTEM checks it | trash never expires; the System page reports it missing |

## Synthetic input (`input`)

_ydotool types into the focused field (bind: paste clipboard). Needs the input group and its user service_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `ydotool` | `ydotool` | hypr/hyprland/keybinds.lua:247, types the clipboard into the focused field | that bind does nothing, _needs the input group and the ydotool user service; dotool is the alternative_ |

## Terminal (`terminal`)

_The terminal stack: Ghostty renders it, fish drives it, tmux/tabs, yazi is the file manager, starship the prompt_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `ghostty` | `ghostty` | variables.lua terminal; every bind that opens a shell; the hub's own stow package | no terminal, _standalone profile: the hub ships its config_ |
| `fish` | `fish` | the login shell; ghostty runs it; fisher plugins | the shell falls back to bash, all fish configs are dead |
| `tmux` | `tmux` | config/tmux/tmux.conf; popups for yazi/lazygit/btop/sessions | no multiplexer, no popups |
| `yazi` | `yazi` | SUPER+E, inode/directory, tmux popup, fish Ctrl+O and Alt+Y, `n` with no args | no file manager anywhere |
| `starship` | `starship` | conf.d/10-shell.fish | prompt silently falls back to fish's own |

## Terminal tools (`terminal-tools`)

_Binaries the terminal configs call: eza/zoxide/direnv (fish), fd/fzf (pickers), bat (preview + cat), 7zip/ffmpeg/poppler (yazi previews), lazygit/mpv/btop/cava/fastfetch (popups and widgets)_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `eza` | `eza` | conf.d/20-aliases.fish, ls, ll, la, lla, lt | aliases fall back to plain ls |
| `zoxide` | `zoxide` | conf.d/10-shell.fish, `z` and `cd` become jumps | cd stops being frecency-aware |
| `direnv` | `direnv` | conf.d/10-shell.fish hook | no per-directory .envrc |
| `fd` | `fd` | yazi `search --via=fd`, FZF_DEFAULT_COMMAND, fish fzf bindings | yazi search and fzf fall back or fail |
| `fzf` | `fzf` | fish Ctrl+R/Ctrl+T/Alt+C, tmux sessions popup, fif | every picker |
| `bat` | `bat` | `cat` alias, fif preview, MANPAGER, yazi's text preview | cat loses its palette, man pages lose highlighting |
| `ripgrep` | `rg` | fish `fif` (search → fzf → nvim), yazi `search --via=rg` (key S), FZF_DEFAULT_COMMAND fallback | content search in yazi and fif do nothing |
| `7zip` | `7z` | yazi archive preview and the extract opener; fish `extract` | archives stop previewing and extracting |
| `ffmpeg` | `ffmpeg` | yazi video previewer (frames), ffprobe metadata | video previews show nothing |
| `poppler` | `pdftoppm` | yazi PDF previewer | PDF previews blank |
| `lazygit` | `lazygit` | tmux popup (prefix+g), fish `lg` abbr | the git popup exits immediately |
| `mpv` | `mpv` | yazi `play` opener, video and audio | opening media falls back to xdg-open |
| `btop` | `btop` | tmux popup (prefix+b) | the btop popup exits immediately |
| `cava` | `cava` | services/Cava.qml runs it with glyph/cava/cava.conf; `cava` alias uses the dots profile | the bar's spectrum widget is empty |
| `fastfetch` | `fastfetch` | stow/fastfetch config (hub); reddoted's copy is currently missing | fastfetch prints its stock output |

## tty (`tty`)

_Mouse on the virtual console. gpm serves the console apps that speak libgpm (vim, less, mc, links); tmux cannot use it, it needs escape sequences only a terminal emulator emits. Optional because gpm grabs /dev/input/mice: if the touchpad misbehaves in Hyprland, disable gpm again_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `gpm` | `gpm` | gpm.service on the console; libgpm is what vim, less, mc and links call | no mouse at all on a tty, only the keyboard |

## Fonts (`fonts`)

_JetBrains Mono Nerd (glyphs in bar/yazi/eza), Space Mono (Glyph typeface, bundled in reddoted), CJK for kaomoji, emoji for Charms_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `ttf-jetbrains-mono-nerd` | `JetBrainsMono Nerd Font` | Ghostty fallback font, every icon in the bar, eza --icons, yazi filetype icons | every glyph becomes a box |
| `noto-fonts` | `Noto Sans` | fallback for text the mono font lacks | some glyphs vanish |
| `noto-fonts-cjk` | `Noto Sans CJK` | charms kaomoji and CJK in file names | CJK renders as boxes |
| `noto-fonts-emoji` | `Noto Color Emoji` | charms emoji picker | emoji render as boxes |

## Icons and GTK (`icons`)

_Papirus/Rice folder icons and the dark GTK base the shell's gtk.css layers on_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `papirus-icon-theme` | `Papirus` | folder colour theme (`grey` in glyph/term/folders), applied by rice | stock folder icons |
| `adw-gtk-theme` | `adw-gtk3-dark` | install.sh sets gsettings gtk-theme; the generated gtk.css layers on top | GTK apps look unstyled |

## Audio applications (`audio-tools` · optional)

_pavucontrol and easyeffects: the mixer and the effects bypass, independent of any desktop shell (Super+Shift+E calls easyeffects)_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `pavucontrol` | `pavucontrol` | variables.lua audioSettings, the mixer bind; Prefs > SYSTEM checks it | the mixer bind does nothing |
| `easyeffects` | `easyeffects` | keybind Super+Shift+E, effects bypass toggle | that bind does nothing |

## Applications (`apps`)

_Apps named by the shell's defaults (variables.lua) and checked by Prefs > SYSTEM_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `dolphin` | `dolphin` | variables.lua fileExplorer; Prefs > SYSTEM checks it | the file-explorer bind does nothing (yazi can replace it) |
| `vscodium` | `codium` | variables.lua apps.editor (Super+Shift+K); Prefs > SYSTEM checks it | the editor bind does nothing |

## ThinkPad (`thinkpad` · optional)

_Fan curve and chassis LEDs. The shell pkexecs /usr/local/bin/reddot-thinkpad, which rewrites /etc/thinkfan.yaml and restarts thinkfan, it never touches the fan directly_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `tlp` | `tlp` | prefs/pages/BatteryPage.qml: pkexec tlp setcharge <start> <end> BAT0; services/EdgeService.qml: pkexec tlp fullcharge | charge thresholds page and the bar's fullcharge action |
| `thinkfan` (aur) | `thinkfan` | owns /proc/acpi/ibm/fan; /usr/local/bin/reddot-thinkpad rewrites /etc/thinkfan.yaml and restarts the service | fan curve page cannot apply; LEDs still work, _AUR: not in the official repos_ |

## yazi extras (`yazi-extras` · optional)

_Optional binaries behind yazi features: mount plugin (udisksctl), EXIF reveal opener (exiftool)_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `udisks2` | `udisksctl` | yazi mount plugin (key M), Dolphin removable media | the mount manager lists nothing |
| `perl-image-exiftool` | `exiftool` | yazi `reveal` opener, EXIF entry | the EXIF action prints nothing |

## Update probe (`updates` · optional)

_The bar's update widget shells out to package-updates.sh, which probes pacman-flavoured sources. checkupdates avoids a root refresh; without it the script falls back to fakeroot_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `pacman-contrib` | `checkupdates` | glyph/system/package-updates.sh, official-repo branch | falls back to a fakeroot pacman -Sy, slower, still works |

## Location (`geo` · optional)

_execs.lua starts the geoclue demo agent for the weather panel. Absent, the panel just has no location_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `geoclue` | `/usr/lib/geoclue-2.0/demos/agent` | execs.lua starts the agent; services/Weather.qml reads its location | weather falls back to ipinfo.io |

## Qt theming (AUR) (`aur-theming`)

_Qt platform theme engine + the Darkly style: Prefs and Qt apps follow the palette through these_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `qtengine` (aur) | `qtengine` | Qt platform theme; reads ~/.config/qtengine.colors (generated by Apply.apps()) | Qt apps ignore the palette |
| `darkly-bin` (aur) | `Darkly` | the Qt style qtengine drives | Qt apps fall back to Fusion |

## Cursor (AUR) (`aur-cursor` · optional)

_Bibata cursor, referenced by the GTK/Hyprland cursor setting_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `bibata-cursor-theme-bin` (aur) | `Bibata` | variables.lua cursorTheme; execs.lua does hyprctl setcursor + gsettings | stock cursor |

## Flatpak (`flatpak-apps` · optional)

_Zen is a Flatpak here; variables.lua launches it with `flatpak run`. Prefs > SYSTEM reports it as missing otherwise_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `app.zen_browser.zen` (flatpak) | `app.zen_browser.zen` | variables.lua browser = flatpak run app.zen_browser.zen | the browser bind does nothing, _manifest key is the flatpak app id, not a package_ |

## Greeter (`greeter` · optional)

_SDDM + the Glyph greeter theme. Not used on the dev machine (it boots Hyprland directly), so it stays optional; install.sh --sddm copies the theme_

| package | binary | called by | if absent |
| --- | --- | --- | --- |
| `sddm` | `sddm` | install.sh --sddm copies config/sddm/glyph and writes zz-glyph.conf | no graphical login; this machine boots Hyprland directly |

## Integrations that are not packages

Called by the desktop but shipped by a package that is already part of the
base system, or not shipped at all. These are the ones that break silently.

| integration | provided by | called by | if absent |
| --- | --- | --- | --- |
| `/usr/local/bin/reddot-thinkpad` | this repo installs it | services/ThinkPad.qml via `pkexec` | fan curve and LED page cannot run, reddoted's own installer never puts it there |
| `pkill` | procps-ng (base) | settings/Rules.qml restarts hypridle | idle timings never reload |
| `busctl`, `loginctl` | systemd (base) | power menu (`CanSuspendThenHibernate`), hypridle `lock-session` | the suspend-then-hibernate entry disappears |
| `localectl` | systemd (base) | Prefs → INPUT lists layouts and options | keyboard layout picker is empty |
| `udevadm` | systemd (base) | services/Backlight.qml monitors hotplug | brightness OSD stops reacting to new devices |
| `gsettings` | glib2 (base) | install.sh (dark scheme), execs.lua (cursor theme) | GTK apps stay light; cursor theme not applied |
| `fc-cache` | fontconfig (base) | install.sh after linking the bundled fonts | the Glyph typefaces are not picked up until the next cache rebuild |
| `xdg-mime`, `update-desktop-database` | xdg-utils / desktop-file-utils | install.sh wiring step | yazi is not registered for `inode/directory` |
| `chsh` | shadow (base) | install.sh wiring, asks before changing the login shell | fish stays a manual choice |
| `hyprctl` | hyprland | 27 files, see the `hyprland` row above | duplicated here because it is called far more than anything else |

85 of 85 package requirements documented.
