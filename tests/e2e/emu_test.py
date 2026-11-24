#!/usr/bin/env python3
"""Pairlume on a virtual phone (an Android emulator, never a real one: the app is installed anew there): pairs through a
link, allows everything, then checks notifications, texts and calls against a test pairlumed of its own.

    tests/e2e/emu_test.py [apk] [pictures folder]      (ANDROID_SERIAL picks the emulator, else the only one)

The computer's own pairlumed, pairings and settings are not touched: the test one has its own folder and port."""
import json, os, re, socket, subprocess, sys, tempfile, time, xml.etree.ElementTree as ET

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
APK = (sys.argv[1] if len(sys.argv) > 1 else "") or REPO + "/android/app/build/outputs/apk/debug/app-debug.apk"
HOME = os.path.expanduser("~")
ADB = [os.environ.get("ADB", HOME + "/Android/Sdk/platform-tools/adb")] + (["-s", os.environ["ANDROID_SERIAL"]] if os.environ.get("ANDROID_SERIAL") else ["-e"])
PKG = "io.github.m4rtwy.pairlume"
T = tempfile.mkdtemp(prefix="pairlume-e2e-")
SHOTS = (sys.argv[2] if len(sys.argv) > 2 else "") or T + "/shots"
SOCK = T + "/s.sock"
os.makedirs(T + "/pc", exist_ok=True)
os.makedirs(SHOTS, exist_ok=True)
ok = []


def adb(*a, check=True):
    return subprocess.run(ADB + list(a), capture_output=True, text=True, check=check).stdout


def ask(o):
    s = socket.socket(socket.AF_UNIX)
    s.connect(SOCK)
    s.sendall((json.dumps(o) + "\n").encode())
    return json.loads(s.makefile().readline())


class Watch:
    def __init__(self):
        self.s = socket.socket(socket.AF_UNIX)
        self.s.connect(SOCK)
        self.s.sendall(b'{"cmd":"watch"}\n')
        self.f = self.s.makefile()
        self.f.readline()

    def wait(self, pred, secs=30):
        self.s.settimeout(secs)
        end = time.time() + secs
        while time.time() < end:
            e = json.loads(self.f.readline())
            if pred(e):
                return e
        raise TimeoutError


def check(name, cond):
    ok.append((name, bool(cond)))
    print(("ok   " if cond else "ZLE  ") + name, flush=True)


