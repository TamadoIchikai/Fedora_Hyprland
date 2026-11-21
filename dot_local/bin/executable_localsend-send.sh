#!/usr/bin/env bash
# Put things into LocalSend's Send tab and show LocalSend: you only pick the device.
#
#   localsend-send.sh --clipboard     clipboard: copied files, an image, or text
#   localsend-send.sh --pick          file picker (zenity) + drop zone on its left
#   localsend-send.sh --add FILE...   add only, don't show LocalSend (drop zone)
#   localsend-send.sh --text "msg"    a text message
#   localsend-send.sh FILE|DIR...     files / folders
#
# LocalSend (1.18+) is single-instance: a second launch with paths or
# `--text <msg>` POSTs those args to the running app (/api/localsend/v2/show),
# which adds them to the Send selection and opens the Send tab. Launching the
# AppImage just for that takes ~5 s, so this script sends the same request
# itself (~70 ms), authenticating like LocalSend does: the show token plus the
# app's own client certificate, both from its settings file. If that fails it
# falls back to the AppImage. Nothing is sent until a device is chosen.
#
# Used by the waybar share icon (~/.config/waybar/scripts/connection.json).
# Waybar-safe: quiet, always exits 0.
set -uo pipefail

APP="$HOME/.local/bin/LocalSend.AppImage"
APP_CLASS="org.localsend.localsend_app"
TOGGLE="$HOME/.config/waybar/scripts/workspace-toggle.sh"
PREFS="$HOME/.local/share/localsend_app/shared_preferences.json"
# Clipboard images are saved here (tmpfs, per user); pruned after a day.
CLIP_DIR="${XDG_RUNTIME_DIR:-/tmp}/localsend-clipboard"

# Absolute path (LocalSend resolves paths in its own process).
abspath() { realpath -e -- "$1" 2>/dev/null; }

# file:// URIs (text/uri-list) -> paths, one per line.
uris_to_paths() {
  python3 -I -c '
import sys, urllib.parse
for line in sys.stdin.read().splitlines():
    line = line.strip()
    if line.startswith("file://"):
        print(urllib.parse.unquote(urllib.parse.urlparse(line).path))
'
}

ARGS=()   # args handed to LocalSend

add_paths() {
  local p a
  for p in "$@"; do
    a="$(abspath "$p")" && ARGS+=("$a")
  done
}

add_text() {
  [ -n "${1//[[:space:]]/}" ] && ARGS+=(--text "$1")
}

from_clipboard() {
  local types
  types="$(wl-paste --list-types 2>/dev/null)" || return 0
  [ -n "$types" ] || return 0

  # Copied files/folders (file managers).
  if grep -qx 'text/uri-list' <<<"$types"; then
    local -a paths
    mapfile -t paths < <(wl-paste --type text/uri-list 2>/dev/null | uris_to_paths)
    add_paths "${paths[@]}"
    [ "${#ARGS[@]}" -gt 0 ] && return 0
  fi

  # Image (screenshots, "copy image").
  local img
  img="$(grep -m1 '^image/' <<<"$types")"
  if [ -n "$img" ]; then
    mkdir -p -m 700 "$CLIP_DIR"
    find "$CLIP_DIR" -type f -mmin +1440 -delete 2>/dev/null
    local ext="${img#image/}"; ext="${ext%%;*}"; [ "$ext" = "jpeg" ] && ext=jpg
    local file="$CLIP_DIR/clipboard-$(date +%Y%m%d-%H%M%S).$ext"
    if wl-paste --type "$img" >"$file" 2>/dev/null && [ -s "$file" ]; then
      ARGS+=("$file")
      return 0
    fi
    rm -f "$file"
  fi

  # Text.
  if grep -qiE '^(text/plain|UTF8_STRING|STRING|TEXT)' <<<"$types"; then
    add_text "$(wl-paste --no-newline 2>/dev/null)"
  fi
}

