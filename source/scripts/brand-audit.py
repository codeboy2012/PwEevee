#!/usr/bin/env python3
"""Audit PwEevee for legacy Taurus / spoti.pw / chroma.pw branding.

Every hit is classified. Anything that is not explicitly allowed fails the audit,
so a new legacy string cannot slip in silently.

    python3 scripts/brand-audit.py                     # source tree
    python3 scripts/brand-audit.py --ipa out/PwEevee.ipa
    python3 scripts/brand-audit.py --json report.json --md docs/brand-audit.md

Allowed categories:

  attribution        required credit or licence notice for upstream code
  historical         release notes / changelog that describe the past
  compatibility      identifiers or on-disk paths an existing install still owns
  upstream           infrastructure that belongs to the upstream project
  internal-docs      reverse-engineering notes that never ship in the product

Exit status: 0 when every hit is classified, 1 when any hit is "legacy".
"""

import argparse
import fnmatch
import json
import os
import re
import sys
import zipfile

# --------------------------------------------------------------------------
# What counts as legacy branding.

TERMS = re.compile(
    r"(?<![A-Za-z])(taurus|terus|spotipw|samj-exe|natasha|arnaupq|pulse-ice|discord\.gg)"
    r"|chroma\.pw|spoti\.pw",
    re.IGNORECASE,
)

# --------------------------------------------------------------------------
# Explicit decisions. Order matters: the first matching rule wins.
#   pattern  regex matched against the hit itself
#   path     regex matched against the forward-slash relative path
#   line     optional regex matched against the whole line
#   binary   True when the hit came from strings(1)-style extraction

