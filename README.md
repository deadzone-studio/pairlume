# Pairlume

Your Android phone and your Hyprland desktop as one: texts, calls, notifications, the phone's screen, and plugins.

> **Early days.** The encrypted link and pairing work between the computer and a pretend phone. There is no Android
> app and no window yet. Nothing here is ready for daily use.

## Where it is

| Stage | What | State |
|---|---|---|
| 0 | Project, protocol, tests | done |
| 1 | Pairing (shake, QR, digits), reconnecting, battery | computer side done, Android app and window next |
| 2 | Texts: window, panel, chat bubbles | planned |
| 3 | Calls | planned |
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

## Try it

Needs a recent stable Rust.

```sh
cargo build
target/debug/pairlumed                 # the service
target/debug/pairlume pair             # in another terminal
```

There is no Android app yet, so a pretend phone does the other half:

```sh
target/debug/pairlume-fake --dir /tmp/fake shake 127.0.0.1:47321
target/debug/pairlume-fake --dir /tmp/fake run 127.0.0.1:47321
target/debug/pairlume status
```

A firewall has to let TCP port 47321 in from your network (and UDP 5353 for finding the computer).

## License

GPL-3.0-or-later. The plugin kit, when it is here, will be MIT, so a plugin can have any license.
