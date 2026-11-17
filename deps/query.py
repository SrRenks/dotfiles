#!/usr/bin/env python3
"""Read the manifests and answer questions in a shape bash can consume.

    query.py pacman            required pacman packages, group order, deduped
    query.py pacman-optional   optional pacman packages
    query.py aur               required AUR packages
    query.py aur-optional
    query.py flatpak           optional flatpak app ids
    query.py conflicts         "a|b" pairs that must not coexist
    query.py services-system   system services to enable
    query.py services-user     user services to enable
    query.py groups            supplementary groups to join
    query.py gaps              packages reddoted forgets, one per line
    query.py reddoted-url      from deps/reddoted.lock
    query.py reddoted-path     expanded with $HOME
    query.py reddoted-rev
    query.py versions          "name floor" lines

Exit 1 with a message on stderr if the manifest is malformed, so the installer
fails before it touches the system.
"""

from __future__ import annotations

import os
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def load(name: str) -> dict:
    path = ROOT / name
    if not path.exists():
        sys.exit(f"query: missing {path}")
    try:
        return tomllib.loads(path.read_text())
    except tomllib.TOMLDecodeError as exc:
        sys.exit(f"query: {path.name} is not valid TOML: {exc}")


def emit(items: list[str]) -> None:
    """Print one item per line; nothing at all when the list is empty. A bare
    print("") would hand bash a one-element array holding an empty string."""
    if items:
        print("\n".join(items))


def collect(groups: list[dict], key: str, optional: bool | None = None,
            only: set[str] | None = None) -> list[str]:
    out: list[str] = []
    for group in groups:
        if optional is not None and bool(group.get("optional", False)) != optional:
            continue
        if only is not None and group.get("id") not in only:
            continue
        for item in group.get(key, []):
            if item not in out:
                out.append(item)
    return out