# Hand ARGS to the running LocalSend directly (exit 0 = accepted).
handoff() {
  python3 -I - "$PREFS" "$@" <<'EOF'
import json, os, ssl, sys, tempfile, urllib.request
prefs = json.load(open(sys.argv[1]))
token = prefs["flutter.ls_show_token"]
sec = json.loads(prefs["flutter.ls_security_context"])
port = prefs.get("flutter.ls_port", 53317)
# LocalSend's server uses a self-signed cert and requires a client cert (its own).
ctx = ssl._create_unverified_context()
with tempfile.NamedTemporaryFile("w", dir=os.environ.get("XDG_RUNTIME_DIR"), suffix=".pem") as f:
    os.chmod(f.name, 0o600)
    f.write(sec["privateKey"].strip() + "\n" + sec["certificate"].strip() + "\n")
    f.flush()
    ctx.load_cert_chain(f.name)
req = urllib.request.Request(
    f"https://127.0.0.1:{port}/api/localsend/v2/show?token={token}",
    data=json.dumps({"args": sys.argv[2:]}).encode(),
    headers={"Content-Type": "application/json"}, method="POST")
with urllib.request.urlopen(req, context=ctx, timeout=2) as r:
    sys.exit(0 if r.status == 200 else 1)
EOF
}

app_running() {
  hyprctl clients -j 2>/dev/null | jq -e --arg c "$APP_CLASS" 'any(.[]; .class == $c)' >/dev/null 2>&1
}

[ -x "$APP" ] || exit 0

# Add only (no window show): used by the Quickshell drop zone for each drop.
if [ "${1:-}" = "--add" ]; then
  shift
  add_paths "$@"
  [ "${#ARGS[@]}" -gt 0 ] || exit 0
  if app_running; then
    handoff "${ARGS[@]}" >/dev/null 2>&1 || timeout 10 "$APP" "${ARGS[@]}" >/dev/null 2>&1
  else
    setsid -f "$APP" "${ARGS[@]}" >/dev/null 2>&1 </dev/null
  fi
  exit 0
fi

# File picker, with the Quickshell drop zone (DropZone.qml) on its left: dropped
# files are added right away, picked ones below. Nothing picked or dropped =
# do nothing. (The title is matched by a float rule in hyprland.lua.)
if [ "${1:-}" = "--pick" ]; then
  out="$(mktemp -p "${XDG_RUNTIME_DIR:-/tmp}" localsend-pick.XXXXXX)"
  zenity --file-selection --multiple --separator=$'\n' \
    --title="Send with LocalSend" --filename="$HOME/" >"$out" 2>/dev/null &
  zpid=$!
  qs -c quickshell_modules ipc call dropzone open "$zpid" >/dev/null 2>&1
  wait "$zpid"
  dropped="$(qs -c quickshell_modules ipc call dropzone close 2>/dev/null)"
  dropped="${dropped//[^0-9]/}"
  mapfile -t picked <"$out"
  rm -f "$out"
  [ "${#picked[@]}" -gt 0 ] || [ "${dropped:-0}" -gt 0 ] || exit 0
  set -- "${picked[@]}"   # may be empty: then LocalSend is just shown
fi

if app_running; then
  # Show it on this workspace right away (it may be parked), while the
  # clipboard is read; then add the items.
  "$TOGGLE" "$APP_CLASS" "$APP" show &
  case "${1:-}" in
    --clipboard) from_clipboard ;;
    --text)      add_text "${2:-}" ;;
    "")          ;;
    *)           add_paths "$@" ;;
  esac
  if [ "${#ARGS[@]}" -gt 0 ]; then
    handoff "${ARGS[@]}" >/dev/null 2>&1 \
      || timeout 10 "$APP" "${ARGS[@]}" >/dev/null 2>&1   # slow fallback
  fi
  wait
else
  # Not running: start it with the args (opens on the current workspace).
  case "${1:-}" in
    --clipboard) from_clipboard ;;
    --text)      add_text "${2:-}" ;;
    "")          ;;
    *)           add_paths "$@" ;;
  esac
  setsid -f "$APP" "${ARGS[@]}" >/dev/null 2>&1 </dev/null
fi
exit 0
