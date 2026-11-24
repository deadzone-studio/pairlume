# Pairlume

Your Android phone and your Hyprland desktop as one: texts, calls, notifications, the phone's screen, and plugins.

![Pairing: shake the phone, scan a code, compare six digits, connected](docs/img/pairing.png)

> **Early days.** Pairing and reconnecting work between a computer and an Android phone, texts are being tried. Nothing
> here is ready for daily use.

## Where it is

| Stage | What | State |
|---|---|---|
| 0 | Project, protocol, tests | done |
| 1 | Pairing (shake, QR, digits), reconnecting, battery | works, being tried on real phones |
| 2 | Texts: window, panel, chat bubbles | works |
| 3 | Calls: who calls, answer, decline, call back (the voice stays on the phone) | works with the pretend phone, being tried on real ones |
| 4 | Notifications in three styles, colors from the wallpaper, glass, animations | planned |
| **0.1** | **first release** | |
| later | Files, clipboard, wireless screen, plugins and themes, remote control, camera | planned |

## How pairing stays safe

- The link is TLS 1.3 with a certificate on both ends. Pairing remembers the other one's fingerprint; anyone else is
  turned away, also on the same Wi-Fi.
- Shaking the phone only says "here I am". Both screens then show the same six digits, and both sides have to say yes.
- The QR code and the typed digits are used for one try.
- A paired phone may do **nothing** until you allow it, one permission at a time.
- Nothing from the phone is written to disk.

The details are in [docs/protocol.md](docs/protocol.md).

## Languages

English, Polski, Ślōnsko godka, Kaszëbsczi, Deutsch, Español, Français, Italiano, Português, Українська and Čeština, in
the windows, the phone app and the installer. All the words are in [`share/lang`](share/lang), one file per language;
`python3 share/lang/check.py` says what a file is missing. Apart from Polish these are first translations: corrections
from people who speak them are very welcome.

## Install

From the [releases](https://github.com/deadzone-studio/pairlume/releases), either:

- unpack `pairlume-…-linux-x86_64.zip` (or `.tar.gz`) and run `./install.sh`, or
- download just `install.sh` and run it with `bash install.sh`: it fetches its release and checks it first.

On a desktop the installer is a window: pick the language, what to install and, at the end, put the app on the phone
(over a USB cable when one is connected with USB debugging on, or by scanning a code). Run it again to update, to put the
app on a phone, or to take Pairlume away, keeping or forgetting the paired phones.

![The installer: what to install, the phone, and what it offers when Pairlume is already there](docs/img/installer.png)

Everything lives in your home: the programs in `~/.local/bin`, the service as a systemd user unit that starts with your
session. Without a desktop, or with `--text`, it asks the same in the terminal. Without questions:

```
./install.sh --yes [--lang pl] [--no-calls] [--no-menu]   install or update
./install.sh --phone                                     put the app on the phone
./install.sh --remove [--purge]                          take it away (--purge: forget the paired phones too)
```

The phone app is also on its own as `Pairlume-….apk` (Android 10 or newer). Releases are early previews until 0.1.
`contrib/bundle.sh` makes the release files from a build.

The phone app is signed with this key (SHA-256 of the certificate):
`50:11:B3:93:23:01:22:35:66:25:F8:4F:6B:B6:89:08:6B:BB:A9:7D:DD:7A:4B:02:9E:3C:C0:C4:D2:C3:40:A3`

## Try it

Needs a recent stable Rust.

```sh
cargo build
target/debug/pairlumed                 # the service
target/debug/pairlume pair             # in another terminal
```

The pairing window needs Qt 6 (`qt6-declarative`) and `layer-shell-qt`, and a Wayland compositor with layers. It is made
for Hyprland ([colors and glass](docs/hyprland.md)):

```sh
cargo build -p pairlume-ui
target/debug/pairlume-ui               # pairing
target/debug/pairlume-ui messages      # texts: a window
target/debug/pairlume-ui panel         # ... from the edge of the screen
target/debug/pairlume-ui bubbles       # ... as faces at the edge
target/debug/pairlume-ui calls         # waits, and shows a call when the phone rings
```

![Texts as a window, a panel and bubbles](docs/img/texts.png)

![A call: ringing, answered, missed](docs/img/calls.png)

The Android app (Android 10 or newer) needs JDK 21 and the Android SDK (platform 36):

```sh
cd android && ./gradlew :app:installDebug
```

Without a phone, a pretend one does the other half:

```sh
target/debug/pairlume-fake --dir /tmp/fake shake 127.0.0.1:47321
target/debug/pairlume-fake --dir /tmp/fake run 127.0.0.1:47321
target/debug/pairlume status
```

A firewall has to let TCP port 47321 in from your network (and UDP 5353 for finding the computer).

## License

GPL-3.0-or-later. The plugin kit, when it is here, will be MIT, so a plugin can have any license.