def main() -> int:
    args = [a for a in sys.argv[1:]]
    only: set[str] | None = None
    units: set[str] | None = None
    if "--groups" in args:
        i = args.index("--groups")
        only = {g for g in args[i + 1].split(",") if g} if i + 1 < len(args) else set()
        del args[i:i + 2]
    with_optional = False
    if "--with-optional" in args:
        with_optional = True
        args.remove("--with-optional")
    if "--units" in args:
        i = args.index("--units")
        units = {u for u in args[i + 1].split(",") if u} if i + 1 < len(args) else set()
        del args[i:i + 2]
    if len(args) != 1:
        sys.exit(__doc__)

    what = args[0]
    deps = load("deps.toml")
    groups = deps.get("group", [])
    # When a selection is given, it *is* the filter: `optional` must not remove a
    # group the user just ticked in the menu. Without --groups the manifest-wide
    # default applies (required groups only).
    opt = False if only is None else None

    match what:
        case "pacman":
            emit(collect(groups, "pacman", optional=opt, only=only))
        case "pacman-optional":
            emit(collect(groups, "pacman", optional=True, only=only))
        case "aur":
            emit(collect(groups, "aur", optional=opt, only=only))
        case "aur-optional":
            emit(collect(groups, "aur", optional=True, only=only))
        case "flatpak":
            emit(collect(groups, "flatpak", only=only))
        case "conflicts":
            for pair in deps.get("conflict", []):
                print("|".join(pair.get("packages", [])))
        case "services-system":
            emit(collect(groups, "services_system", only=only))
        case "services-user":
            emit(collect(groups, "services_user", only=only))
        case "groups":
            emit(collect(groups, "groups", only=only))
        case "gaps":
            for gap in deps.get("gap", []):
                for pkg in gap.get("packages", []):
                    print(pkg)
        case "unit-ids":
            for uid in load("units.toml").get("unit", {}):
                print(uid)
        case "checklist":
            # The whole selection UI, one row per line, in the manifest's order:
            # type|id|label|desc|sets. Bash only has to draw it.
            deps = load("deps.toml")
            units = load("units.toml").get("unit", {})
            uses = load("usage.toml").get("uses", {})
            groups = deps.get("group", [])
            by_id = {g.get("id"): g for g in groups}
            def pkg_ids(g):
                return ",".join(g.get("pacman", []) + g.get("aur", []))
            def short(pid):
                u = uses.get(pid, {})
                w = u.get("where", "")
                return (w[:46] + "…") if len(w) > 47 else w
            # presets are built from the units, not from "every group there is":
            # an optional group is not part of the default desktop
            def unit_pkgs(uid, seen=None):
                u = units.get(uid, {})
                out = []
                for gid in u.get("groups", []):
                    out += by_id.get(gid, {}).get("pacman", [])
                    out += by_id.get(gid, {}).get("aur", [])
                return out
            def dedupe(seq):
                seen = set()
                out = []
                for x in seq:
                    if x and x not in seen:
                        seen.add(x)
                        out.append(x)
                return out
            # a package whose name is also a unit name (fish, tmux, yazi...) would
            # be read as that unit; reddoted owns those configs, so keep them out
            # of the desktop preset and let the unit rows stand on their own
            desktop = dedupe(["unit:reddoted", "unit:core"] + unit_pkgs("reddoted") + unit_pkgs("core"))
            hub = dedupe(["unit:" + u for u in units if u not in ("reddoted", "personal")])
            print("head||presets|")
            print(f"preset|preset:desktop|desktop|reddoted e o que ele precisa|{','.join(desktop)}")
            print(f"preset|preset:terminal|terminal|o hub sozinho, sem Hyprland|{','.join(hub)}")
            for g in groups:
                gid = g.get("id")
                pkgs = g.get("pacman", []) + g.get("aur", [])
                if not pkgs:
                    continue
                label = gid + (" (AUR)" if g.get("aur") else "")
                print(f"head|grp:{gid}|{label}||{pkg_ids(g)}")
                for pid in pkgs:
                    print(f"pkg|{pid}|{pid}|{short(pid)}|")
            print("head||configs|")
            for uid, unit in units.items():
                if uid == "reddoted":
                    continue
                desc = unit.get("desc", "")
                desc = desc[:46] + "…" if len(desc) > 47 else desc
                print(f"unit|unit:{uid}|{uid}|{desc}|")
            gaps = deps.get("gaps", [])
            if gaps:
                print("head|grp:gaps|o que o reddoted esquece||" + ",".join(gaps))
                for pid in gaps:
                    print(f"pkg|{pid}|{pid}|{short(pid)}|")
            print("action||iniciar||")
        case "classify":
            # id|kind, so the installer knows whether an id is a package, a stow
            # unit, or the reddoted action
            deps = load("deps.toml")
            for g in deps.get("group", []):
                for pid in g.get("pacman", []) + g.get("aur", []):
                    print(f"{pid}|pkg|{g.get('id')}")
            for pid in deps.get("gaps", []):
                print(f"{pid}|pkg|gaps")
            for g in deps.get("group", []):
                if g.get("pacman") or g.get("aur"):
                    print(f"{g.get('id')}|group|{g.get('id')}")
            for uid in load("units.toml").get("unit", {}):
                print(f"unit:{uid}|unit|{uid}")
        case "packages":
            # group|package|kind, in manifest order: the checklist reads this
            for group in load("deps.toml").get("group", []):
                gid = group.get("id")
                for pkg in group.get("pacman", []):
                    print(f"{gid}|{pkg}|pacman")
                for pkg in group.get("aur", []):
                    print(f"{gid}|{pkg}|aur")
                for pkg in group.get("flatpak", []):
                    print(f"{gid}|{pkg}|flatpak")
        case "group-services":
            # group|unit|scope, so services are enabled for the groups that kept
            # at least one package
            for group in load("deps.toml").get("group", []):
                gid = group.get("id")
                for unit in group.get("services_system", []):
                    print(f"{gid}|{unit}|system")
                for unit in group.get("services_user", []):
                    print(f"{gid}|{unit}|user")
        case "unit-always":
            for uid, unit in load("units.toml").get("unit", {}).items():
                if unit.get("always"):
                    print(uid)
        case "unit-desc":
            for uid, unit in load("units.toml").get("unit", {}).items():
                print(f"{uid}|{unit.get('desc', '')}|{unit.get('manual', '')}")
        case "unit-groups":
            table = load("units.toml").get("unit", {})
            out: list[str] = []
            for uid in (units or table.keys()):
                unit = table.get(uid, {})
                for gid in unit.get("groups", []):
                    if gid not in out:
                        out.append(gid)
                if with_optional:
                    for gid in unit.get("optional_groups", []):
                        if gid not in out:
                            out.append(gid)
            emit(out)
        case "unit-packages":
            table = load("units.toml").get("unit", {})
            seen: list[str] = []
            for uid in (units or table.keys()):
                for pkg in table.get(uid, {}).get("packages", []):
                    if pkg not in seen:
                        seen.append(pkg)
            emit(seen)
        case "unit-reddoted-only":
            table = load("units.toml").get("unit", {})
            for uid in (units or table.keys()):
                if table.get(uid, {}).get("requires_reddoted"):
                    print(uid)
        case "ids":
            for group in groups:
                print(group.get("id", ""))
        case "versions":
            for name, floor in deps.get("versions", {}).items():
                print(f"{name} {floor}")
        case "reddoted-url" | "reddoted-path" | "reddoted-rev" | "reddoted-branch":
            lock = load("reddoted.lock").get("reddoted", {})
            key = what.split("-", 1)[1]
            value = str(lock.get(key, ""))
            print(os.path.expanduser(value))
        case _:
            sys.exit(f"query: unknown query {what!r}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
