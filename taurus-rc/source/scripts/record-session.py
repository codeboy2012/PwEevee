#!/usr/bin/env python3
"""Record clean view trees screen by screen, as many snapshots of each screen as you like.

    scripts/record-session.py                   # every screen of the session, in order
    scripts/record-session.py playlist artist   # only these screens
    scripts/record-session.py --list            # the screens and what is recorded so far
    scripts/record-session.py -o trees/other    # another folder (default trees/clean)
    scripts/record-session.py --url URL         # fetch from URL instead of the phone (testing)

It names a screen ("now record: playlist") and every Enter saves the tree of what the phone shows as
the next numbered file of that screen, trees/clean/<screen>/01.txt, 02.txt and on. Type a few words
before Enter to put them in the name ("02 scrolled.txt"); a screen's name alone jumps to that screen
instead. n goes on to the next screen, b back to the one before; u takes back the last snapshot, q quits. trees/clean/INDEX.txt lists what is recorded.

The tree comes from the tree server of a FLEX build (make install FLEX=1), through iproxy over USB, the
way scripts/record-trees.py gets it. That build also reports the mod's own settings under "== mod", so
every snapshot says whether it shows Spotify as it came or a screen a switch of the mod's has changed.
"""
import datetime
import hashlib
import importlib.util
import os
import re
try:
    import readline  # noqa: F401  arrow keys and history at the prompt
except ImportError:
    pass
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PORT = 8085

# The tree recorder's own helpers (describe, fetch), so both scripts read the phone the same way.
_spec = importlib.util.spec_from_file_location("record_trees", os.path.join(HERE, "record-trees.py"))
recorder = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(recorder)

# (folder, how to get there, the states worth a snapshot each)
SESSION = [
    ("home", "the Home tab", [
        "the top of Home",
        "scroll down a screen at a time to the bottom, Enter after each",
        "the side drawer (tap your avatar)",
    ]),
    ("search", "the Search tab", [
        "the browse page, top",
        "the browse page scrolled to the bottom",
        "tap the search field: recent searches",
        "type an artist's name: the results",
        "each filter chip in turn: Songs, Artists, Albums, Playlists",
        "results scrolled",
    ]),
    ("library", "the Library tab", [
        "the top, as a list",
        "as a grid",
        "each filter chip in turn: Playlists, Albums, Artists, Downloaded",
        "the sort sheet",
        "scrolled to the bottom",
        "search in Library opened",
    ]),
    ("playlist", "a playlist someone else made, a Spotify editorial one for instance", [
        "the top",
        "scroll down a screen at a time to the very bottom (recommended songs)",
        "find in playlist opened",
        "the sort sheet",
        "the … menu of a track",
    ]),
    ("liked-songs", "Library → Liked Songs", [
        "the top",
        "scrolled",
    ]),
    ("own-playlist", "a playlist you made yourself", [
        "the top",
        "scrolled",
        "edit mode",
    ]),
    ("album", "any album (a multi-disc one too, if you have one)", [
        "the top",
        "scroll down a screen at a time to the very bottom",
    ]),
    ("artist", "any artist page", [
        "the top",
        "scroll down a screen at a time to the very bottom",
        "Popular, after tapping See more",
        "the discography page (Show all)",
    ]),
    ("player", "tap the now playing bar to open the full screen player", [
        "the player while playing",
        "the player paused",
        "scroll down through every card to the very bottom",
        "a track with a Canvas video, if you come across one",
    ]),
    ("lyrics", "open the lyrics from the player", [
        "the lyrics page",
        "scrolled by hand",
    ]),
    ("queue", "open the queue from the player", [
        "the top",
        "scrolled",
    ]),
]

CHECKLIST = """Before recording, the phone needs:
  1. the FLEX build of the mod on it: make install FLEX=1 (only that build serves the tree)
  2. stock Spotify: Mod Settings → Mod → Export settings (keep the file), then Reset all settings.
     Spotify restarts with every switch off; close the welcome tour if it comes up.
     Afterwards, Mod Settings → Mod → Import settings brings your settings back.
  3. Spotify open in the foreground, the phone unlocked and on USB."""

HELP = """  Enter         save a snapshot of what the phone shows
  words + Enter save a snapshot with those words in its name ("scrolled", "see more")
  n / b         next screen / the screen before
  j <screen>    jump to a screen by name or number (a screen's name alone jumps too)
  u             take back the last snapshot saved on this screen
  r             delete every snapshot of this screen (asks first)
  l             what is recorded so far
  q             quit"""

NUMBERED = re.compile(r"^(\d+)(?: (.*))?\.txt$")
UNSAFE = re.compile(r"[^\w\- ]+")


def shown(path):
    """A path as the user reads it: relative to the repo when it is inside it."""
    relative = os.path.relpath(path, ROOT)
    return path if relative.startswith("..") else relative


def ask(prompt):
    try:
        return input(prompt).strip()
    except EOFError:
        return "q"


