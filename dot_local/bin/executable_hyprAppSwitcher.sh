#!/usr/bin/env bash
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hypr-app-switcher"
ICON_CACHE="$CACHE_DIR/icons.tsv"
CACHE_TTL_SECONDS="${CACHE_TTL_SECONDS:-604800}" # 7 days

mkdir -p "$CACHE_DIR"

command -v hyprctl >/dev/null || exit 1
command -v fuzzel >/dev/null || exit 1
command -v python3 >/dev/null || exit 1

cache_expired() {
    [[ ! -s "$ICON_CACHE" ]] && return 0

    local now mtime age
    now="$(date +%s)"
    mtime="$(stat -c %Y "$ICON_CACHE" 2>/dev/null || echo 0)"
    age=$((now - mtime))

    (( age > CACHE_TTL_SECONDS ))
}

if [[ "${1:-}" == "--rebuild-cache" ]] || cache_expired; then
python3 - "$ICON_CACHE" <<'PY'
import configparser
import os
import re
import shlex
import sys
from pathlib import Path

out_path = Path(sys.argv[1])

def clean(value):
    return str(value or "").replace("\t", " ").replace("\n", " ").strip()

def norm(value):
    return re.sub(r"[^a-z0-9]+", "", str(value).lower())

def add(mapping, key, icon):
    key = clean(key)
    icon = clean(icon)

    if not key or not icon:
        return

    mapping.setdefault(norm(key), icon)

def parse_exec(exec_value):
    candidates = []

    try:
        parts = shlex.split(exec_value)
    except Exception:
        parts = exec_value.split()

    parts = [p for p in parts if not p.startswith("%")]

    if not parts:
        return candidates

    if parts[0] == "flatpak" and "run" in parts:
        run_i = parts.index("run")
        if run_i + 1 < len(parts):
            app_id = parts[run_i + 1]
            candidates.append(app_id)
            candidates.append(app_id.split(".")[-1])

    candidates.append(Path(parts[0]).name)
    return candidates

data_dirs = []

xdg_data_home = os.environ.get("XDG_DATA_HOME")
data_dirs.append(Path(xdg_data_home) if xdg_data_home else Path.home() / ".local/share")

xdg_data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
data_dirs.extend(Path(p) for p in xdg_data_dirs.split(":") if p)

data_dirs.extend([
    Path("/var/lib/flatpak/exports/share"),
    Path.home() / ".local/share/flatpak/exports/share",
])

app_dirs = []
seen_dirs = set()

for d in data_dirs:
    app_dir = d / "applications"
    key = str(app_dir)

    if app_dir.is_dir() and key not in seen_dirs:
        seen_dirs.add(key)
        app_dirs.append(app_dir)

icon_map = {}

for app_dir in app_dirs:
    for desktop_file in app_dir.rglob("*.desktop"):
        parser = configparser.ConfigParser(
            interpolation=None,
            strict=False,
            delimiters=("=",)
        )
        parser.optionxform = str

        try:
            parser.read(desktop_file, encoding="utf-8")
        except Exception:
            continue

        if "Desktop Entry" not in parser:
            continue

        sec = parser["Desktop Entry"]

        if sec.get("Hidden", "").lower() == "true":
            continue

        icon = sec.get("Icon", "")
        if not icon:
            continue

        stem = desktop_file.name.removesuffix(".desktop")

        candidates = [
            sec.get("StartupWMClass", ""),
            sec.get("X-GNOME-WMClass", ""),
            sec.get("Name", ""),
            sec.get("GenericName", ""),
            stem,
            stem.split(".")[-1],
        ]

        exec_value = sec.get("Exec", "")
        if exec_value:
            candidates.extend(parse_exec(exec_value))

        for candidate in candidates:
            add(icon_map, candidate, icon)

manual_icons = {
    "vivaldi-stable": "vivaldi",
    "vivaldi-snapshot": "vivaldi-snapshot",
    "google-chrome": "google-chrome",
    "chromium-browser": "chromium",
    "code": "visual-studio-code",
    "code-oss": "code",
    "org.gnome.Nautilus": "org.gnome.Nautilus",
    "org.wezfurlong.wezterm": "org.wezfurlong.wezterm",
}

for key, icon in manual_icons.items():
    add(icon_map, key, icon)

tmp_path = out_path.with_suffix(".tmp")

with tmp_path.open("w", encoding="utf-8") as f:
    for key, icon in icon_map.items():
        f.write(f"{key}\t{icon}\n")

tmp_path.replace(out_path)
PY
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

menu_file="$tmpdir/menu"
addr_file="$tmpdir/addr"

