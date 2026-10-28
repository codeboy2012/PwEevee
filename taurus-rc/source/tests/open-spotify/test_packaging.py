import importlib.util
import json
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("extension_plist", ROOT / "scripts/safari-extension-plist.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PackagingTests(unittest.TestCase):
    def test_identity_matches_host_and_override(self):
        host = {"CFBundleIdentifier": "com.spotify.client", "CFBundleShortVersionString": "9.1.90", "CFBundleVersion": "1234"}
        for override in ("", "dev.example.pweevee"):
            info = module.make_plist(host, override)
            self.assertEqual(info["CFBundleIdentifier"], (override or host["CFBundleIdentifier"]) + ".PwEeveeOpenSpotify")
            self.assertEqual(info["CFBundleVersion"], "1234")
            self.assertEqual(info["CFBundleShortVersionString"], "9.1.90")
            self.assertEqual(info["NSExtension"]["NSExtensionPointIdentifier"], "com.apple.Safari.web-extension")
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / "host.plist", Path(directory) / "Info.plist"
            source.write_bytes(plistlib.dumps(host))
            subprocess.run(["python3", str(ROOT / "scripts/safari-extension-plist.py"), str(source), str(output), "dev.pweevee"], check=True)
            self.assertEqual(plistlib.loads(output.read_bytes()), module.make_plist(host, "dev.pweevee"))

    def test_manifest_references_only_existing_files_and_expected_hosts(self):
        resources = ROOT / "extension/OpenSpotify/Resources"
        manifest = json.loads((resources / "manifest.json").read_text())
        self.assertEqual(manifest["manifest_version"], 3)
        self.assertEqual(set(manifest["permissions"]), {"storage", "activeTab"})
        content = manifest["content_scripts"][0]
        self.assertFalse(content["all_frames"])
        self.assertEqual(len(content["matches"]), 5)
        self.assertNotIn("<all_urls>", content["matches"])
        for name in content["js"] + [manifest["action"]["default_popup"]]:
            self.assertTrue((resources / name).is_file(), name)
        self.assertNotIn("background", manifest)

    def test_shell_syntax(self):
        for name in ("build-safari-extension.sh", "pipeline.sh"):
            subprocess.run(["bash", "-n", str(ROOT / "scripts" / name)], check=True)


if __name__ == "__main__":
    unittest.main()
