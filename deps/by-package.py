#!/usr/bin/env python3
"""Render docs/BY-PACKAGE.md from deps.toml + deps/usage.toml.

    python3 deps/by-package.py            # write the document
    python3 deps/by-package.py --check    # exit 1 if a package has no usage entry

The two files cannot drift: every package in the manifest is looked up in the
usage evidence, and anything undocumented fails --check instead of quietly
rendering a row that says nothing.
"""

from __future__ import annotations

import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parent / "docs" / "BY-PACKAGE.md"

GROUP_TITLES = {
    "base": "Base",
    "graphics": "Graphics",
    "session": "Session and shell plumbing",
    "audio": "Audio",
    "network": "Network and Bluetooth",
    "power": "Power",
    "shell-core": "Shell core",
    "shell-extras": "Shell extras",
    "input": "Synthetic input",
    "terminal": "Terminal",
    "terminal-tools": "Terminal tools",
    "fonts": "Fonts",
    "icons": "Icons and GTK",
    "audio-tools": "Audio applications",
    "apps": "Applications",
    "yazi-extras": "yazi extras",
    "updates": "Update probe",
    "geo": "Location",
    "aur-theming": "Qt theming (AUR)",
    "aur-cursor": "Cursor (AUR)",
    "flatpak-apps": "Flatpak",
    "greeter": "Greeter",
    "thinkpad": "ThinkPad",
}


# Integration points that no package list owns. Kept here so the per-package view
# is complete: everything the desktop calls is either a package above or a row here.
NOT_PACKAGES = [
    ("`/usr/local/bin/reddot-thinkpad`", "this repo installs it", "services/ThinkPad.qml via `pkexec`",
     "fan curve and LED page cannot run, reddoted's own installer never puts it there"),
    ("`pkill`", "procps-ng (base)", "settings/Rules.qml restarts hypridle",
     "idle timings never reload"),
    ("`busctl`, `loginctl`", "systemd (base)", "power menu (`CanSuspendThenHibernate`), hypridle `lock-session`",
     "the suspend-then-hibernate entry disappears"),
    ("`localectl`", "systemd (base)", "Prefs → INPUT lists layouts and options",
     "keyboard layout picker is empty"),
    ("`udevadm`", "systemd (base)", "services/Backlight.qml monitors hotplug",
     "brightness OSD stops reacting to new devices"),
    ("`gsettings`", "glib2 (base)", "install.sh (dark scheme), execs.lua (cursor theme)",
     "GTK apps stay light; cursor theme not applied"),
    ("`fc-cache`", "fontconfig (base)", "install.sh after linking the bundled fonts",
     "the Glyph typefaces are not picked up until the next cache rebuild"),
    ("`xdg-mime`, `update-desktop-database`", "xdg-utils / desktop-file-utils", "install.sh wiring step",
     "yazi is not registered for `inode/directory`"),
    ("`chsh`", "shadow (base)", "install.sh wiring, asks before changing the login shell",
     "fish stays a manual choice"),
    ("`hyprctl`", "hyprland", "27 files, see the `hyprland` row above",
     "duplicated here because it is called far more than anything else"),
]


def load(name: str) -> dict:
    path = ROOT / name
    try:
        return tomllib.loads(path.read_text())
    except tomllib.TOMLDecodeError as exc:
        sys.exit(f"by-package: {path.name}: {exc}")


def render() -> tuple[str, list[str]]:
    deps = load("deps.toml")
    usage = load("usage.toml").get("uses", {})

    lines: list[str] = []
    missing: list[str] = []
    documented = 0
    total = 0

    lines.append("# Dependencies, package by package")
    lines.append("")
    lines.append(
        "Generated from [`deps/deps.toml`](../deps/deps.toml) (what is installed) and\n"
        "[`deps/usage.toml`](../deps/usage.toml) (who calls it). Regenerate with\n"
        "`python3 deps/by-package.py`; it fails if a package has no evidence."
    )
    lines.append("")
    lines.append("| Column | means |")
    lines.append("| --- | --- |")
    lines.append("| binary | what actually lands in `$PATH` (or the library / font name) |")
    lines.append("| called by | the file that calls it, not the feature it resembles |")
    lines.append("| if absent | what stops working, and whether it fails loudly or silently |")
    lines.append("")

    for group in deps.get("group", []):
        gid = group.get("id", "")
        packages: list[tuple[str, str]] = []
        for kind in ("pacman", "aur", "flatpak"):
            for pkg in group.get(kind, []):
                packages.append((pkg, kind))
        if not packages:
            continue

        title = GROUP_TITLES.get(gid, gid)
        opt = " · optional" if group.get("optional") else ""
        lines.append(f"## {title} (`{gid}`{opt})")
        lines.append("")
        if group.get("desc"):
            lines.append(f"_{group['desc']}_")
            lines.append("")
        lines.append("| package | binary | called by | if absent |")
        lines.append("| --- | --- | --- | --- |")

        for pkg, kind in packages:
            total += 1
            entry = usage.get(pkg) or usage.get(gid)
            if entry is None:
                missing.append(f"{pkg} ({kind}, {gid})")
                lines.append(f"| `{pkg}`{'' if kind == 'pacman' else f' ({kind})'} | ? | ? | ? |")
                continue
            documented += 1
            bin_ = entry.get("bin", "?")
            where = entry.get("where", "?")
            breaks = entry.get("breaks", "?")
            note = entry.get("note")
            if note:
                breaks = f"{breaks}, _{note}_"
            label = f"`{pkg}`" if kind == "pacman" else f"`{pkg}` ({kind})"
            lines.append(f"| {label} | `{bin_}` | {where} | {breaks} |")

        lines.append("")

    lines.append("## Integrations that are not packages")
    lines.append("")
    lines.append(
        "Called by the desktop but shipped by a package that is already part of the\n"
        "base system, or not shipped at all. These are the ones that break silently."
    )
    lines.append("")
    lines.append("| integration | provided by | called by | if absent |")
    lines.append("| --- | --- | --- | --- |")
    for row in NOT_PACKAGES:
        lines.append("| " + " | ".join(row) + " |")
    lines.append("")
    lines.append(f"{documented} of {total} package requirements documented.")
    if missing:
        lines.append("")
        lines.append("**Undocumented:** " + ", ".join(f"`{m}`" for m in missing))
    lines.append("")

    return "\n".join(lines), missing


def main() -> int:
    check = "--check" in sys.argv[1:]
    doc, missing = render()

    if check:
        if missing:
            print("by-package: no usage evidence for:")
            for m in missing:
                print(f"  - {m}")
            return 1
        print("by-package: every package has usage evidence")
        return 0

    OUT.write_text(doc)
    total = doc.count("| `")
    print(f"by-package: wrote {OUT.relative_to(ROOT.parent)} ({total} package rows)")
    if missing:
        print("by-package: undocumented: " + ", ".join(missing))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
