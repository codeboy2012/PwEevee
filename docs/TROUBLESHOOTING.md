# Troubleshooting

Failure modes actually encountered in this project's history, with their real fixes.

## "Unknown archive type" when installing a .deb

**Cause:** the ar archive was malformed — member names written as directory-style
entries (`debian-binary/`), wrong member modes, or the mode field formatted through
`%o` (decimal 100644 becomes octal `030444`). dpkg/APT reads the member headers, finds
garbage, and reports the file as an unknown archive type.

**Fix:** `PwEvevee/build-system/package/make-deb.pl` writes the format correctly and directly:

- global magic `!<arch>\n`
- members in order: `debian-binary` (`2.0\n`), `control.tar.gz`, `data.tar.lzma`
- 60-byte GNU member headers: name + trailing `/` marker, mode string `100644`
  (literal, never through `%o`), decimal size, `` `\n `` terminator
- bodies padded to even length

**Verify:** `perl PwEvevee/build-system/tests/deb-format-test.pl` (30 checks) — it parses the generated
archive back member-by-member and asserts every field, then decodes the LZMA member
with `xz` and reads the tar. The same reader from the pre-restructure toolchain
(`scripts/deb-tree.pl`) also parses it cleanly.

**Historical proof:** rebuilding the reference Eevee deb's data from its unpacked
payload produced a `data.tar.lzma` byte-identical to the original working package
(5,970,903 bytes, sha-verified member-for-member).

## Eevee loads but its icons / resources don't appear

**Cause:** the build was missing Eevee's resources, not placing them in a "special"
directory. Eevee's BundleHelper searches:

1. `<home>/Library/Application Support/EeveeSpotify.bundle` (jailbreak layout), then
2. `Spotify.app/EeveeSpotify.bundle` (main-bundle fallback)

The known-good IPA ships the bundle inside the app (fallback 2) **plus 142 icon PNGs
at the app root** — the icon picker reads them there. Builds that skipped either part
showed the tweak working with broken theming.

**Fix:** the unified build installs both (bundle + icons) and `resolve-deps.pl`
fails the build if `EeveeSpotify.bundle/Info.plist`, the en.lproj strings, or fewer
than 140 app-root PNGs are present.

**Verify:**

```bash
unzip -l dist/<build>.ipa | grep -c EeveeSpotify.bundle      # 58 entries
unzip -l dist/<build>.ipa | grep -cE 'Payload/Spotify.app/[^/]+\.png$'  # >= 142
```

## Sideloadly injects conflicts or double-injects

**Cause:** letting Sideloadly inject tweaks on top of an IPA that already carries them.
The unified IPA is already fully integrated — the five load commands are in the main
executable and every dependency ships inside the app.

**Fix:** use Sideloadly (or any signer) in **sign-only** mode on the unified IPA. Do
not feed it `.deb`/`.dylib` inputs. If you must use an injection mode, verify the
binary afterwards: `ncmds` must still be 153 and each load command must appear exactly
once (the Mach-O validator's duplicate check exists for this).

**Verify:**

```bash
unzip -p dist/<build>.ipa Payload/Spotify.app/Spotify > /tmp/exe
perl scripts/macho-dump.pl /tmp/exe | grep -cE 'LC_LOAD_DYLIB @executable_path/Frameworks/(spotifyglass|Eevee)'
# 5
```

## Injector refuses: "padding after load commands is not zero"

**Cause:** the input binary was already modified (injected by another tool) and the
padding region contains data. Overwriting it would corrupt the binary.

**Fix:** start from a clean decrypted IPA. The pipeline assumes an unmodified input;
`unified.sh` on a fresh 9.1.84 IPA has ~131 KB of zero padding available.

## Injector refuses: "no room for another load command"

**Cause:** pathological binary with no padding. Not seen on 9.1.84 (needs ~72 bytes per
command; 131 KB is available). If it happens, the input is not the expected binary —
check its version with `PwEvevee/build-system/lib/plist-value.pl Info.plist CFBundleShortVersionString`.

## Wrong Spotify version / tweak mismatch

spoti.pw 0.22.0 is built and tested against Spotify **9.1.84** (0.21.1 against 9.1.78).
The mod hooks Spotify's own classes, which change between releases. If you feed a
different version, the build may succeed and the app may then crash at runtime. The
manifest records the input version — check `dist/build-manifest.json` before publishing.

## Dependency resolution fails with DUPLICATE DEPENDENCY

**Cause:** two suppliers provided the same dependency with different bytes (e.g. a
CydiaSubstrate from two sources).

**Fix:** pick one supplier. The policy lives in `PwEvevee/dependencies.json`
(`duplicate_policy`): byte-identical copies collapse with a note; different copies fail
the build naming both suppliers. Never "fix" this by deleting one copy silently —
resolve which version is actually required, then re-run.

## Website downloads 404

The website serves `website/releases/<name>.ipa`. If it's missing:

1. `perl PwEvevee/build-system/release/make-release.pl <ipa> dist/build-manifest.json` was run, and
2. `perl PwEvevee/build-system/release/render-site.pl` copied in-window files to `website/releases/`, and
3. your web server maps `/releases/` to `website/releases/`.

Check `releases/index.json`: a release with `"past_retention": true` is intentionally
not hosted — it links to GitHub Releases instead.

`perl PwEvevee/build-system/tests/website-tests.pl` checks this for you: it fails if any
page offers a download whose file is not present under `website/releases/`.

## Upstream versions on the site look wrong or stale

The site never hardcodes a version, so a wrong number means the generated data is out of
date or the last fetch failed.

1. `scripts/update-releases.sh` — refetch, re-render and re-check.
2. Read the diagnostics. Each project prints its resolved release; a failure prints why
   and says whether the previous known-good value was kept.
3. A card showing a `cached` badge means GitHub could not be reached on the last run and
   the site is deliberately showing the last good value instead of nothing.
4. `403`/`429` from GitHub is the anonymous rate limit (60 requests/hour). Export
   `GITHUB_TOKEN` and run again.
5. `451` means the repository has been disabled on GitHub. That is a real upstream state,
   not a bug — update the repository coordinates in `website/data/projects.json` if the
   project has moved.

Nothing on the site is edited by hand to fix a version. If a number is wrong, the data
file or `projects.json` is wrong.

## A page shows skeletons or "Release information is temporarily unavailable"

That state only appears when `render-site.pl` has not run against current data, so the
page shipped with an empty data region and the browser fallback took over. Run
`scripts/update-releases.sh` and redeploy `website/`.

## A sideloaded build will not launch until Developer Mode is on (iOS 16+)

**Cause:** the app is *development-signed* by the signer (AltStore/SideStore/Feather/Sideloadly all
sign with your Apple ID's development profile). Since iOS 16, iOS refuses to run locally installed
development-signed apps unless Developer Mode is enabled on the device — Apple's own wording is that
it "grant[s] or den[y] permission for locally installed apps to run" and covers "installing an `.ipa`
file with Apple Configurator". Nothing in the PwEevee IPA causes this: the file ships with no
provisioning profile and no certificate-backed signature at all (see
[developer-mode-audit-3.1.0.md](../release-candidate/developer-mode-audit-3.1.0.md)).

**Fix:** Settings → **Privacy & Security** → **Developer Mode** → on → **Restart** → after reboot
confirm **Enable** and enter the passcode. The switch only appears once the device has been
paired/trusted once, so install the app first if you cannot see it. Separately, trust the signing
certificate via Settings → **General → VPN & Device Management** (a different gate, needed either way).

**Do not** try to remove the requirement by stripping signatures or editing entitlements — it is a
device policy tied to the profile type, and those edits only break the install. Free Apple ID builds
expire after 7 days; re-install from the signer weekly (Developer Mode itself can stay on).

## Spotify login or signup returns a "Spotify server error" (iOS 17)

**Cause:** a known defect of the 3.1.0 build, reproduced on an **iPhone SE (2nd generation)
running iOS 17.8.1**. It is not a signing, provisioning or Developer Mode problem, so
re-signing or re-installing does not clear it.

**Status:** acknowledged and carried for a future update. Authentication is listed as **not
working on iOS 17** wherever compatibility is claimed, and the build is not presented as
fully compatible on the strength of a launch alone. No other iOS version was tested.

**Do not** re-install repeatedly or re-sign to try to clear it — the failure is in the
build's authentication path, not in your installation.

## Device testing

The build is validated structurally, but only a device run proves the app: Eevee's
settings pane, the icon picker showing 142 icons, spoti.pw's Mod Settings, and the
Live Activity all need a real launch. Treat every structural validation as necessary,
not sufficient, before publishing.