def mod_state(text):
    """(clean, reason) from the tree's "== mod" section; clean is None for a build without one."""
    lines = text.split("\n")
    try:
        start = lines.index("== mod")
    except ValueError:
        return None, "the build on the phone does not report the mod's settings; reinstall with make install FLEX=1"
    stock, dirty = False, []
    for line in lines[start + 1:]:
        if line.startswith("== "):
            break
        if line.startswith("stock "):
            stock = line.split(" ", 1)[1].strip() == "yes"
            continue
        key, sep, value = line.partition(" = ")
        if not sep:
            continue
        value = value.strip()
        if key.startswith("spotifyglass.flag."):
            dirty.append(f"flag {key[len('spotifyglass.flag.'):]} forced {value}")
        elif value.startswith(("list:", "map:")):
            if not value.endswith(":0"):
                dirty.append(f"{key} ({value})")
        elif re.fullmatch(r"-?\d+(\.\d+)?", value):
            if float(value) > 0:
                dirty.append(f"{key} = {value}")
    if not stock:
        dirty.insert(0, "Reset all settings has not been run, so every switch that defaults to on is on")
    return not dirty, "; ".join(dirty)


class Screen:
    def __init__(self, index, name, hint, states, folder):
        self.index, self.name, self.hint, self.states = index, name, hint, states
        self.folder = os.path.join(folder, name)
        self.saved = []   # paths saved by this run, newest last, for u

    def snapshots(self):
        if not os.path.isdir(self.folder):
            return []
        found = []
        for entry in os.listdir(self.folder):
            m = NUMBERED.match(entry)
            if m:
                found.append((int(m.group(1)), os.path.join(self.folder, entry)))
        return [path for _, path in sorted(found)]

    def next_number(self):
        numbers = [int(NUMBERED.match(os.path.basename(p)).group(1)) for p in self.snapshots()]
        return max(numbers, default=0) + 1


def header_of(path):
    info = {}
    with open(path, errors="replace") as f:
        for line in f:
            if not line.startswith("# ") or line.startswith("# tree:"):
                break
            key, _, value = line[2:].rstrip("\n").partition(": ")
            info[key] = value
    return info


def write_index(folder, screens):
    lines = [f"# Clean view trees, recorded with scripts/record-session.py. Written {datetime.datetime.now():%Y-%m-%d %H:%M}.", ""]
    names = [s.name for s in screens]
    others = sorted(d for d in os.listdir(folder) if os.path.isdir(os.path.join(folder, d)) and d not in names) if os.path.isdir(folder) else []
    for screen in screens + [Screen(0, d, "", [], folder) for d in others]:
        paths = screen.snapshots()
        if not paths:
            continue
        lines.append(f"{screen.name}/")
        for path in paths:
            info = header_of(path)
            lines.append(f"  {os.path.basename(path):<28} {info.get('recorded', ''):<28} mod: {info.get('mod', '?'):<10} {info.get('shape', '')}")
        lines.append("")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "INDEX.txt"), "w") as f:
        f.write("\n".join(lines))


def fetch_tree(url, attempts=1):
    for attempt in range(attempts):
        try:
            text = recorder.fetch(url)
            if "== window" in text:
                return text, None
            error = "the phone answered, but not with a tree"
        except Exception as e:   # the tunnel may still be coming up, or Spotify is in the background
            error = str(e)
        if attempt + 1 < attempts:
            time.sleep(1)
    return None, error


def save(screen, url, note, last_hash):
    text, error = fetch_tree(url)
    if text is None:
        print(f"    could not get the tree ({error}).")
        print("    Spotify (the FLEX build) must be in the foreground, the phone unlocked and on USB; press Enter to try again.")
        return last_hash
    digest = hashlib.sha1(text.encode()).hexdigest()
    if digest == last_hash:
        print("    the same tree as the snapshot before, not saved (the screen has not changed yet?)")
        return last_hash
    clean, reason = mod_state(text)
    os.makedirs(screen.folder, exist_ok=True)
    number = screen.next_number()
    label = UNSAFE.sub("", note).strip()[:40]
    path = os.path.join(screen.folder, f"{number:02d}{' ' + label if label else ''}.txt")
    mod = "clean" if clean else ("unknown" if clean is None else "NOT CLEAN")
    with open(path, "w") as f:
        f.write(f"# screen: {screen.name}\n")
        f.write(f"# snapshot: {number}{' (' + label + ')' if label else ''}\n")
        f.write(f"# recorded: {datetime.datetime.now():%Y-%m-%d %H:%M:%S} via usb\n")
        f.write(f"# mod: {mod}\n")
        if reason:
            f.write(f"# mod detail: {reason}\n")
        f.write(f"# shape: {recorder.describe(text)}\n")
        f.write("# tree:\n" + text + ("" if text.endswith("\n") else "\n"))
    screen.saved.append(path)
    print(f"    saved {shown(path)}: {text.count(chr(10))} lines, mod {mod}")
    if clean is False:
        print(f"    ⚠ not stock Spotify: {reason}")
    elif clean is None:
        print(f"    ⚠ {reason}")
    return digest


def show_progress(screens, current=None):
    print()
    for screen in screens:
        count = len(screen.snapshots())
        mark = "▶" if screen is current else " "
        print(f"  {mark} {screen.index:2d}. {screen.name:<13} {count:>3} snapshot{'s' if count != 1 else ' '}   {screen.hint}")
    print()