RULES = [
    # -- required attribution ------------------------------------------------
    dict(pattern=r"chroma\.pw", path=r"^README\.md$", line=r"licensed under GPL-3\.0",
         category="attribution",
         reason="GPL-3.0 notice for the upstream source this project derives from"),
    dict(pattern=r"chroma\.pw|spoti\.pw", path=r"^README\.md$", line=r"derives from the open-source",
         category="attribution", reason="upstream credit required by the GPL lineage"),
    dict(pattern=r"spoti\.pw", path=r"^LICENSE$",
         category="attribution", reason="required copyright notice"),
    dict(pattern=r"spoti\.pw", path=r"^CLA\.md$",
         category="attribution", reason="contributor agreement names the upstream project"),
    dict(pattern=r"chroma\.pw|spoti\.pw", path=r"^(altstore-source|esign-source)\.json$",
         category="attribution", reason="distribution description credits the upstream project"),
    dict(pattern=r"pulse-ice", path=r"^(docs/tweaks\.md|README\.md)$",
         category="attribution", reason="credit for an adapted third-party visual treatment"),

    # -- history -------------------------------------------------------------
    dict(pattern=r".", path=r"^CHANGELOG\.md$",
         category="historical", reason="release history for versions that shipped under the old name"),

    # -- compatibility: identifiers an existing install still carries --------
    dict(pattern=r"taurus", path=r"^tweak/Sources/App/About/Update\.m$",
         line=r"spotifyglass\.update\.taurus\.latest",
         category="compatibility",
         reason="one-time migration read of the pre-rename update-check preference; removed after reading"),
    dict(pattern=r"taurus", path=r"^tweak/Sources/App/ModSettings\.x$",
         category="compatibility",
         reason="compares against the badge text a pre-rename install may still have stored"),
    dict(pattern=r"taurus", path=r"^tweak/Sources/Shared/LyricsSources/SpicyLyrics\.m$",
         category="compatibility",
         reason="legacy UserDefaults key holding the user's saved SpicyLyrics token"),
    dict(pattern=r"taurus", path=r"^tweak/Sources/Shared/LyricsTranslation/LyricsTranslation\.m$",
         category="compatibility",
         reason="legacy UserDefaults key holding the user's saved Gemini token"),
    dict(pattern=r"taurus-spotify-mod", path=r"^tweak/Sources/Shared/Concerts/Concerts\.m$",
         category="compatibility",
         reason="Bandsintown app id issued to this project upstream; renaming it would be rejected by the API"),
    dict(pattern=r"taurus", path=r"^tweak/Sources/Shared/Concerts/Concerts\.m$",
         category="compatibility", reason="comment documenting the upstream-issued app id"),

    # -- compatibility: on-disk data namespace ------------------------------
    dict(pattern=r"spoti\.pw", path=r"^tweak/Sources/.*\.(m|x|h)$",
         category="compatibility",
         reason="existing on-disk data root (effects, lyrics, translations, stats); renaming it without a migration would orphan user data"),
    dict(pattern=r"spoti\.pw", path=r"^tweak/Sources/.*\.(m|x|h)$",
         category="compatibility",
         reason="existing on-disk data root retained for upgrade compatibility"),
    dict(pattern=r"spoti\.pw", path=r"^harness/.*\.m$",
         category="compatibility", reason="harness mirrors the production on-disk data root"),
    dict(pattern=r"spoti\.pw", path=r"^docs/tweaks\.md$",
         category="compatibility", reason="documented on-disk data root"),

    # -- upstream infrastructure / internal notes ---------------------------
    dict(pattern=r"spoti\.pw", path=r"^\.github/workflows/cla\.yml$",
         category="upstream",
         reason="upstream CLA bot guard; the workflow is inert in this repository"),
    dict(pattern=r".", path=r"^\.github/workflows/cla\.yml$",
         category="upstream", reason="upstream CLA automation"),
    dict(pattern=r"spoti\.pw", path=r"^tweak/Sources/App/About/SGUpdateChannels\.m$",
         category="historical",
         reason="comment quoting real release titles used as parser regression evidence"),
    dict(pattern=r".", path=r"^(\.agents|\.claude)/.*$",
         category="internal-docs",
         reason="reverse-engineering notes kept outside the shipped product"),

    # -- binary compatibility strings ---------------------------------------
    dict(pattern=r"spoti\.pw", path=r"spotifyglass\.dylib$", binary=True,
         category="compatibility", reason="existing on-disk data root retained for user-data compatibility"),
    dict(pattern=r"spotifyglass\.update\.taurus\.latest", path=r"spotifyglass\.dylib$", binary=True,
         category="compatibility", reason="one-time update-preference migration key"),
    dict(pattern=r"taurus-spotify-mod", path=r"spotifyglass\.dylib$", binary=True,
         category="compatibility", reason="upstream-issued concerts API app id"),
    dict(pattern=r"^Taurus$", path=r"spotifyglass\.dylib$", binary=True,
         category="compatibility", reason="legacy badge value read from old installs"),
    dict(pattern=r"^Taurus\.(Gemini|SpicyLyrics)$", path=r"spotifyglass\.dylib$", binary=True,
         category="compatibility", reason="legacy token keys read from old installs"),
    dict(pattern=r"^spotifyglass\.update\.taurus\.latest$", path=r"spotifyglass\.dylib$", binary=True,
         category="compatibility", reason="one-time update-preference migration key"),
    dict(pattern=r"^taurus-spotify-mod$", path=r"spotifyglass\.dylib$", binary=True,
         category="compatibility", reason="upstream-issued concerts API app id"),
]

SKIP_DIRS = {
    ".git", "__pycache__", ".theos", "packages", "out", "node_modules",
    "vendor/audio/wdl", "vendor/audio/libbs2b", "vendor/audio/eel2-parser",
}
SKIP_EXT = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".pdf", ".ipa", ".deb", ".zip",
    ".dylib", ".a", ".o", ".mlmodel", ".mlmodelc", ".ttf", ".otf", ".woff",
    ".woff2", ".mp3", ".m4a", ".mp4", ".mov", ".ico", ".icns", ".plist.bin",
}


def rel(root, path):
    return os.path.relpath(path, root).replace(os.sep, "/")


def is_binary(data):
    return b"\x00" in data[:4096]


def printable_runs(data, minimum=6):
    """A small `strings` replacement that works on every host."""
    runs, current = [], bytearray()
    for byte in data:
        if 32 <= byte < 127 or byte == 9:
            current.append(byte)
        else:
            if len(current) >= minimum:
                runs.append(current.decode("ascii", "replace"))
            current = bytearray()
    if len(current) >= minimum:
        runs.append(current.decode("ascii", "replace"))
    return runs


def classify(path, line, context, binary=False):
    for rule in RULES:
        if rule.get("binary", False) != binary:
            continue
        if not re.search(rule["pattern"], context, re.IGNORECASE if not rule.get("binary") else 0):
            continue
        if not re.search(rule["path"], path):
            continue
        if "line" in rule and not re.search(rule["line"], line):
            continue
        return rule["category"], rule["reason"]
    return "legacy", "unclassified legacy branding"


