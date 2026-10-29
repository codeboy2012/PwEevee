#!/usr/bin/env python3
"""Fail a build if its Safari extension is missing, stale or incorrectly identified."""
import json
import plistlib
import sys
import zipfile
from pathlib import Path

RESOURCES = Path(__file__).resolve().parents[1] / 'extension/OpenSpotify/Resources'


def verify(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate entries in IPA')
        if archive.testzip() is not None:
            raise ValueError('IPA archive CRC check failed')
        hosts = [name for name in names if name.startswith('Payload/') and name.count('/') == 2 and name.endswith('.app/Info.plist')]
        if len(hosts) != 1:
            raise ValueError('IPA must contain exactly one host app')
        base = hosts[0][:-len('Info.plist')]
        host = plistlib.loads(archive.read(hosts[0]))
        extension_base = base + 'PlugIns/PwEeveeOpenSpotify.appex/'
        extension = plistlib.loads(archive.read(extension_base + 'Info.plist'))
        expected = host['CFBundleIdentifier'] + '.PwEeveeOpenSpotify'
        if extension['CFBundleIdentifier'] != expected:
            raise ValueError('Safari bundle identifier does not match its host')
        for key in ('CFBundleVersion', 'CFBundleShortVersionString'):
            if extension[key] != host[key]:
                raise ValueError('Safari version does not match host: ' + key)
        if extension['NSExtension'] != {
            'NSExtensionPointIdentifier': 'com.apple.Safari.web-extension',
            'NSExtensionPrincipalClass': 'PwEeveeSafariWebExtensionHandler',
        }:
            raise ValueError('Unexpected Safari extension registration')
        binary = archive.read(extension_base + extension['CFBundleExecutable'])
        if binary[:4] != b'\xcf\xfa\xed\xfe':
            raise ValueError('Safari executable is not a 64-bit Mach-O binary')
        for resource in RESOURCES.rglob('*'):
            if resource.is_file() and archive.read(extension_base + resource.relative_to(RESOURCES).as_posix()) != resource.read_bytes():
                raise ValueError('Stale packaged Safari resource: ' + resource.name)
        return {'artifact': Path(path).name, 'spotify_version': host['CFBundleShortVersionString'], 'safari_extension': expected, 'verification': 'passed'}


if __name__ == '__main__':
    try:
        print(json.dumps(verify(sys.argv[1]), indent=2))
    except (KeyError, ValueError, OSError, zipfile.BadZipFile) as error:
        raise SystemExit('Safari IPA verification failed: ' + str(error))
