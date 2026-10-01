#!/usr/bin/env python3
"""Hide/show a game's bar icon while keeping it launchable from OmaGames.

Why this exists: in omarchy-shell, a bar-widget plugin's "enabled" state
*is* its bar placement (see PluginRegistry.qml -- `enabled: inBar(id)` for
anything with kind "bar-widget"). Calling `omarchy plugin disable <id>`
therefore also makes the plugin un-summonable, which breaks "hide the icon
but still let me launch it from the OmaGames panel".

The shell's panel loader (computePanelEntries) takes a different, wider view
of "enabled": a plugin counts if it's found in bar.layout *or* in the
top-level `plugins[]` array. So keeping the id in `plugins[]` while
`omarchy plugin disable` strips only the bar.layout entry (it matches "bar"
before it ever looks at `plugins[]`) leaves the game hidden but still
loadable/toggleable. Showing it again means reversing that: remove the
`plugins[]` entry first (otherwise `omarchy plugin enable` sees the id as
already "found" and skips re-inserting a bar entry), then enable normally.

This script only ever touches shell.json's `plugins[]` array and the one
bar.layout entry matching the given id; it shells out to `omarchy plugin
enable/disable` for everything else so the well-tested placement/clone
logic in the CLI stays the single source of truth for bar mechanics.

Usage:
  bar-visibility.py '{"id": "some.plugin", "action": "hide"}'
  bar-visibility.py '{"id": "some.plugin", "action": "show"}'

Prints one JSON line: {"ok": bool, "changed": bool, "error": str|None}.
"""

import json
import os
import re
import subprocess
import sys
import tempfile

SHELL_CONFIG = os.path.expanduser("~/.config/omarchy/shell.json")
SECTIONS = ("left", "center", "right")
VALID_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def emit(ok, changed=False, error=None):
    print(json.dumps({"ok": ok, "changed": changed, "error": error}))
    sys.exit(0 if ok else 1)


def load_options():
    if len(sys.argv) <= 1:
        emit(False, error="missing payload")
    try:
        opts = json.loads(sys.argv[1])
    except (ValueError, TypeError):
        emit(False, error="invalid JSON payload")
    if not isinstance(opts, dict):
        emit(False, error="payload must be a JSON object")
    return opts


def atomic_write(path, text):
    directory = os.path.dirname(path) or "."
    fd, tmp_path = tempfile.mkstemp(dir=directory, prefix=".shell.json.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def backup(path):
    if not os.path.exists(path):
        return
    try:
        with open(path, encoding="utf-8") as src:
            data = src.read()
        with open(path + ".omagames-bak", "w", encoding="utf-8") as dst:
            dst.write(data)
    except OSError:
        pass


def load_config():
    if not os.path.exists(SHELL_CONFIG):
        emit(False, error="shell.json not found at " + SHELL_CONFIG)
    try:
        with open(SHELL_CONFIG, encoding="utf-8") as handle:
            config = json.load(handle)
    except (OSError, ValueError) as exc:
        emit(False, error="could not read shell.json: " + str(exc))
    if not isinstance(config, dict):
        emit(False, error="shell.json is not a JSON object")
    return config


def find_bar_entry(config, plugin_id):
    layout = (config.get("bar") or {}).get("layout")
    if not isinstance(layout, dict):
        return None
    for section in SECTIONS:
        entries = layout.get(section)
        if not isinstance(entries, list):
            continue
        for i, entry in enumerate(entries):
            entry_id = entry.get("id") if isinstance(entry, dict) else entry
            if entry_id == plugin_id:
                return entries, i
    return None


def find_plugins_entry(config, plugin_id):
    plugins = config.get("plugins")
    if not isinstance(plugins, list):
        return None
    for i, entry in enumerate(plugins):
        entry_id = entry.get("id") if isinstance(entry, dict) else entry
        if entry_id == plugin_id:
            return plugins, i
    return None


def run_cli(*args):
    try:
        proc = subprocess.run(
            ["omarchy", "plugin", *args],
            capture_output=True, text=True, timeout=15,
        )
        return proc.returncode, (proc.stderr or proc.stdout or "").strip()
    except Exception as exc:
        return 1, str(exc)


def hide(plugin_id):
    config = load_config()
    location = find_bar_entry(config, plugin_id)
    already_kept = find_plugins_entry(config, plugin_id) is not None
    changed = False

    if not already_kept:
        extra = {}
        if location is not None:
            entries, index = location
            bar_entry = entries[index]
            if isinstance(bar_entry, dict):
                extra = {k: v for k, v in bar_entry.items() if k != "id"}
        plugins = config.get("plugins")
        if not isinstance(plugins, list):
            plugins = []
            config["plugins"] = plugins
        plugins.append({"id": plugin_id, **extra})
        backup(SHELL_CONFIG)
        atomic_write(SHELL_CONFIG, json.dumps(config, indent=2) + "\n")
        changed = True

    if location is None:
        # Already off the bar; the plugins[] safety net is all that was needed.
        emit(True, changed=changed)

    code, err = run_cli("disable", plugin_id)
    if code != 0:
        emit(False, changed=changed, error=err or "omarchy plugin disable failed")
    emit(True, changed=True)


def show(plugin_id):
    config = load_config()
    kept = find_plugins_entry(config, plugin_id)
    changed = False

    if kept is not None:
        plugins, index = kept
        plugins.pop(index)
        if not plugins:
            del config["plugins"]
        backup(SHELL_CONFIG)
        atomic_write(SHELL_CONFIG, json.dumps(config, indent=2) + "\n")
        changed = True

    code, err = run_cli("enable", plugin_id)
    if code != 0:
        emit(False, changed=changed, error=err or "omarchy plugin enable failed")
    emit(True, changed=True)


def main():
    opts = load_options()
    plugin_id = str(opts.get("id") or "").strip()
    action = str(opts.get("action") or "").strip()
    if not plugin_id or not VALID_ID.match(plugin_id):
        emit(False, error="invalid or missing plugin id")
    if action == "hide":
        hide(plugin_id)
    elif action == "show":
        show(plugin_id)
    else:
        emit(False, error="unsupported action: " + action)


if __name__ == "__main__":
    main()