def add_hit(result, path, line_no, line, term, binary=False, context=None):
    category, reason = classify(path, line, context if context is not None else line, binary)
    result["hits"].append({
        "path": path,
        "line": line_no,
        "term": term,
        "category": category,
        "reason": reason,
    })


def scan_text(result, path, text, display):
    for number, line in enumerate(text.splitlines(), 1):
        for match in TERMS.finditer(line):
            add_hit(result, display, number, line.strip(), match.group(0))


def scan_source(root, result):
    for base, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in {".git", "__pycache__", ".theos", "packages", "out", "node_modules"})
        display_base = rel(root, base)
        if any(display_base == d or display_base.startswith(d + "/") for d in SKIP_DIRS):
            continue
        for name in sorted(files):
            path = os.path.join(base, name)
            display = rel(root, path)
            if name.endswith(".pyc") or display in {
                "scripts/brand-audit.py", "docs/brand-audit.md", "docs/brand-audit.json",
            }:
                continue
            if any(display.startswith(d + "/") for d in SKIP_DIRS):
                continue
            if os.path.splitext(name)[1].lower() in SKIP_EXT:
                continue
            try:
                data = open(path, "rb").read()
            except OSError:
                continue
            if is_binary(data):
                continue
            scan_text(result, path, data.decode("utf-8", "ignore"), display)


def scan_ipa(ipa, result):
    with zipfile.ZipFile(ipa) as archive:
        for info in archive.infolist():
            if info.is_dir():
                continue
            name = info.filename
            lower = name.lower()
            if lower.endswith((".dylib", "/spotify", ".appex/")):
                data = archive.read(info)
                for run in printable_runs(data):
                    for match in TERMS.finditer(run):
                        add_hit(result, name, 0, run, match.group(0), binary=True, context=run)
                continue
            if not lower.endswith((".plist", ".json", ".strings", ".js", ".html", ".css", ".txt")):
                continue
            try:
                text = archive.read(info).decode("utf-8", "ignore")
            except Exception:
                continue
            scan_text(result, name, text, name)


def summarise(result):
    counts = {}
    for hit in result["hits"]:
        counts[hit["category"]] = counts.get(hit["category"], 0) + 1
    result["counts"] = counts
    result["ok"] = counts.get("legacy", 0) == 0


def write_markdown(result, path):
    lines = [
        "# PwEevee branding audit",
        "",
        f"Source root: `{result['root']}`  ",
        f"IPA: `{result['ipa'] or 'not scanned'}`  ",
        f"Result: **{'PASS' if result['ok'] else 'FAIL'}**",
        "",
        "| Category | Hits |",
        "|---|---|",
    ]
    for category in ("attribution", "historical", "compatibility", "upstream", "internal-docs", "legacy"):
        lines.append(f"| {category} | {result['counts'].get(category, 0)} |")
    lines += ["", "## Hits", "", "| file | line | term | category | reason |", "|---|---|---|---|---|"]
    for hit in result["hits"]:
        term = hit["term"].replace("|", "\\|")
        reason = hit["reason"].replace("|", "\\|")
        lines.append(f"| `{hit['path']}` | {hit['line'] or '-'} | `{term}` | {hit['category']} | {reason} |")
    lines += ["", "A `legacy` row is a failure: the string is product-facing or unowned and must be fixed.", ""]
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    open(path, "w", encoding="utf-8").write("\n".join(lines))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--ipa")
    parser.add_argument("--json")
    parser.add_argument("--md")
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    result = {"root": root, "ipa": args.ipa, "hits": [], "counts": {}, "ok": False}
    scan_source(root, result)
    if args.ipa:
        scan_ipa(args.ipa, result)
    summarise(result)

    print(f"brand-audit: {len(result['hits'])} hits — " + ", ".join(f"{k}={v}" for k, v in sorted(result['counts'].items())))
    for hit in result["hits"]:
        if hit["category"] == "legacy":
            print(f"LEGACY {hit['path']}:{hit['line']} {hit['term']}")

    if args.json:
        os.makedirs(os.path.dirname(os.path.abspath(args.json)), exist_ok=True)
        json.dump(result, open(args.json, "w", encoding="utf-8"), indent=2)
    if args.md:
        write_markdown(result, args.md)

    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
