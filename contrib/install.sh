#!/usr/bin/env bash
# Pairlume for one user. Run it from the unpacked release:
#
#   ./install.sh                  a window when there is a desktop, else questions in the terminal
#   ./install.sh --text           questions in the terminal
#   ./install.sh --yes            install (or update) without questions
#   ./install.sh --remove         take it away; with --purge also forget the paired phones
#   ./install.sh --phone          put the app on the phone connected by USB (adb), or show its link
#
#   --lang <code>   the language (en pl szl csb de es fr it pt uk cs)
#   --no-calls      do not start the call window with the desktop
#   --no-menu       no entries in the menu of applications
#
# The words are in lang/<code>.json, the same files the windows and the phone app read.
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true   # bash 5.2: "&" in a replacement would mean the match
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="$HOME/.local/bin"
conf="${XDG_CONFIG_HOME:-$HOME/.config}/pairlume"
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
autostart="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
id=io.github.m4rtwy.pairlume
langs=(en pl szl csb de es fr it pt uk cs)
version="$(cat "$here/VERSION" 2>/dev/null || echo 0.0.0)"
apk="$here/Pairlume.apk"
apk_url="https://github.com/deadzone-studio/pairlume/releases/download/v$version/Pairlume-$version.apk"

what="" code="" text=0 yes=0 purge=0 calls=1 menu=1
args=("$@")
while [ $# -gt 0 ]; do
  case "$1" in
    --remove) what=remove ;;
    --purge) purge=1 ;;
    --phone) what=phone ;;
    --text) text=1 ;;
    --yes) yes=1 ;;
    --no-calls) calls=0 ;;
    --no-menu) menu=0 ;;
    --lang) code="${2:-}"; shift ;;
    --lang=*) code="${1#--lang=}" ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  esac
  shift
done

# ---------- run on its own (the install.sh next to the archives): fetch its release first ----------
release=""   # contrib/bundle.sh writes the version here in that copy
if [ ! -x "$here/pairlumed" ] && [ -n "$release" ]; then
  arch="$(uname -m)"; base="https://github.com/deadzone-studio/pairlume/releases/download/v$release"
  pack="pairlume-$release-linux-$arch"; tmp="$(mktemp -d)"
  get() { if command -v curl >/dev/null; then curl -fsSL "$1" -o "$2"; else wget -qO "$2" "$1"; fi; }
  echo "Pairlume $release: downloading $pack.tar.gz"
  get "$base/$pack.tar.gz" "$tmp/$pack.tar.gz" || { echo "Could not download $base/$pack.tar.gz" >&2; exit 1; }
  if get "$base/SHA256SUMS" "$tmp/SHA256SUMS"; then
    (cd "$tmp" && grep " $pack.tar.gz\$" SHA256SUMS | sha256sum -c --quiet) || { echo "The download is damaged; try again." >&2; exit 1; }
  fi
  tar -xzf "$tmp/$pack.tar.gz" -C "$tmp"
  exec bash "$tmp/$pack/install.sh" "${args[@]}"
fi

# ---------- the language: asked for, chosen before, or the system's ----------
known() { local c; for c in "${langs[@]}"; do [ "$c" = "$1" ] && return 0; done; return 1; }
if [ -z "$code" ] && [ -f "$conf/ui.json" ]; then code="$(sed -n 's/.*"lang" *: *"\([a-z]*\)".*/\1/p' "$conf/ui.json")"; fi
sys="${LANG:-en}"; sys="${sys%%_*}"; sys="${sys%%.*}"; known "$sys" || sys=en
name() { sed -n 's/^ *"name" *: *"\(.*\)",*$/\1/p' "$here/lang/$1.json" 2>/dev/null | head -1; }

# ---------- a desktop and the windows can start: the installer is a window ----------
windows_ok() {
  ! ldd "$here/pairlume-ui" 2>/dev/null | grep -q 'not found' &&
    { [ -e /usr/lib/qt6/qml/org/kde/layershell ] || [ -e /usr/lib/x86_64-linux-gnu/qt6/qml/org/kde/layershell ]; }
}
gui=0
if [ -z "$what" ] && [ $text -eq 0 ] && [ $yes -eq 0 ] && { [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; } && windows_ok; then
  gui=1
  # started by a click, not from a terminal: straight to the window
  [ -t 0 ] || exec "$here/pairlume-ui" setup --from "$here" ${code:+--lang "$code"}
fi

if [ -z "$code" ] && [ $yes -eq 0 ] && [ -t 0 ] && [ -d "$here/lang" ]; then
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
# a step: the window shows these lines as they come
step() { printf '• %s\n' "$*"; }
ask() { local a; [ $yes -eq 1 ] && return 0; printf '%s [%s] ' "$1" "$(t "Y/n")"; read -r a || a=""; case "$a" in [nN]*) return 1 ;; *) return 0 ;; esac; }

