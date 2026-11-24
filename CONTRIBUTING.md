# Contributing

Issues and pull requests are welcome.

- `cargo fmt`, `cargo clippy --all-targets -- -D warnings` and `cargo test` have to pass.
- Never put real texts, numbers, names or notifications into code, tests, issues or screenshots. Use `pairlume-fake`.
- A change to what the two ends say to each other goes into `docs/protocol.md` too.
- Found a security problem? Use "Report a vulnerability" under Security, not a public issue.

## On a virtual phone

`tests/e2e/emu_test.py` installs the debug app on an Android emulator (never on a real phone) and checks pairing through
a link, notifications both ways, an incoming text and a call answered, ended and missed, against a test `pairlumed` with
its own folder and port. Build first (`cargo build`, `cd android && ./gradlew :app:assembleDebug`), start an emulator
with Android 10 or newer, then run it; `ANDROID_SERIAL` picks the emulator when there are several.

