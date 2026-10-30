#!/usr/bin/env python3
"""Refresh PwEevee's Chroma upstream metadata from the official website.

Chroma is a separate upstream project with an official browser-based patcher.
PwEevee does not bundle it, mirror it, or package it as a .deb.  The only
supported source of public version information is:

    https://chroma.pw/patch

The installation page publishes a recommended release and its supported
Spotify version.  This tool selects the entry marked ``recommended``, records
the source URL and successful check time, and writes the result atomically.

If the page cannot be fetched or parsed, the metadata is marked
``status: unavailable`` with null current-version fields.  The previous
successful values are retained only under ``last_success`` so they cannot be
mistaken for the current release.

Usage:
    python3 PwEvevee/build-system/release/check-chroma-version.py
    python3 PwEvevee/build-system/release/check-chroma-version.py --check
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sys
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_METADATA = ROOT / "upstream" / "chroma.json"
DEFAULT_SOURCE = "https://chroma.pw/patch"
HOMEPAGE = "https://chroma.pw/"
USER_AGENT = "PwEevee-Chroma-Version/1.0 (+https://github.com/codeboy2012/PwEevee)"
MAX_PAGE_BYTES = 2 * 1024 * 1024

VERSION = r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?"
SPOTIFY_VERSION = r"\d+\.\d+\.\d+"

DISPLAY_VERSION_RE = re.compile(
    r"Chroma\s*(?:<!--\s*-->)?\s*v?(" + VERSION + r")"
)
DISPLAY_SPOTIFY_RE = re.compile(
    r"for Spotify\s*(?:<!--\s*-->)?\s*(" + SPOTIFY_VERSION + r")"
)
RECOMMENDED_RE = re.compile(
    r'\{"tag":"[^"]+","version":"(?P<version>' + VERSION + r')",'
    r'"prerelease":(?:true|false),"date":"[^"]+","size":\d+,'
    r'"spotify":"(?P<spotify>' + SPOTIFY_VERSION + r')",'
    r'"recommended":true\}'
)


class FetchError(RuntimeError):
    """The official page could not be fetched."""


class PageError(RuntimeError):
    """The official page did not contain one unambiguous release."""


class MetadataError(RuntimeError):
    """The local metadata file is malformed."""


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace(
        "+00:00", "Z"
    )


def normalize_version(value: str) -> str:
    value = value.strip()
    if value.startswith(("v", "V")):
        value = value[1:]
    if not re.fullmatch(VERSION, value):
        raise PageError(f"invalid Chroma version: {value!r}")
    return value


def fetch_page(url: str, timeout: float) -> str:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = getattr(response, "status", 200)
            if status != 200:
                raise FetchError(f"{url} returned HTTP {status}")
            raw = response.read(MAX_PAGE_BYTES + 1)
            if len(raw) > MAX_PAGE_BYTES:
                raise FetchError(f"{url} exceeded {MAX_PAGE_BYTES} bytes")
            charset = response.headers.get_content_charset() or "utf-8"
            return raw.decode(charset, errors="replace")
    except FetchError:
        raise
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        raise FetchError(f"could not fetch {url}: {exc}") from exc


def parse_page(page: str) -> tuple[str, str]:
    """Return (Chroma version, supported Spotify version).

    The page is a Next.js document.  It displays the recommended release in
    visible text and also embeds the same release in its serialized data.  We
    prefer the structured ``recommended: true`` entry, but require it to agree
    with any visible version when both are present.
    """
    decoded = html.unescape(page).replace('\\"', '"')

    display_versions = sorted(
        {normalize_version(v) for v in DISPLAY_VERSION_RE.findall(decoded)}
    )
    display_spotify = sorted(set(DISPLAY_SPOTIFY_RE.findall(decoded)))
    structured = sorted(
        {
            (normalize_version(match.group("version")), match.group("spotify"))
            for match in RECOMMENDED_RE.finditer(decoded)
        }
    )

    if len(display_versions) > 1:
        raise PageError(
            "multiple Chroma versions are displayed: "
            + ", ".join(display_versions)
        )
    if len(display_spotify) > 1:
        raise PageError(
            "multiple Spotify versions are displayed: "
            + ", ".join(display_spotify)
        )
    if len(structured) > 1:
        raise PageError("multiple recommended Chroma releases are published")

    if structured:
        version, spotify = structured[0]
        if display_versions and display_versions[0] != version:
            raise PageError(
                "displayed Chroma version "
                f"{display_versions[0]} disagrees with recommended {version}"
            )
        if display_spotify and display_spotify[0] != spotify:
            raise PageError(
                "displayed Spotify version "
                f"{display_spotify[0]} disagrees with recommended {spotify}"
            )
        return version, spotify

    if len(display_versions) == 1 and len(display_spotify) == 1:
        return display_versions[0], display_spotify[0]

    raise PageError("could not find a recommended Chroma and Spotify version")


def base_metadata() -> dict:
    return {
        "schema": 1,
        "name": "Chroma",
        "kind": "upstream-patcher",
        "homepage": HOMEPAGE,
        "source_url": DEFAULT_SOURCE,
        "distribution": "official-browser-patcher",
        "bundled": False,
        "deb": None,
        "status": "unavailable",
        "version": None,
        "spotify_version": None,
        "checked_at": None,
        "last_success": None,
        "error": "not checked yet",
    }


def load_metadata(path: Path) -> dict:
    if not path.exists():
        return base_metadata()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise MetadataError(f"cannot read {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise MetadataError(f"{path} must contain a JSON object")
    return data


def last_success_from(meta: dict) -> dict | None:
    previous = meta.get("last_success")
    if isinstance(previous, dict) and previous.get("version") and previous.get(
        "spotify_version"
    ):
        return dict(previous)
    if (
        meta.get("status") == "current"
        and meta.get("version")
        and meta.get("spotify_version")
    ):
        return {
            "version": meta["version"],
            "spotify_version": meta["spotify_version"],
            "checked_at": meta.get("checked_at"),
            "source_url": meta.get("source_url", DEFAULT_SOURCE),
        }
    return None


def write_metadata(path: Path, meta: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(
        prefix=path.name + ".", suffix=".tmp", dir=path.parent
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(meta, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def refresh(
    metadata_path: Path = DEFAULT_METADATA,
    source_url: str = DEFAULT_SOURCE,
    html_path: Path | None = None,
    timeout: float = 20.0,
    now: str | None = None,
    write: bool = True,
) -> tuple[dict, str | None, tuple[str, str] | None]:
    """Fetch and record the current Chroma release.

    Returns (metadata, previous_current_version, detected_pair).  A network or
    parse failure is recorded as ``unavailable`` and does not raise.
    """
    existing = load_metadata(metadata_path)
    previous_version = (
        existing.get("version") if existing.get("status") == "current" else None
    )
    checked_at = now or utc_now()

    try:
        if html_path is not None:
            page = html_path.read_text(encoding="utf-8")
        else:
            page = fetch_page(source_url, timeout)
        version, spotify = parse_page(page)
    except (FetchError, PageError, OSError) as exc:
        meta = dict(base_metadata())
        meta.update(existing)
        meta.update(
            {
                "source_url": source_url,
                "status": "unavailable",
                "version": None,
                "spotify_version": None,
                "checked_at": checked_at,
                "last_success": last_success_from(existing),
                "error": str(exc)[:500],
            }
        )
        if write:
            write_metadata(metadata_path, meta)
        return meta, previous_version, None

    last_success = {
        "version": version,
        "spotify_version": spotify,
        "checked_at": checked_at,
        "source_url": source_url,
    }
    meta = dict(base_metadata())
    meta.update(existing)
    meta.update(
        {
            "source_url": source_url,
            "status": "current",
            "version": version,
            "spotify_version": spotify,
            "checked_at": checked_at,
            "last_success": last_success,
            "error": None,
        }
    )
    if write:
        write_metadata(metadata_path, meta)
    return meta, previous_version, (version, spotify)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Refresh Chroma version metadata from https://chroma.pw/patch"
    )
    parser.add_argument(
        "--metadata",
        type=Path,
        default=DEFAULT_METADATA,
        help=f"metadata file (default: {DEFAULT_METADATA})",
    )
    parser.add_argument(
        "--source",
        default=DEFAULT_SOURCE,
        help=f"installation page (default: {DEFAULT_SOURCE})",
    )
    parser.add_argument(
        "--html",
        type=Path,
        help="parse a saved installation page instead of fetching it",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=20.0,
        help="network timeout in seconds (default: 20)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="compare without writing the metadata file",
    )
    args = parser.parse_args(argv)

    try:
        meta, previous, _ = refresh(
            metadata_path=args.metadata,
            source_url=args.source,
            html_path=args.html,
            timeout=args.timeout,
            write=not args.check,
        )
    except MetadataError as exc:
        print(f"chroma: {exc}", file=sys.stderr)
        return 1

    if meta["status"] == "current":
        label = (
            f"Chroma {meta['version']} for Spotify {meta['spotify_version']}"
        )
        if previous and previous != meta["version"]:
            action = "would update" if args.check else "updated"
            print(f"{label} — {action} from {previous}")
        else:
            print(f"{label} — current")
        return 0

    print(f"chroma: unavailable: {meta['error']}", file=sys.stderr)
    last = meta.get("last_success")
    if isinstance(last, dict) and last.get("version"):
        print(
            "last successful check: Chroma "
            f"{last['version']} for Spotify {last['spotify_version']} "
            f"at {last.get('checked_at') or 'unknown time'}",
            file=sys.stderr,
        )
    print("Chroma version information is temporarily unavailable.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
