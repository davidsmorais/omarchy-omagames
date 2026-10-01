#!/usr/bin/env python3
"""Scan installed Omarchy plugins and print the ones that look like games.

A plugin counts as a game when any of these hold:
  - barWidget.category is Games / Game / Fun / Arcade / Play
  - top-level tags contain game / games / gaming / arcade / fun / play
  - barWidget.aliases contain game / games / arcade
  - its ID is passed in --extra (always include)

Usage:
  scan-games.py '{"extra": ["some.id"], "hidden": ["other.id"]}'

Output is a single JSON line: {"games": [{id, name, description, category,
kinds, hasPanel, hasBarWidget, enabled}], "enabledKnown": bool} sorted with
enabled games first, then by name. enabledKnown is false when
`omarchy plugin list` failed (callers should then keep previous states).

Enabled state comes from `omarchy plugin list --json`; if that call fails
every plugin is assumed enabled. Note that for bar-widget plugins the
shell defines enabled as "in the bar", so enabled/disabled and
shown-in-top-bar/hidden are the same thing.
"""

import glob
import json
import os
import subprocess
import sys

GAME_CATEGORIES = {"game", "games", "fun", "arcade", "play"}
GAME_TAGS = {"game", "games", "gaming", "arcade", "fun", "play"}
GAME_ALIASES = {"game", "games", "arcade"}

SELF_ID = "david.omagames"


def load_options():
    if len(sys.argv) > 1:
        try:
            opts = json.loads(sys.argv[1])
            if isinstance(opts, dict):
                return opts
        except (ValueError, TypeError):
            pass
    return {}


def load_enabled():
    """Map plugin ID -> enabled bool. Empty map = assume enabled."""
    try:
        proc = subprocess.run(
            ["omarchy", "plugin", "list", "--json"],
            capture_output=True,
            text=True,
            timeout=15,
        )
        if proc.returncode != 0:
            return {}
        return {
            str(p.get("id", "")): bool(p.get("enabled", True))
            for p in json.loads(proc.stdout)
            if isinstance(p, dict)
        }
    except Exception:
        return {}


def is_game(manifest, plugin_id, extra):
    if plugin_id in extra:
        return True
    bar_widget = manifest.get("barWidget") or {}
    category = str(bar_widget.get("category") or "").strip().lower()
    if category in GAME_CATEGORIES:
        return True
    tags = manifest.get("tags") or []
    if any(str(t).strip().lower() in GAME_TAGS for t in tags):
        return True
    aliases = bar_widget.get("aliases") or []
    if any(str(a).strip().lower() in GAME_ALIASES for a in aliases):
        return True
    return False


def main():
    opts = load_options()
    extra = set(str(i).strip() for i in (opts.get("extra") or []) if str(i).strip())
    hidden = set(str(i).strip() for i in (opts.get("hidden") or []) if str(i).strip())

    plugins_dir = os.path.expanduser("~/.config/omarchy/plugins")
    enabled = load_enabled()
    enabled_known = bool(enabled)

    games = []
    for path in sorted(glob.glob(os.path.join(plugins_dir, "*", "manifest.json"))):
        try:
            with open(path, encoding="utf-8") as handle:
                manifest = json.load(handle)
        except (OSError, ValueError):
            continue
        if not isinstance(manifest, dict):
            continue
        plugin_id = str(
            manifest.get("id") or os.path.basename(os.path.dirname(path))
        )
        if plugin_id == SELF_ID or plugin_id in hidden:
            continue
        if not is_game(manifest, plugin_id, extra):
            continue
        bar_widget = manifest.get("barWidget") or {}
        kinds = manifest.get("kinds") or []
        games.append(
            {
                "id": plugin_id,
                "name": bar_widget.get("displayName")
                or manifest.get("name")
                or plugin_id,
                "description": bar_widget.get("description")
                or manifest.get("description")
                or "",
                "category": bar_widget.get("category") or "",
                "kinds": kinds,
                "hasPanel": any(k in ("panel", "menu", "overlay") for k in kinds),
                "hasBarWidget": "bar-widget" in kinds,
                "enabled": enabled.get(plugin_id, True),
            }
        )

    games.sort(key=lambda g: (not g["enabled"], str(g["name"]).lower()))
    print(json.dumps({"games": games, "enabledKnown": enabled_known}))


if __name__ == "__main__":
    main()
