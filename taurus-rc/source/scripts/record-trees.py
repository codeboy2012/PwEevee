#!/usr/bin/env python3
"""Record Spotify view trees from the iPhone over USB, one file per screen, into trees/.

    scripts/record-trees.py                    # interactive: pick screens, record each, save trees/<name>.txt
    scripts/record-trees.py --import LOG NAME  # file an old syslog capture as trees/NAME.txt
    scripts/record-trees.py --url URL          # fetch trees from URL instead of the phone (testing)
    scripts/record-trees.py -C                 # continuous: every Enter saves trees/continuous/1.txt, 2.txt, ...

A FLEX build of the tweak serves the visible screen's tree on the phone's loopback port 8085. This
script opens that port over USB with iproxy and pulls the tree when you press Enter, so Spotify only
has to show the screen. Screens live in trees/screens.txt as "name | hint".
"""
import datetime
import os
import re
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TREES = os.path.join(ROOT, "trees")
SCREENS = os.path.join(TREES, "screens.txt")
CONTINUOUS = os.path.join(TREES, "continuous")
PORT = 8085

DEFAULT_SCREENS = [
    ("home", "Home tab"),
    ("search", "Search tab"),
    ("library", "Library tab"),
    ("create", "the + tab"),
    ("now-playing", "tap the now playing bar to open the full player"),
    ("playlist", "open any playlist"),
    ("album", "open any album"),
    ("artist", "open any artist page"),
    ("queue", "open the queue from the player"),
    ("lyrics", "open the lyrics from the player"),
    ("settings", "avatar → settings"),
]

TIMESTAMP = re.compile(r"^[A-Z][a-z]{2} +\d+ \d\d:\d\d:\d\d\.\d+ ")
TAG = re.compile(r"\[spotifyglass\] (.*)$")
PART = re.compile(r"^(.*) (\d+)/(\d+)$")
PAGE = re.compile(r"<((?:Home_|Browse_|Search_|Library_|Create|NowPlaying_Scroll|Playlist|Album|Artist|Queue|Lyrics|Settings)[A-Za-z_]*\.[A-Za-z]+)")


def load_screens():
    if not os.path.exists(SCREENS):
        os.makedirs(TREES, exist_ok=True)
        with open(SCREENS, "w") as f:
            f.writelines(f"{name} | {hint}\n" for name, hint in DEFAULT_SCREENS)
    screens = []
    for line in open(SCREENS):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, _, hint = line.partition("|")
        screens.append((name.strip(), hint.strip()))
    return screens


def add_screen(name, hint):
    with open(SCREENS, "a") as f:
        f.write(f"{name} | {hint}\n")


def pages_in(text):
    return sorted(set(PAGE.findall(text)))


def describe(text):
    return f"{text.count(chr(10))} lines, pages: {', '.join(pages_in(text)) or 'none recognised'}"


def write_tree(name, text, source, messages=None, folder=TREES):
    path = os.path.join(folder, f"{name}.txt")
    with open(path, "w") as f:
        f.write(f"# screen: {name}\n# recorded: {datetime.datetime.now():%Y-%m-%d %H:%M} via {source}\n# {describe(text)}\n")
        if messages:
            f.write("# messages:\n" + "\n".join(messages) + "\n")
        f.write("# tree:\n" + text + ("" if text.endswith("\n") else "\n"))
    return path


def parse_log(lines):
    """Old syslog captures: returns (single messages, stitched dumps)."""
    messages, current = [], None
    for raw in lines:
        line = raw.rstrip("\n")
        if TIMESTAMP.match(line):
            current = None
            m = TAG.search(line)
            if m:
                current = [m.group(1), []]
                messages.append(current)
        elif current is not None:
            current[1].append(line)
    singles, dumps = [], []
    for header, body in messages:
        m = PART.match(header)
        if not m:
            singles.append(header + ("\n" + "\n".join(body) if body else ""))
            continue
        tag, index, total = m.group(1), int(m.group(2)), int(m.group(3))
        if index == 1 or not dumps or dumps[-1]["tag"] != tag:
            dumps.append({"tag": tag, "total": total, "parts": {}})
        dumps[-1]["parts"][index] = "\n".join(body)
    complete = [("\n".join(d["parts"][i] for i in sorted(d["parts"]))) for d in dumps if len(d["parts"]) == d["total"]]
    return singles, complete


def fetch(url):
    with urllib.request.urlopen(url, timeout=20) as response:
        return response.read().decode("utf-8", "replace")


def ask(prompt):
    try:
        return input(prompt).strip().lower()
    except EOFError:
        return "q"


