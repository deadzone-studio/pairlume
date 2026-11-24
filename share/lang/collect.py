#!/usr/bin/env python3
"""Gathers every word of the code into en.json (English is the key) and says which words each language is missing.
Run it after adding or changing a text in the windows (Tr.t), the phone app (t) or install.sh (t)."""
import glob, json, re, sys
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
here = Path(__file__).parent


def unq(s):
    return json.loads('"' + s + '"')


def gather():
    ui, phone, inst = [], [], []
    for f in sorted(glob.glob(str(repo / "crates/pairlume-ui/qml/*.qml"))):
        for m in re.finditer(r'Tr\.t\("((?:[^"\\]|\\.)*)"\)', Path(f).read_text()):
            k = unq(m.group(1))
            if k not in ui:
                ui.append(k)
    for f in sorted(glob.glob(str(repo / "android/app/src/main/kotlin/dev/pairlume/app/*.kt"))):
        for m in re.finditer(r'(?<![A-Za-z])t\("((?:[^"\\$]|\\.)*)"', Path(f).read_text()):
            k = unq(m.group(1))
            if k not in phone:
                phone.append(k)
    # words that come from the protocol's core and are shown as they are
    for k in ["Shake", "QR code", "Digits", "not confirmed here", "not confirmed on the computer", "the codes do not match"]:
        if k not in phone:
            phone.append(k)
    for m in re.finditer(r'\bt "((?:[^"\\]|\\.)*)"', (repo / "contrib/install.sh").read_text()):
        k = m.group(1).replace('\\"', '"')
        if k not in inst:
            inst.append(k)
    return {"ui": ui, "phone": phone, "install": inst}


keys = gather()
en = {"name": "English", "code": "en"}
for sec, ks in keys.items():
    en[sec] = {k: k for k in ks}
(here / "en.json").write_text(json.dumps(en, ensure_ascii=False, indent=2) + "\n")
missing = 0
for f in sorted(here.glob("*.json")):
    if f.name == "en.json":
        continue
    d = json.loads(f.read_text())
    for sec, ks in keys.items():
        have = d.setdefault(sec, {})
        # words no longer in the code go; new ones are listed
        for k in [k for k in have if k not in ks]:
            del have[k]
        d[sec] = {k: have[k] for k in ks if k in have}
        miss = [k for k in ks if k not in have]
        missing += len(miss)
        for k in miss:
            print(f"{f.name} {sec}: {k}")
    f.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
print(f"{sum(len(v) for v in keys.values())} words; {missing} missing translations")
sys.exit(0)