def tap_text(label, secs=15):
    end = time.time() + secs
    while time.time() < end:
        adb("shell", "uiautomator", "dump", "/sdcard/ui.xml", check=False)
        x = adb("shell", "cat", "/sdcard/ui.xml", check=False)
        try:
            for n in ET.fromstring(x).iter("node"):
                if n.get("text") == label:
                    a, b, c, d = map(int, re.findall(r"\d+", n.get("bounds")))
                    adb("shell", "input", "tap", str((a + c) // 2), str((b + d) // 2))
                    return True
        except ET.ParseError:
            pass
        time.sleep(1)
    return False


def shot(name):
    with open(f"{SHOTS}/{name}.png", "wb") as f:
        f.write(subprocess.run(ADB + ["exec-out", "screencap", "-p"], capture_output=True).stdout)


# ---------- the computer ----------
env = dict(os.environ, PAIRLUME_DIR=T + "/pc", PAIRLUME_SOCKET=SOCK, RUST_LOG="info")
d = subprocess.Popen([REPO + "/target/debug/pairlumed", "--port", "47399", "--listen", "0.0.0.0", "--no-mdns", "--name", "Desk"],
                     env=env, stdout=open(T + "/pairlumed.log", "w"), stderr=subprocess.STDOUT)
time.sleep(1.5)
try:
    # ---------- the phone: a clean app ----------
    adb("uninstall", PKG, check=False)
    print(adb("install", "-r", "-g", APK).strip().splitlines()[-1])
    for p in ["READ_SMS", "RECEIVE_SMS", "SEND_SMS", "READ_CONTACTS", "READ_PHONE_STATE", "READ_CALL_LOG", "ANSWER_PHONE_CALLS", "CALL_PHONE", "POST_NOTIFICATIONS"]:
        adb("shell", "pm", "grant", PKG, "android.permission." + p, check=False)
    w = Watch()
    qr = ask({"cmd": "pair"})["pairing"]["qr"]
    check("the computer opens pairing with a code", qr and qr.startswith("pairlume://pair?"))
    # the link has & in it: quoted, or the phone's shell cuts it
    adb("shell", f"am start -a android.intent.action.VIEW -d '{qr}' {PKG}")
    check("the link asks first", tap_text("Pair"))
    e = w.wait(lambda e: e.get("event") == "paired", 40)
    phone = e["id"]
    check("paired through the link", phone)
    shot("01-paired")
    for cap in ["sms", "calls", "notifications"]:
        ask({"cmd": "allow", "device": phone, "cap": cap, "on": True})
    # the switches of the phone (a debug build lets the shell write them)
    prefs = '<?xml version="1.0" encoding="utf-8"?><map>' + "".join(
        f'<boolean name="{k}" value="true" />' for k in ["sms_read", "sms_send", "calls_show", "calls_act", "notifs_on"]) + "</map>"
    subprocess.run(ADB + ["shell", f"run-as {PKG} sh -c 'mkdir -p shared_prefs && cat > shared_prefs/choices.xml'"], input=prefs, text=True)
    adb("shell", "cmd", "notification", "allow_listener", f"{PKG}/dev.pairlume.app.Notifs")
    adb("shell", "am", "force-stop", PKG)
    adb("shell", "am", "start", "-n", f"{PKG}/dev.pairlume.app.MainActivity")
    w.wait(lambda e: e.get("event") == "online", 40)
    time.sleep(3)
    st = [x for x in ask({"cmd": "status"})["devices"] if x["id"] == phone][0]
    check("connected again, may use sms, calls, notifications", st["online"] and set(st["allowed"]) >= {"sms", "calls", "notifications"})
    shot("02-home")

    # ---------- notifications ----------
    adb("shell", "cmd notification post -S bigtext -t Emma e2e1 'Are you coming tonight?'")
    e = w.wait(lambda e: e.get("event") == "notif" and e.get("title") == "Emma", 20)
    print("     dotarlo:", repr(e.get("title")), repr(e.get("text")))
    check("a notification reaches the computer", "Are you coming tonight?" in e["text"])
    check("with its app and icon", e["app"] == "com.android.shell" and bool(ask({"cmd": "notif_icon", "device": phone, "app": e["app"]}).get("icon")))
    lst = ask({"cmd": "notifications", "device": phone})["notifications"]
    check("the computer keeps it for windows", any(n["key"] == e["key"] for n in lst))
    r = ask({"cmd": "notif", "device": phone, "key": e["key"], "what": "dismiss"})
    check("dismissing it from the computer works", r.get("ok"))
    w.wait(lambda x: x.get("event") == "notif_gone" and x.get("key") == e["key"], 20)
    check("and it is gone from the phone", "e2e1" not in adb("shell", "dumpsys", "notification", "--noredact"))
    adb("shell", "cmd notification post -S bigtext -t Mail e2e2 'Your order is ready'")
    e2 = w.wait(lambda e: e.get("event") == "notif" and e.get("title") == "Mail", 20)
    # gone on the phone without the computer (snoozed away)
    adb("shell", f"cmd notification snooze --for 60000 '{e2['key']}'")
    w.wait(lambda x: x.get("event") == "notif_gone" and x.get("key") == e2["key"], 20)
    check("dismissed on the phone: gone on the computer", True)

    # ---------- texts ----------
    adb("emu", "sms", "send", "5551234", "Hello from the virtual phone")
    e = w.wait(lambda e: e.get("event") == "sms", 30)
    check("a text that comes reaches the computer", e["message"]["text"] == "Hello from the virtual phone")
    th = ask({"cmd": "sms_threads", "device": phone, "before": None})
    print("     rozmowy:", [t["address"] for t in th["answer"]["threads"]][:5])
    check("the computer reads the conversations", any("5551234" in t["address"] for t in th["answer"]["threads"]))

    # ---------- calls ----------
    adb("emu", "gsm", "call", "5551234")
    # Android tells it twice: first without the number, then with it
    e = w.wait(lambda e: e.get("event") == "call" and e.get("state") == "ringing" and e.get("number"), 30)
    print("     numer:", repr(e.get("number")), repr(e.get("name")))
    check("a call rings on the computer", "5551234" in e["number"])
    r = ask({"cmd": "call", "device": phone, "what": "answer"})
    check("answered from the computer", r.get("ok"))
    w.wait(lambda e: e.get("event") == "call" and e.get("state") == "talking", 20)
    check("and it is talking", True)
    shot("03-call")
    r = ask({"cmd": "call", "device": phone, "what": "end"})
    w.wait(lambda e: e.get("event") == "call" and e.get("state") == "ended", 20)
    check("ended from the computer", r.get("ok"))
    adb("emu", "gsm", "call", "5559876")
    w.wait(lambda e: e.get("event") == "call" and e.get("state") == "ringing", 30)
    adb("emu", "gsm", "cancel", "5559876")
    e = w.wait(lambda e: e.get("event") == "call" and e.get("state") == "ended", 30)
    check("a call nobody answers is missed", e.get("missed"))
except Exception:
    import traceback
    traceback.print_exc()
    ok.append(("no error on the way", False))
finally:
    d.terminate()
    print(f"\n{sum(1 for _, x in ok if x)} of {len(ok)} ok; pictures in {SHOTS}, the log in {T}/pairlumed.log")
    sys.exit(0 if ok and all(x for _, x in ok) else 1)
