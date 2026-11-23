#!/usr/bin/env bash
# Pairlume for one user: the programs into ~/.local/bin, the service started with the session.
# Run from the unpacked release:  ./install.sh      To take it away:  ./install.sh --remove
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="$HOME/.local/bin"
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
say() { printf '\033[1m%s\033[0m\n' "$*"; }

if [ "${1:-}" = "--remove" ]; then
  systemctl --user disable --now pairlumed.service 2>/dev/null || true
  rm -f "$bin/pairlumed" "$bin/pairlume" "$bin/pairlume-ui" "$units/pairlumed.service"
  systemctl --user daemon-reload 2>/dev/null || true
  say "Pairlume is gone. Your pairings stay in ~/.config/pairlume until you delete that folder."
  exit 0
fi

[ "$(id -u)" -ne 0 ] || { echo "Run it as yourself, not as root."; exit 1; }
for f in pairlumed pairlume pairlume-ui; do [ -x "$here/$f" ] || { echo "$f is not next to this script: unpack the whole release."; exit 1; }; done

# what the windows need from the system
missing=()
ldd "$here/pairlume-ui" 2>/dev/null | grep -q 'not found' && missing+=(qt6)
[ -e /usr/lib/qt6/qml/org/kde/layershell ] || [ -e /usr/lib/x86_64-linux-gnu/qt6/qml/org/kde/layershell ] || missing+=(layer-shell-qt)
if [ ${#missing[@]} -gt 0 ]; then
  say "The windows need Qt 6 and layer-shell-qt:"
  if command -v pacman >/dev/null; then echo "  sudo pacman -S --needed qt6-declarative layer-shell-qt"
  elif command -v apt >/dev/null; then echo "  sudo apt install qml6-module-qtquick layer-shell-qt"
  elif command -v dnf >/dev/null; then echo "  sudo dnf install qt6-qtdeclarative layer-shell-qt"
  else echo "  Qt 6 (Qt Quick) and layer-shell-qt from your distribution"; fi
  echo "Install them, then run ./install.sh again. (The service itself works without them.)"
fi

mkdir -p "$bin" "$units"
install -m 755 "$here/pairlumed" "$here/pairlume" "$here/pairlume-ui" "$bin/"
install -m 644 "$here/pairlumed.service" "$units/pairlumed.service"
systemctl --user daemon-reload
systemctl --user enable --now pairlumed.service
systemctl --user restart pairlumed.service

case ":$PATH:" in *":$bin:"*) ;; *) say "Add ~/.local/bin to your PATH to use the pairlume command.";; esac

say "Pairlume is installed and running."
cat <<TEXT

Next:
  1. Install Pairlume.apk on your Android phone (Android 10 or newer).
  2. Pair:  pairlume-ui            and shake the phone with the app open.
  3. Allow what the phone may do:  pairlume allow "<phone>" sms   (and calls)

On Hyprland, to see calls when the phone rings, add to hyprland.conf:
  exec-once = pairlume-ui calls

The firewall must let phones in on TCP 47321 and mDNS (UDP 5353), e.g.  sudo ufw allow 47321/tcp
TEXT