# from a terminal on a desktop: the window or right here
if [ $gui -eq 1 ]; then
  echo
  printf '  1  %s\n  2  %s\n\n  > ' "$(t "In a window")" "$(t "Here in the terminal")"
  read -r how || how=""
  case "$how" in 2) ;; *) exec "$here/pairlume-ui" setup --from "$here" --lang "$code" --chosen ;; esac
  echo
fi

[ "$(id -u)" -ne 0 ] || { t "Run it as yourself, not as root."; echo; exit 1; }
installed() { [ -x "$bin/pairlumed" ]; }
installed_version() { "$bin/pairlumed" --version 2>/dev/null | awk '{print $2}'; }

# ---------- taking it away ----------
remove() {
  step "$(t "Stopping Pairlume")"
  systemctl --user disable --now pairlume-calls.service pairlumed.service >/dev/null 2>&1 || true
  step "$(t "Removing the programs and the menu entries")"
  rm -f "$bin/pairlumed" "$bin/pairlume" "$bin/pairlume-ui" "$units/pairlumed.service" "$units/pairlume-calls.service" \
    "$autostart/$id.calls-autostart.desktop" "$apps/$id".*.desktop "$icons/$id.svg"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  command -v update-desktop-database >/dev/null && update-desktop-database "$apps" >/dev/null 2>&1 || true
  if [ $purge -eq 1 ]; then
    step "$(t "Forgetting the paired phones and the settings")"
    rm -rf "$conf"
    say "$(t "Pairlume is gone, with the paired phones and the settings.")"
  else
    say "$(t "Pairlume is gone. Your pairings stay in ~/.config/pairlume until you delete that folder.")"
  fi
}

# ---------- the phone app ----------
phone() {
  local adb="" devs=""
  adb="$(command -v adb || true)"; [ -n "$adb" ] || { [ -x "$HOME/Android/Sdk/platform-tools/adb" ] && adb="$HOME/Android/Sdk/platform-tools/adb"; }
  if [ -n "$adb" ] && [ -f "$apk" ]; then
    devs="$("$adb" devices 2>/dev/null | awk 'NR > 1 && $2 == "device" {print $1}')"
  fi
  if [ -n "$devs" ]; then
    for d in $devs; do
      step "$(t "Installing the app on the phone %1" "$d")"
      if "$adb" -s "$d" install -r "$apk" >/dev/null 2>&1; then say "$(t "The app is on the phone. Open Pairlume there.")"
      else t "The phone did not take the app. Allow installing from USB on it, or use the link below."; echo; devs=""; fi
    done
  fi
  if [ -z "$devs" ]; then
    t "Scan this with the phone's camera to download the app, then open the file to install it:"; echo
    "$here/pairlume" qr "$apk_url" 2>/dev/null || true
    echo "  $apk_url"
    t "Or connect the phone by USB with USB debugging on, and run: %1" "./install.sh --phone"; echo
  fi
}

