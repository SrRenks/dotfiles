#!/usr/bin/env python3
"""Audit this machine against deps/deps.toml.

    python3 deps/check.py            # full report
    python3 deps/check.py --quiet    # only problems; exit code says how many

Exit code: 0 everything required is present, 1 otherwise.

Uses `pacman -T`, not `pacman -Q`: -T resolves provides (codium <- vscodium),
so the manifest does not have to know which package actually ships a binary.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "deps.toml"

# The installer records what you chose, so the audit reports on *your* machine
# and not on a manifest you deliberately only half-installed.
SELECTION = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "dotfiles" / "groups"

OK, MISS, OPT, UNKNOWN = "ok", "MISSING", "optional", "unverifiable"


def run(cmd: list[str]) -> int:
    return subprocess.run(cmd, capture_output=True, text=True).returncode


def pkg(manager: str, name: str) -> bool:
    """Is this package requirement satisfied?"""
    if manager == "pacman":
        return run(["pacman", "-T", name]) == 0
    if manager == "aur":
        return run(["pacman", "-Q", name]) == 0
    if manager == "flatpak":
        return run(["flatpak", "info", name]) == 0
    return False


def binary(name: str) -> bool:
    return shutil.which(name) is not None


def service(system: bool, name: str) -> bool | None:
    """True/False, or None when the bus cannot be reached (containers, sandboxes)."""
    scope = [] if system else ["--user"]
    r = subprocess.run(["systemctl", *scope, "is-enabled", name], capture_output=True, text=True)
    if r.returncode == 0:
        return True
    if "Failed to connect" in r.stderr or "No data available" in r.stderr:
        return None
    return False


def in_group(name: str) -> bool:
    """Membership from the group database, not from the current process (which a
    sandbox may strip). Falls back to the primary gid."""
    r = subprocess.run(["getent", "group", name], capture_output=True, text=True)
    if r.returncode != 0:
        return False
    fields = r.stdout.strip().split(":")
    if len(fields) < 4:
        return False
    members = [m.strip() for m in fields[3].split(",") if m.strip()]
    user = subprocess.run(["id", "-un"], capture_output=True, text=True).stdout.strip()
    if user in members:
        return True
    return subprocess.run(["id", "-g"], capture_output=True, text=True).stdout.strip() == fields[2]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true", help="only report problems")
    ap.add_argument("--all", action="store_true",
                    help="audit the whole manifest, ignoring the saved selection")
    args = ap.parse_args()

    data = tomllib.loads(MANIFEST.read_text())
    groups = data.get("group", [])

    chosen: set[str] | None = None
    if not args.all and SELECTION.exists():
        chosen = {line.strip() for line in SELECTION.read_text().splitlines() if line.strip()}
        groups = [g for g in groups if g.get("id") in chosen]
    versions = data.get("versions", {})

    missing_required: list[tuple[str, str, str]] = []
    missing_optional: list[tuple[str, str, str]] = []
    present = 0

    def emit(group: dict, kind: str, name: str, state: str) -> None:
        nonlocal present
        gid = group["id"]
        opt = bool(group.get("optional", False))
        if state == UNKNOWN:
            if not args.quiet:
                print(f"  \033[90m?\033[0m {gid:<18} {kind:<8} {name}")
            return
        if state == OK:
            present += 1
            if not args.quiet:
                print(f"  \033[32m●\033[0m {gid:<18} {kind:<8} {name}")
            return
        if opt:
            missing_optional.append((gid, kind, name))
            if not args.quiet:
                print(f"  \033[90m○\033[0m {gid:<18} {kind:<8} {name}")
        else:
            missing_required.append((gid, kind, name))
            print(f"  \033[31m✕\033[0m {gid:<18} {kind:<8} {name}")

    if not args.quiet:
        scope = "whole manifest" if chosen is None else f"{len(groups)} selected groups"
        print(f"\n\033[1mmanifest\033[0m  {MANIFEST}  ({scope})\n")

    for group in groups:
        for kind, manager in (("pacman", "pacman"), ("aur", "aur"), ("flatpak", "flatpak")):
            for name in group.get(kind, []):
                emit(group, kind, name, OK if pkg(manager, name) else MISS)

        for b in group.get("provides", {}):
            emit(group, "binary", b, OK if binary(b) else MISS)

        for s in group.get("services_system", []):
            st = service(True, s)
            emit(group, "service", s, UNKNOWN if st is None else (OK if st else MISS))
        for s in group.get("services_user", []):
            st = service(False, s)
            emit(group, "service", s, UNKNOWN if st is None else (OK if st else MISS))

        for g in group.get("groups", []):
            emit(group, "group", g, OK if in_group(g) else MISS)

    if not args.quiet:
        print("\n\033[1mversion floors\033[0m (what the configs were validated against)\n")
        for name, floor in versions.items():
            have = subprocess.run(
                ["pacman", "-Q", name] if name != "quickshell" else ["pacman", "-Q", "quickshell"],
                capture_output=True,
                text=True,
            )
            ver = have.stdout.split()[-1].split("-")[0] if have.returncode == 0 else "absent"
            print(f"  {name:<12} floor {floor:<8} here {ver}")

    print()
    if missing_required:
        print(f"\033[1m{len(missing_required)} required requirement(s) missing\033[0m")
        for gid, kind, name in missing_required:
            print(f"  - {name} ({kind}, {gid})")
    else:
        print("\033[32mevery required requirement is present\033[0m")
    if missing_optional:
        print(f"{len(missing_optional)} optional missing (feature degrades, nothing breaks):")
        print("  " + ", ".join(n for _, _, n in missing_optional))
    print(f"{present} satisfied")

    return 1 if missing_required else 0


if __name__ == "__main__":
    sys.exit(main())
