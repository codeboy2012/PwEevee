import importlib.util
import json
import re
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "build-system" / "release" / "check-chroma-version.py"

spec = importlib.util.spec_from_file_location("check_chroma_version", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

PAGE = r"""<!doctype html>
<html><body>
<span>Chroma <!-- -->0.51.0</span>
<span>for Spotify <!-- -->9.1.90</span>
<script>self.__next_f.push([1,"{\"versions\":[{\"tag\":\"v1.0.0-beta.6\",\"version\":\"1.0.0-beta.6\",\"prerelease\":true,\"date\":\"2026-10-29T18:22:32Z\",\"size\":91704910,\"spotify\":\"9.1.90\",\"recommended\":false},{\"tag\":\"v0.51.0\",\"version\":\"0.51.0\",\"prerelease\":false,\"date\":\"2026-10-14T10:35:30Z\",\"size\":2804017,\"spotify\":\"9.1.90\",\"recommended\":true}]}"])</script>
</body></html>
"""

DISPLAY_ONLY = """
<span>Chroma <!-- -->0.51.0</span>
<span>for Spotify <!-- -->9.1.90</span>
"""

MISMATCH_PAGE = r"""
<span>Chroma <!-- -->0.51.0</span>
<span>for Spotify <!-- -->9.1.90</span>
<script>self.__next_f.push([1,"{\"versions\":[{\"tag\":\"v0.50.0\",\"version\":\"0.50.0\",\"prerelease\":false,\"date\":\"2026-10-14T10:35:30Z\",\"size\":2804017,\"spotify\":\"9.1.90\",\"recommended\":true}]}"])</script>
"""


class ChromaVersionTests(unittest.TestCase):
    def test_selects_recommended_release_and_ignores_beta(self):
        version, spotify = module.parse_page(PAGE)
        self.assertEqual(version, "0.51.0")
        self.assertEqual(spotify, "9.1.90")

    def test_falls_back_to_visible_text(self):
        version, spotify = module.parse_page(DISPLAY_ONLY)
        self.assertEqual((version, spotify), ("0.51.0", "9.1.90"))

    def test_rejects_display_and_structured_mismatch(self):
        with self.assertRaises(module.PageError):
            module.parse_page(MISMATCH_PAGE)

    def test_rejects_missing_version(self):
        with self.assertRaises(module.PageError):
            module.parse_page("<html><body>Chroma</body></html>")

    def test_success_writes_current_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            page = root / "patch.html"
            metadata = root / "chroma.json"
            page.write_text(PAGE, encoding="utf-8")

            result, previous, detected = module.refresh(
                metadata_path=metadata,
                html_path=page,
                now="2026-10-30T03:20:00Z",
            )

            self.assertEqual(detected, ("0.51.0", "9.1.90"))
            self.assertIsNone(previous)
            self.assertEqual(result["status"], "current")
            self.assertEqual(result["version"], "0.51.0")
            self.assertEqual(result["spotify_version"], "9.1.90")
            self.assertEqual(result["last_success"]["version"], "0.51.0")
            self.assertIsNone(result["error"])
            self.assertEqual(
                json.loads(metadata.read_text(encoding="utf-8")),
                result,
            )

    def test_update_reports_the_previous_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            page = root / "patch.html"
            metadata = root / "chroma.json"
            page.write_text(PAGE, encoding="utf-8")
            seed = module.base_metadata()
            seed.update(
                {
                    "status": "current",
                    "version": "0.50.0",
                    "spotify_version": "9.1.90",
                    "checked_at": "2026-10-29T00:00:00Z",
                    "error": None,
                }
            )
            metadata.write_text(json.dumps(seed), encoding="utf-8")

            result, previous, detected = module.refresh(
                metadata_path=metadata,
                html_path=page,
                now="2026-10-30T03:23:00Z",
            )

            self.assertEqual(previous, "0.50.0")
            self.assertEqual(detected, ("0.51.0", "9.1.90"))
            self.assertEqual(result["status"], "current")
            self.assertEqual(result["version"], "0.51.0")

    def test_failure_marks_unavailable_and_keeps_last_success_historical(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            page = root / "patch.html"
            metadata = root / "chroma.json"
            page.write_text("<html><body>Chroma changed</body></html>", encoding="utf-8")
            seed = module.base_metadata()
            seed.update(
                {
                    "status": "current",
                    "version": "0.50.0",
                    "spotify_version": "9.1.90",
                    "checked_at": "2026-10-29T00:00:00Z",
                    "last_success": {
                        "version": "0.50.0",
                        "spotify_version": "9.1.90",
                        "checked_at": "2026-10-29T00:00:00Z",
                        "source_url": module.DEFAULT_SOURCE,
                    },
                    "error": None,
                }
            )
            metadata.write_text(json.dumps(seed), encoding="utf-8")

            result, previous, detected = module.refresh(
                metadata_path=metadata,
                html_path=page,
                now="2026-10-30T03:21:00Z",
            )

            self.assertIsNone(detected)
            self.assertEqual(previous, "0.50.0")
            self.assertEqual(result["status"], "unavailable")
            self.assertIsNone(result["version"])
            self.assertIsNone(result["spotify_version"])
            self.assertEqual(result["last_success"]["version"], "0.50.0")
            self.assertIn("could not find", result["error"])
            self.assertEqual(
                json.loads(metadata.read_text(encoding="utf-8")),
                result,
            )

    def test_fetch_failure_also_marks_unavailable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            metadata = root / "chroma.json"
            original = module.fetch_page

            def fail(*_args, **_kwargs):
                raise module.FetchError("network unavailable")

            module.fetch_page = fail
            try:
                result, _previous, detected = module.refresh(
                    metadata_path=metadata,
                    now="2026-10-30T03:22:00Z",
                    write=False,
                )
            finally:
                module.fetch_page = original

            self.assertIsNone(detected)
            self.assertEqual(result["status"], "unavailable")
            self.assertIsNone(result["version"])
            self.assertFalse(metadata.exists())

    def test_repository_metadata_is_distinct_and_has_no_deb(self):
        metadata = json.loads(
            (ROOT / "upstream" / "chroma.json").read_text(encoding="utf-8")
        )
        self.assertEqual(metadata["name"], "Chroma")
        self.assertEqual(metadata["kind"], "upstream-patcher")
        self.assertFalse(metadata["bundled"])
        self.assertIsNone(metadata["deb"])
        self.assertIn(metadata["status"], {"current", "unavailable"})
        if metadata["status"] == "current":
            self.assertRegex(metadata["version"], r"^\d+\.\d+\.\d+")
            self.assertRegex(metadata["spotify_version"], r"^\d+\.\d+\.\d+")

    def test_build_system_has_no_chroma_deb_reference(self):
        offenders = []
        here = Path(__file__).resolve()
        for path in (ROOT / "build-system").rglob("*"):
            if path.resolve() == here:
                continue
            if path.is_file() and path.suffix in {".pl", ".sh", ".py", ".json"}:
                text = path.read_text(encoding="utf-8", errors="replace")
                if re.search(r"chroma[^\n]{0,100}\.deb|\.deb[^\n]{0,100}chroma", text, re.I):
                    offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual(offenders, [])


if __name__ == "__main__":
    unittest.main()