def introduce(screen, total):
    print(f"\n━━ {screen.index}/{total}  now record: {screen.name.upper()} ━━")
    print(f"  go to {screen.hint}")
    if screen.states:
        print("  worth a snapshot each:")
        for state in screen.states:
            print(f"    · {state}")
    existing = len(screen.snapshots())
    if existing:
        print(f"  {existing} already recorded here; new ones are numbered from {screen.next_number()} (r clears them)")
    print("  Enter saves, words + Enter saves with a name, a screen's name jumps there, n next, b back, h help")


def run(screens, url, folder):
    position, last_hash = 0, None
    introduce(screens[0], len(screens))
    while True:
        screen = screens[position]
        answer = ask(f"  {screen.name} > ")
        command = answer.lower()
        if command == "q":
            return
        if command in ("h", "?", "help"):
            print(HELP)
        elif command == "n" or command == "b":
            step = 1 if command == "n" else -1
            if not 0 <= position + step < len(screens):
                if command == "n":
                    print("  that was the last screen: q quits, b goes back, j <screen> jumps")
                continue
            position += step
            last_hash = None
            introduce(screens[position], len(screens))
        elif command.startswith("j ") or command == "j" or command in [s.name for s in screens]:
            target = command[1:].strip() if command.startswith("j") and command not in [s.name for s in screens] else command
            match = [s for s in screens if s.name == target or str(s.index) == target]
            if not match:
                print(f"  no screen {target!r}; l lists them")
                continue
            position = screens.index(match[0])
            last_hash = None
            introduce(screens[position], len(screens))
        elif command == "l":
            show_progress(screens, screen)
        elif command == "u":
            if not screen.saved:
                print("  nothing saved on this screen in this run to take back")
                continue
            path = screen.saved.pop()
            if os.path.exists(path):
                os.remove(path)
            last_hash = None
            print(f"    removed {shown(path)}")
        elif command == "r":
            paths = screen.snapshots()
            if not paths:
                print("  nothing recorded on this screen")
                continue
            if ask(f"  delete all {len(paths)} snapshots of {screen.name}? [y/N] ").lower() == "y":
                for path in paths:
                    os.remove(path)
                screen.saved.clear()
                last_hash = None
                print("    cleared")
        elif command in [name for name, _, _ in SESSION]:
            print(f"  {command} is not in this run; start the script without screen names to have every screen")
            continue
        elif len(command) == 1:
            print("  not a command; h lists them (a name for a snapshot needs two letters or more)")
            continue
        else:
            last_hash = save(screen, url, answer, last_hash)
        write_index(folder, screens)


def main():
    args = sys.argv[1:]
    folder = os.path.join(ROOT, "trees", "clean")
    url, listing, wanted = None, False, []
    while args:
        arg = args.pop(0)
        if arg in ("-h", "--help"):
            sys.exit(__doc__)
        elif arg == "-o" and args:
            folder = os.path.abspath(args.pop(0))
        elif arg == "--url" and args:
            url = args.pop(0)
        elif arg == "--list":
            listing = True
        elif arg.startswith("-"):
            sys.exit(__doc__)
        else:
            wanted.append(arg.lower())

    names = [name for name, _, _ in SESSION]
    unknown = [w for w in wanted if w not in names]
    if unknown:
        sys.exit(f"unknown screen {', '.join(unknown)}; the session has: {', '.join(names)}")
    chosen = [entry for entry in SESSION if not wanted or entry[0] in wanted]
    screens = [Screen(i, name, hint, states, folder) for i, (name, hint, states) in enumerate(chosen, 1)]

    if listing:
        print(f"trees in {shown(folder)}/")
        show_progress(screens)
        return

    tunnel = None
    if url is None:
        if subprocess.run(["idevice_id", "-l"], capture_output=True, text=True).stdout.strip() == "":
            sys.exit("no iPhone on USB: plug it in, unlock it, tap Trust if asked, then run again")
        tunnel = subprocess.Popen(["iproxy", f"{PORT}:{PORT}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        url = f"http://127.0.0.1:{PORT}/tree"

    try:
        print(CHECKLIST)
        while True:
            text, error = fetch_tree(url, attempts=4)
            if text is not None:
                break
            print(f"\n  the phone is not answering yet ({error}).")
            if ask("  press Enter to try again, q to quit > ").lower() == "q":
                return
        clean, reason = mod_state(text)
        if clean:
            print("\n  ✓ the phone answers, and the mod is at stock: every snapshot will be Spotify as it came")
        else:
            print(f"\n  ⚠ the phone answers, but {'the mod is not at stock' if clean is False else 'the mod state is unknown'}: {reason}")
            print("  snapshots are still saved and marked NOT CLEAN; see step 2 above to make them clean")
        run(screens, url, folder)
    except KeyboardInterrupt:
        print()
    finally:
        if tunnel:
            tunnel.terminate()
        write_index(folder, screens)
    print(f"done, trees are in {shown(folder)}/ (INDEX.txt lists them)")


if __name__ == "__main__":
    main()
