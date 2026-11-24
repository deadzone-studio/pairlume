#!/usr/bin/env bash
# Makes the release folder and its archives: contrib/bundle.sh [out folder]
# Build first: cargo build --release && cargo build --release -p pairlume-ui && (cd android && ./gradlew :app:assembleRelease)
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$repo/target/bundle}"
version="$(sed -n 's/^version = "\(.*\)"/\1/p' "$repo/Cargo.toml" | head -1)"
name="pairlume-$version-linux-$(uname -m)"
d="$out/$name"
rm -rf "$d"; mkdir -p "$d/lang" "$d/share"
for f in pairlumed pairlume pairlume-ui; do install -m 755 "$repo/target/release/$f" "$d/"; strip "$d/$f" 2>/dev/null || true; done
install -m 755 "$repo/contrib/install.sh" "$d/"
install -m 644 "$repo/contrib/systemd/pairlumed.service" "$repo/contrib/systemd/pairlume-calls.service" "$repo/contrib/systemd/pairlume-notifications.service" "$repo/LICENSE" "$d/"
cp "$repo"/share/lang/*.json "$d/lang/"
cp -r "$repo/share/applications" "$repo/share/icons" "$d/share/"
printf '%s\n' "$version" > "$d/VERSION"
apk="$repo/android/app/build/outputs/apk/release/app-release.apk"
[ -f "$apk" ] && install -m 644 "$apk" "$d/Pairlume.apk"
cat > "$d/README.txt" <<TXT
Pairlume $version for Linux ($(uname -m))

  ./install.sh            installs it (a window when there is a desktop), updates it, or takes it away
  ./install.sh --help     everything it can do

Pairlume.apk is the phone app (Android 10 or newer). More: https://github.com/deadzone-studio/pairlume
TXT
cd "$out"
rm -f "$name.tar.gz" "$name.zip"
tar -czf "$name.tar.gz" "$name"
python3 -I - "$name" <<'PY'
import os, sys, zipfile
d = sys.argv[1]
with zipfile.ZipFile(d + ".zip", "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(d):
        for f in sorted(files):
            p = os.path.join(root, f); i = zipfile.ZipInfo.from_file(p); i.compress_type = zipfile.ZIP_DEFLATED
            with open(p, "rb") as fh: z.writestr(i, fh.read())
PY
[ -f "$d/Pairlume.apk" ] && cp "$d/Pairlume.apk" "Pairlume-$version.apk"
sed "s/^release=\"\"/release=\"$version\"/" "$d/install.sh" > install.sh; chmod 755 install.sh
sha256sum "$name.tar.gz" "$name.zip" install.sh $( [ -f "Pairlume-$version.apk" ] && echo "Pairlume-$version.apk") > SHA256SUMS
ls -la "$out" | tail -n +2