python3 - "$ICON_CACHE" "$menu_file" "$addr_file" <<'PY'
import json
import re
import subprocess
import sys
from pathlib import Path

icon_cache_path = Path(sys.argv[1])
menu_path = Path(sys.argv[2])
addr_path = Path(sys.argv[3])

def clean(value):
    return str(value or "").replace("\t", " ").replace("\n", " ").strip()

def norm(value):
    return re.sub(r"[^a-z0-9]+", "", str(value).lower())

def uniq(seq):
    out = []
    seen = set()

    for item in seq:
        item = clean(item)
        if not item:
            continue

        key = item.casefold()
        if key not in seen:
            seen.add(key)
            out.append(item)

    return out

def hypr_json(*args, default):
    try:
        result = subprocess.run(
            ["hyprctl", *args],
            check=True,
            capture_output=True,
            text=True
        )
        text = result.stdout.strip()
        return json.loads(text) if text else default
    except Exception:
        return default

icon_map = {}

try:
    with icon_cache_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if "\t" not in line:
                continue

            key, icon = line.split("\t", 1)
            if key and icon:
                icon_map.setdefault(key, icon)
except Exception:
    pass

def icon_for(app_class, title):
    app_class = clean(app_class)
    title = clean(title)

    variants = [
        app_class,
        app_class.lower(),
        app_class.replace("-", " "),
        app_class.replace("_", " "),
        app_class.split(".")[-1],
        app_class.removesuffix("-stable"),
        app_class.removesuffix("-beta"),
        app_class.removesuffix("-bin"),
        title,
    ]

    for item in uniq(variants):
        icon = icon_map.get(norm(item))
        if icon:
            return icon

    return app_class or "application-x-executable"

active = hypr_json("activewindow", "-j", default={})
clients = hypr_json("clients", "-j", default=[])

current_addr = clean(active.get("address"))
current_ws_id = active.get("workspace", {}).get("id")

if current_ws_id is None:
    active_workspace = hypr_json("activeworkspace", "-j", default={})
    current_ws_id = active_workspace.get("id")

current_ws_id = clean(current_ws_id)

# Workspaces that should never appear in the switcher.
# Workspace 11 is used for background apps.
excluded_ws_ids = {"11"}

windows = []

for c in clients:
    if c.get("mapped") is not True:
        continue
    if c.get("hidden") is True:
        continue
    if not c.get("class"):
        continue
    if c.get("focusHistoryID") is None:
        continue

    addr = clean(c.get("address"))
    ws_id = clean(c.get("workspace", {}).get("id"))

    # Always exclude background workspace apps.
    if ws_id in excluded_ws_ids:
        continue

    # Exclude apps on current workspace, except the currently focused app.
    if ws_id == current_ws_id and addr != current_addr:
        continue

    windows.append(c)

windows.sort(key=lambda c: c.get("focusHistoryID", 999999))

filtered = []
seen_classes = set()

for c in windows:
    app_class = clean(c.get("class"))
    class_key = app_class.casefold()

    if class_key in seen_classes:
        continue

    seen_classes.add(class_key)
    filtered.append(c)

with menu_path.open("wb") as mf, addr_path.open("w", encoding="utf-8") as af:
    for c in filtered:
        ws_id = clean(c.get("workspace", {}).get("id"))
        app_class = clean(c.get("class"))
        title = clean(c.get("title"))
        addr = clean(c.get("address"))

        icon = icon_for(app_class, title)

        if addr == current_addr:
            name = f"● CURRENT  {app_class}  {title}".strip()
        else:
            name = f"{app_class}  {title}".strip()

        visible = f"{ws_id:<4} {name}"

        icon_list = uniq([
            icon,
            app_class,
            app_class.lower(),
            app_class.split(".")[-1],
            "application-x-executable",
        ])

        mf.write(visible.encode("utf-8", "replace"))
        mf.write(b"\0icon\x1f")
        mf.write(",".join(icon_list).encode("utf-8", "replace"))
        mf.write(b"\n")

        af.write(addr + "\n")
PY

[[ -s "$menu_file" ]] || exit 0

index="$(
  fuzzel \
    --dmenu \
    --index \
    --prompt="Apps > " \
    --no-run-if-empty \
    < "$menu_file"
)" || exit 0

[[ -n "$index" ]] || exit 0

addr="$(sed -n "$((index + 1))p" "$addr_file")"

[[ -n "$addr" ]] || exit 0

hyprctl dispatch "hl.dsp.focus({ window = 'address:${addr}' })" >/dev/null