# ---------- putting it in ----------
install_it() {
  for f in pairlumed pairlume pairlume-ui; do [ -x "$here/$f" ] || { t "%1 is not next to this script: unpack the whole release." "$f"; echo; exit 1; }; done
  if ! windows_ok; then
    say "$(t "The windows need Qt 6 and layer-shell-qt:")"
    if command -v pacman >/dev/null; then echo "  sudo pacman -S --needed qt6-declarative layer-shell-qt"
    elif command -v apt >/dev/null; then echo "  sudo apt install qml6-module-qtquick layer-shell-qt"
    elif command -v dnf >/dev/null; then echo "  sudo dnf install qt6-qtdeclarative layer-shell-qt"
    else echo "  $(t "Qt 6 (Qt Quick) and layer-shell-qt from your distribution")"; fi
    t "Install them, then run ./install.sh again. (The service itself works without them.)"; echo
  fi
  mkdir -p "$bin" "$units" "$conf"
  step "$(t "Copying the programs")"
  # a running service keeps its file: put the new one beside it, then swap
  for f in pairlumed pairlume pairlume-ui; do install -m 755 "$here/$f" "$bin/.$f.new" && mv -f "$bin/.$f.new" "$bin/$f"; done
  install -m 644 "$here/pairlumed.service" "$units/pairlumed.service"
  # the windows speak the language chosen here (the settings window changes it later)
  if [ -f "$conf/ui.json" ] && command -v python3 >/dev/null; then
    python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["lang"]=sys.argv[2]; json.dump(d,open(p,"w"))' "$conf/ui.json" "$code"
  else
    printf '{"lang":"%s"}\n' "$code" > "$conf/ui.json"
  fi
  step "$(t "Starting the service with your session")"
  systemctl --user daemon-reload
  systemctl --user enable pairlumed.service >/dev/null 2>&1
  systemctl --user restart pairlumed.service
  if [ $calls -eq 1 ]; then
    step "$(t "The call window starts with the desktop")"
    install -m 644 "$here/pairlume-calls.service" "$units/pairlume-calls.service"
    mkdir -p "$autostart"; install -m 644 "$here/share/applications/$id.calls-autostart.desktop" "$autostart/"
    systemctl --user daemon-reload
    systemctl --user enable pairlume-calls.service >/dev/null 2>&1 || true
    systemctl --user restart pairlume-calls.service >/dev/null 2>&1 || true
  else
    systemctl --user disable --now pairlume-calls.service >/dev/null 2>&1 || true
    rm -f "$units/pairlume-calls.service" "$autostart/$id.calls-autostart.desktop"
  fi
  if [ $menu -eq 1 ]; then
    step "$(t "Adding Pairlume to the menu of applications")"
    mkdir -p "$apps" "$icons"
    install -m 644 "$here/share/icons/$id.svg" "$icons/"
    for f in "$here/share/applications/$id".*.desktop; do
      case "$f" in *autostart*) ;; *) install -m 644 "$f" "$apps/" ;; esac
    done
    command -v update-desktop-database >/dev/null && update-desktop-database "$apps" >/dev/null 2>&1 || true
  else
    rm -f "$apps/$id".*.desktop "$icons/$id.svg"
  fi
  case ":$PATH:" in *":$bin:"*) ;; *) say "$(t "Add ~/.local/bin to your PATH to use the pairlume command.")";; esac
  say "$(t "Pairlume %1 is installed and running." "$version")"
}

after() {
  echo
  t "Next:"; echo
  echo "  1. $(t "Install the Pairlume app on your Android phone (Android 10 or newer).")"
  echo "  2. $(t "Pair: run %1 and shake the phone with the app open." "pairlume-ui")"
  echo "  3. $(t "Allow what the phone may do: %1 (and calls)." "pairlume allow \"<phone>\" sms")"
}

# ---------- a firewall keeps phones out: let them in (sudo asks for the password) ----------
fw_cmds() {
  if systemctl is-active --quiet ufw 2>/dev/null; then echo "ufw allow 47321/tcp && ufw allow 5353/udp"
  elif systemctl is-active --quiet firewalld 2>/dev/null; then echo "firewall-cmd --permanent --add-port=47321/tcp --add-service=mdns && firewall-cmd --reload"
  fi
}
firewall() {
  local c; c="$(fw_cmds)"; [ -n "$c" ] || return 0
  echo
  if [ $yes -eq 0 ] && [ -t 0 ] && ask "$(t "A firewall is on and keeps phones out. Let them in now? (it asks for your password)")"; then
    if sudo sh -c "$c" >/dev/null; then say "$(t "Phones can get through the firewall")"; return 0; fi
  fi
  t "To let phones in later, run: %1" "sudo sh -c '$c'"; echo
}

# ---------- what to do ----------
if [ -z "$what" ] && [ $yes -eq 0 ]; then
  if installed; then
    say "$(t "Pairlume %1 is installed; this is %2." "$(installed_version)" "$version")"
    echo "  1  $(t "Update or repair")"
    echo "  2  $(t "Put the app on the phone")"
    echo "  3  $(t "Remove Pairlume")"
    echo "  4  $(t "Remove it and forget the paired phones")"
    echo "  0  $(t "Cancel")"
    printf '\n  > '; read -r pick || pick=0
    case "$pick" in 1) what=install ;; 2) what=phone ;; 3) what=remove ;; 4) what=remove; purge=1 ;; *) exit 0 ;; esac
  else
    what=install
  fi
  if [ "$what" = install ]; then
    ask "$(t "Show calls on this computer when the phone rings (start the call window with the desktop)?")" || calls=0
    ask "$(t "Add Pairlume to the menu of applications?")" || menu=0
  fi
fi
case "${what:-install}" in
  remove) remove ;;
  phone) phone ;;
  install)
    install_it
    after
    firewall
    if [ $yes -eq 0 ] && ask "$(t "Put the app on the phone now?")"; then echo; phone; fi
    ;;
esac
