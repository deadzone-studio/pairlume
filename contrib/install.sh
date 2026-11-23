#!/usr/bin/env bash
# Pairlume for one user: the programs into ~/.local/bin, the service started with the session.
# Run from the unpacked release:  ./install.sh [--lang pl]      To take it away:  ./install.sh --remove
# The words are in lang/<code>.json, the same files the windows and the phone app read.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="$HOME/.local/bin"
conf="${XDG_CONFIG_HOME:-$HOME/.config}/pairlume"
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
langs=(en pl szl csb de es fr it pt uk cs)

remove=0 code=""
while [ $# -gt 0 ]; do
  case "$1" in
    --remove) remove=1 ;;
    --lang) code="${2:-}"; shift ;;
    --lang=*) code="${1#--lang=}" ;;
  esac
  shift
done

# the language: asked for, chosen before, or the system's
known() { local c; for c in "${langs[@]}"; do [ "$c" = "$1" ] && return 0; done; return 1; }
if [ -z "$code" ] && [ -f "$conf/ui.json" ]; then code="$(sed -n 's/.*"lang" *: *"\([a-z]*\)".*/\1/p' "$conf/ui.json")"; fi
sys="${LANG:-en}"; sys="${sys%%_*}"; sys="${sys%%.*}"; known "$sys" || sys=en
name() { sed -n 's/^ *"name" *: *"\(.*\)",*$/\1/p' "$here/lang/$1.json" 2>/dev/null | head -1; }
if [ -z "$code" ] && [ $remove -eq 0 ] && [ -t 0 ] && [ -d "$here/lang" ]; then
  i=1; for c in "${langs[@]}"; do printf '  %2d  %s\n' "$i" "$(name "$c")"; i=$((i + 1)); done
  printf '\n  Language / Język [Enter: %s]: ' "$(name "$sys")"
  read -r pick || pick=""
  if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le ${#langs[@]} ]; then code="${langs[$((pick - 1))]}"; fi
fi
known "${code:-x}" || code="$sys"

# the words, read once
declare -A W=()
if command -v python3 >/dev/null && [ -f "$here/lang/$code.json" ]; then
  eval "$(python3 -I - "$here/lang/$code.json" <<'PY'
import json, shlex, sys
for k, v in json.load(open(sys.argv[1])).get("install", {}).items():
    if v:
        print("W[%s]=%s" % (shlex.quote(k), shlex.quote(v)))
PY
)"
fi
t() { local s="${W[$1]:-$1}"; shift; local i=1; for a in "$@"; do s="${s//%$i/$a}"; i=$((i + 1)); done; printf '%s' "$s"; }
say() { printf '\033[1m%s\033[0m\n' "$*"; }

if [ $remove -eq 1 ]; then
  systemctl --user disable --now pairlumed.service 2>/dev/null || true
  rm -f "$bin/pairlumed" "$bin/pairlume" "$bin/pairlume-ui" "$units/pairlumed.service"
  systemctl --user daemon-reload 2>/dev/null || true
  say "$(t "Pairlume is gone. Your pairings stay in ~/.config/pairlume until you delete that folder.")"
  exit 0
fi

[ "$(id -u)" -ne 0 ] || { t "Run it as yourself, not as root."; echo; exit 1; }
for f in pairlumed pairlume pairlume-ui; do [ -x "$here/$f" ] || { t "%1 is not next to this script: unpack the whole release." "$f"; echo; exit 1; }; done

# what the windows need from the system
missing=()
ldd "$here/pairlume-ui" 2>/dev/null | grep -q 'not found' && missing+=(qt6)
[ -e /usr/lib/qt6/qml/org/kde/layershell ] || [ -e /usr/lib/x86_64-linux-gnu/qt6/qml/org/kde/layershell ] || missing+=(layer-shell-qt)
if [ ${#missing[@]} -gt 0 ]; then
  say "$(t "The windows need Qt 6 and layer-shell-qt:")"
  if command -v pacman >/dev/null; then echo "  sudo pacman -S --needed qt6-declarative layer-shell-qt"
  elif command -v apt >/dev/null; then echo "  sudo apt install qml6-module-qtquick layer-shell-qt"
  elif command -v dnf >/dev/null; then echo "  sudo dnf install qt6-qtdeclarative layer-shell-qt"
  else echo "  $(t "Qt 6 (Qt Quick) and layer-shell-qt from your distribution")"; fi
  t "Install them, then run ./install.sh again. (The service itself works without them.)"; echo
fi

mkdir -p "$bin" "$units" "$conf"
install -m 755 "$here/pairlumed" "$here/pairlume" "$here/pairlume-ui" "$bin/"
install -m 644 "$here/pairlumed.service" "$units/pairlumed.service"
# the windows speak the language chosen here (Settings in the windows changes it later)
if [ -f "$conf/ui.json" ] && command -v python3 >/dev/null; then
  python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["lang"]=sys.argv[2]; json.dump(d,open(p,"w"))' "$conf/ui.json" "$code"
else
  printf '{"lang":"%s"}\n' "$code" > "$conf/ui.json"
fi
systemctl --user daemon-reload
systemctl --user enable --now pairlumed.service
systemctl --user restart pairlumed.service

case ":$PATH:" in *":$bin:"*) ;; *) say "$(t "Add ~/.local/bin to your PATH to use the pairlume command.")";; esac

say "$(t "Pairlume is installed and running.")"
echo
t "Next:"; echo
echo "  1. $(t "Install the Pairlume app on your Android phone (Android 10 or newer).")"
echo "  2. $(t "Pair: run %1 and shake the phone with the app open." "pairlume-ui")"
echo "  3. $(t "Allow what the phone may do: %1 (and calls)." "pairlume allow \"<phone>\" sms")"
echo
t "On Hyprland, to see calls when the phone rings, add to hyprland.conf:"; echo
echo "  exec-once = pairlume-ui calls"
echo
t "Phones reach this computer on TCP 47321 and mDNS (UDP 5353). With a firewall: %1" "sudo ufw allow 47321/tcp"; echo