def pick(screens):
    print("\nScreens in trees/:")
    for i, (name, hint) in enumerate(screens, 1):
        path = os.path.join(TREES, f"{name}.txt")
        status = f"recorded {datetime.datetime.fromtimestamp(os.path.getmtime(path)):%Y-%m-%d %H:%M}" if os.path.exists(path) else "missing"
        print(f"  {i:2d}. {name:<14} {status:<26} {hint}")
    print("\nSelect: numbers or ranges (1,3-5), 'a' all, 'm' missing only [default], 'n' add a new screen, 'q' quit")
    while True:
        answer = ask("> ")
        if answer in ("q", "quit"):
            return None
        if answer == "n":
            name = input("  new screen name (letters, digits, dashes): ").strip().lower()
            if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name):
                print("  invalid name")
                continue
            hint = input("  hint (how to get there): ").strip()
            add_screen(name, hint)
            screens.append((name, hint))
            print(f"  added {name}")
            return pick(screens)
        if answer in ("", "m"):
            return [s for s in screens if not os.path.exists(os.path.join(TREES, f"{s[0]}.txt"))]
        if answer == "a":
            return list(screens)
        chosen = []
        try:
            for token in answer.split(","):
                token = token.strip()
                if "-" in token:
                    lo, hi = token.split("-")
                    chosen.extend(range(int(lo), int(hi) + 1))
                elif token:
                    chosen.append(int(token))
            if all(1 <= c <= len(screens) for c in chosen):
                return [screens[c - 1] for c in chosen]
        except ValueError:
            pass
        print("  didn't understand that")


def record(url, name, hint):
    exists = os.path.exists(os.path.join(TREES, f"{name}.txt"))
    print(f"\n▶ Now recording: {name}{'  (will overwrite)' if exists else ''}")
    print(f"  {hint}. When it is on screen press Enter.   [s] skip   [q] quit")
    while True:
        answer = ask("  > ")
        if answer == "q":
            return "quit"
        if answer == "s":
            return "skipped"
        try:
            text = fetch(url)
        except Exception as error:
            print(f"  could not fetch the tree ({error}).")
            print("  Spotify (the FLEX build) must be open in the foreground, the phone unlocked and on USB. Press Enter to try again.")
            continue
        if "== window" not in text:
            print("  the phone answered but not with a tree, press Enter to try again")
            continue
        path = write_tree(name, text, "usb")
        print(f"  saved {os.path.relpath(path, ROOT)}: {describe(text)}")
        return "saved"


def record_continuous(url):
    os.makedirs(CONTINUOUS, exist_ok=True)
    for old in os.listdir(CONTINUOUS):
        if old.endswith(".txt"):
            os.remove(os.path.join(CONTINUOUS, old))
    print("\nContinuous mode: press Enter to save the visible screen as the next numbered file.   [q] quit")
    count = 0
    while True:
        if ask("> ") == "q":
            return
        try:
            text = fetch(url)
        except Exception as error:
            print(f"  could not fetch the tree ({error}).")
            continue
        if "== window" not in text:
            print("  the phone answered but not with a tree, press Enter to try again")
            continue
        count += 1
        path = write_tree(str(count), text, "usb", folder=CONTINUOUS)
        print(f"  saved {os.path.relpath(path, ROOT)}: {describe(text)}")


def main():
    args = sys.argv[1:]
    continuous = "-C" in args
    if continuous:
        args.remove("-C")
    if len(args) == 3 and args[0] == "--import":
        singles, dumps = parse_log(open(args[1], errors="replace"))
        if not dumps and not singles:
            sys.exit("nothing usable in that log")
        path = write_tree(args[2], dumps[-1] if dumps else "", os.path.basename(args[1]), singles)
        print(f"saved {path}" + (f": {describe(dumps[-1])}" if dumps else " (messages only)"))
        return
    url, tunnel = None, None
    if len(args) == 2 and args[0] == "--url":
        url = args[1]
    elif args:
        sys.exit(__doc__)
    else:
        if subprocess.run(["idevice_id", "-l"], capture_output=True, text=True).stdout.strip() == "":
            sys.exit("no iPhone on USB: plug it in, unlock it, tap Trust if asked, then run again")
        tunnel = subprocess.Popen(["iproxy", f"{PORT}:{PORT}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        url = f"http://127.0.0.1:{PORT}/tree"
    if continuous:
        try:
            record_continuous(url)
        except KeyboardInterrupt:
            print()
        finally:
            if tunnel:
                tunnel.terminate()
        return
    screens = load_screens()
    chosen = pick(screens)
    if not chosen:
        if tunnel:
            tunnel.terminate()
        return
    try:
        for name, hint in chosen:
            if record(url, name, hint) == "quit":
                break
    except KeyboardInterrupt:
        print()
    finally:
        if tunnel:
            tunnel.terminate()
    print("done, trees are in trees/")


if __name__ == "__main__":
    main()
