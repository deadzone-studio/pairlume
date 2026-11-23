#!/usr/bin/env python3
"""Every language has every word of en.json, with the same %1, %2, and nothing more. Run it after changing a text."""
import json, re, sys
from pathlib import Path

here = Path(__file__).parent
en = json.loads((here / "en.json").read_text())
bad = 0
for f in sorted(here.glob("*.json")):
    d = json.loads(f.read_text())
    for need in ("name", "code"):
        if not d.get(need):
            print(f"{f.name}: no {need}"); bad += 1
    for sec, words in en.items():
        if not isinstance(words, dict):
            continue
        have = d.get(sec, {})
        for k in words:
            if k not in have:
                print(f"{f.name} {sec}: missing {k!r}"); bad += 1
            elif sorted(re.findall(r"%\d", k)) != sorted(re.findall(r"%\d", have[k])):
                print(f"{f.name} {sec}: not the same %n in {k!r}"); bad += 1
        for k in have:
            if k not in words:
                print(f"{f.name} {sec}: no longer used {k!r}"); bad += 1
print("ok" if not bad else f"{bad} problems")
sys.exit(1 if bad else 0)
