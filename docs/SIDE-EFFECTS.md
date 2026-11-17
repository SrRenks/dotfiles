# Side effects: everything that writes outside the shell

`Apply.qml` is the one everybody notices, because it repaints the desktop. It is
not the only writer, it is not even the biggest one. This is the complete list
of places where reddoted changes something that outlives the process, ordered by
how much privilege the change needs.

Three tiers:

1. **files under `$HOME`**, no privilege, reversible by deleting a file
2. **live session state**, `hyprctl`, `gsettings`, service restarts
3. **privileged**, `pkexec`, and one root-owned helper binary

## Tier 1, files under `$HOME`

| Writer | Writes | Notes |
| --- | --- | --- |
| `Apply.apply()` | `~/.config/demonshot/ghostty-colors` | the terminal palette; Ghostty includes it with `config-file = ?…` |
| `Apply.apps()` | `~/.local/state/rice/glyph/{gtk-3.0/gtk.css, gtk-4.0/gtk.css, qtengine.colors}` | generated from the `term/` templates by `sed`, then the `~/.config/…` symlinks are repointed at the generated copies |
| `Rules.qml` | `~/.config/demonshot/rules.json` | the whole Prefs store |
| `Rules.idle()` | `~/.config/demonshot/hypridle.conf` | then **restarts hypridle**: `pkill -x hypridle; exec hypridle -c $f` |
| `Startup.qml` | `~/.config/demonshot/startup.json` | read back at login by `startup-run.sh` |
| `Shortcuts.qml` | `~/.config/demonshot/shortcuts.json` | applied by `shortcuts-apply.sh` |
| `Updates` service | `~/.config/demonshot/updates.json` | last probe result |
| `rec-toggle.sh` | `$XDG_STATE_HOME/rice/glyph.json` | recording state, next to the shell-flag file |
| `shot-quick.sh` | `$(xdg-user-dir PICTURES)/shots/*.png` | screenshots land in a real directory |
| `Launcher.qml` | command usage file | frecency for the `›` launcher |
| `Clip.qml` | `cliphist` database | clipboard history |
| `glyph-process` | `$XDG_RUNTIME_DIR/glyph-process/*` | per-pid metadata for the process panel (nice/kill) |
| `AiPage` | **secret service** via `secret-tool store/clear` | keys go to gnome-keyring, never to a dotfile |

`~/.local/state/rice/shell` is written by the installer, not the shell: it is how
`rice` knows which shell to start.

## Tier 2, live session state

| Writer | Mechanism | Result |
| --- | --- | --- |
| `Apply.apply()` | `hyprctl eval` | gaps, border colours, rounding, opacity, blur, shadow, group bar, background |
| `kbd-apply.sh` | `hyprctl eval` + `hyprctl switchxkblayout` | keyboard layout/variant/options at runtime |
| `toggle-inactive-exempt.sh` | `hyprctl getoption` + config | per-window opacity exemption |
| `minimize-toggle.sh`, `special-toggle.sh` | `hyprctl` + `jq` | window moves between workspaces |
| `MuteLeds`, `ThinkPadLedGuard` | `brightnessctl` | LEDs on the chassis |
| `EdgeService` | `pkexec tlp …` (see tier 3) | charge thresholds |
| `startup-run.sh` | `jq` + `glyph-process` | launches autostart entries |
| `shortcuts-apply.sh` | `jq` + `hyprctl` | re-binds custom chords |

## Tier 3, privileged

This is the part that quietly needs root, and the part most likely to break.

| Writer | Command | Touches | Needs |
| --- | --- | --- | --- |
| `PowerPage` | `pkexec sh -c "printf '%s' <choice> > /sys/firmware/acpi/platform_profile"` | ACPI platform profile (quiet / balanced / performance) | `polkit` + `pkexec`; profile support in the kernel |
| `BatteryPage` | `pkexec tlp setcharge <start> <end> BAT0` | charge start/end thresholds | **`tlp`** |
| `EdgeService` | `pkexec tlp fullcharge` / `setcharge` | same, from the bar | `tlp` |
| `ThinkPad` service | `pkexec /usr/local/bin/reddot-thinkpad …` | `/etc/thinkfan.yaml` (backup `.glyph.bak`), **restarts `thinkfan`**, `/sys/class/leds`, reads `/proc/acpi/ibm/fan` | **`thinkfan`** (AUR) + the helper installed as root |

The helper is the subtle one. `config/hypr/scripts/glyph-thinkpad` in the repo is
the source; the shell never calls that copy, it calls **`/usr/local/bin/reddot-thinkpad`**,
deliberately:

```qml
// Use the installed, root-owned helper: a user-writable script must never
// [be executed as root]
readonly property string helper: "/usr/local/bin/reddot-thinkpad"
```

And that helper deliberately does **not** drive the fan:

```
# Fan control is deliberately absent: thinkfan owns /proc/acpi/ibm/fan on the
```

It owns `/etc/thinkfan.yaml` instead, it rewrites the curve and restarts the
daemon. So the ThinkPad feature is: **`tlp` for the battery, `thinkfan` for the
fan, the helper for the left-hand side.**

## What a fresh install gets wrong

Found while mapping the above, these are gaps, not bugs in the shell:

1. **`/usr/local/bin/reddot-thinkpad` is never installed.** `reddoted/install.sh`
   has no reference to it at all. On a clean machine the fan curve page opens and
   every action fails with "file not found". This repo now installs it when the
   reddoted profile is selected.
2. **`libsecret` (`secret-tool`) is not in any manifest.** The AI panel stores and
   reads keys through it; without it, saving a key silently does nothing.
3. **`thinkfan` is not in the official repos** (`pacman -Si thinkfan` → not found)
   but is installed here, it came from the AUR. It must be listed as AUR, or the
   fan page cannot work on a fresh machine.
4. **`matugen` is installed and unused**, dead AUR dependency.

## The dependency list this implies

| Package | Why | Group |
| --- | --- | --- |
| `tlp` | charge thresholds via `tlp setcharge` | `power` |
| `libsecret` | `secret-tool` for the AI keys | `session` |
| `thinkfan` (**AUR**) | owns the fan; the helper writes its config | `thinkpad` |
| `polkit-gnome` | the `pkexec` prompt | `session` |
| `xdg-user-dirs` | `xdg-user-dir PICTURES` for screenshots | `session` |
| `jq` | every script that reads a JSON state file | `base` |

Everything else above is already covered by the desktop groups.
