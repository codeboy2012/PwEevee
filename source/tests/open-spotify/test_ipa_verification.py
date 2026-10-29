import importlib.util
import plistlib
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('check_ipa', ROOT / 'scripts/check-safari-ipa.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class IpaVerificationTests(unittest.TestCase):
    def fixture(self, path, missing=None, extension_id='com.spotify.client.PwEeveeOpenSpotify'):
        base = 'Payload/Spotify.app/'
        host = {'CFBundleIdentifier': 'com.spotify.client', 'CFBundleShortVersionString': '9.1.90', 'CFBundleVersion': '123'}
        extension = dict(host, CFBundleIdentifier=extension_id, CFBundleExecutable='PwEeveeOpenSpotify', NSExtension={
            'NSExtensionPointIdentifier': 'com.apple.Safari.web-extension',
            'NSExtensionPrincipalClass': 'PwEeveeSafariWebExtensionHandler'})
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(base + 'Info.plist', plistlib.dumps(host))
            ext = base + 'PlugIns/PwEeveeOpenSpotify.appex/'
            archive.writestr(ext + 'Info.plist', plistlib.dumps(extension))
            archive.writestr(ext + 'PwEeveeOpenSpotify', b'\xcf\xfa\xed\xfe' + b'fixture')
            for source in module.RESOURCES.rglob('*'):
                if source.is_file() and source.name != missing:
                    archive.writestr(ext + source.relative_to(module.RESOURCES).as_posix(), source.read_bytes())

    def test_valid_package_and_missing_or_misidentified_extension(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.ipa'
            self.fixture(path)
            self.assertEqual(module.verify(path)['verification'], 'passed')
            self.fixture(path, missing='content.js')
            with self.assertRaises(KeyError):
                module.verify(path)
            self.fixture(path, extension_id='wrong.bundle.id')
            with self.assertRaises(ValueError):
                module.verify(path)
