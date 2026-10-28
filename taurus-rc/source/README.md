<h1 align="center">PwEevee</h1>

<p align="center">Open-Sourced fork of chroma.pw with built-in Spotify Premium. </p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-000000?style=for-the-badge&logo=ios&logoColor=white" alt="iOS">
  <img src="https://img.shields.io/badge/Spotify-9.1.90-1ED760?style=for-the-badge&logo=spotify&logoColor=white" alt="Spotify 9.1.78">
  <img src="https://img.shields.io/badge/Objective--C-3A95E3?style=for-the-badge&logo=apple&logoColor=white" alt="Objective-C">
  <img src="https://img.shields.io/badge/GitHub_Actions-2671E5?style=for-the-badge&logo=githubactions&logoColor=white" alt="GitHub Actions">
</p>

<p align="center">
  <a href="#build-it">Build it</a> ·
  <a href="docs/tweaks.md">Hack on it</a> ·
  <a href="#install-it">Install it</a>
</p>



## PwEevee: the free, open-sourced liquid glass spotify tweak 

A no-jailbreak Theos tweak that rebuilds Spotify for iOS in Liquid Glass, injected into your own
decrypted IPA and signed with your own certificate.

Built and tested on **Spotify 9.1.90** — use that version's IPA. The mod hooks Spotify's own classes,
which change between releases, so another version may build and then break.

| | |
|---|---|
| The redesign | **iOS 26+** |
| Legacy look | iOS 16.1+ |
| Live Activity | iOS 17+ |

The redesign is `UIGlassEffect`, which only exists from iOS 26. Below that the Redesigned UI switch
is greyed out and the mod runs Spotify's own screens with everything else it adds on top. Both live
in Settings → Mod Settings.

## Downloads

Mod Settings → **Downloads** controls Spotify's offline downloads: download or check the current track
or album, cancel a download, inspect quotas and device slots, and review status. Spotify's own download
buttons also work; downloaded songs stay in Spotify's offline storage and play in Spotify.

Downloads patching is verified for **Spotify 9.1.90**. Other versions build without the executable
patch; pass `--no-downloads` to skip it explicitly. The engine is
[Pixie](https://github.com/Glongq/Vitrine-Pixie), by Glongq; see `extension/Downloads/`.

## Install it

Each
[release](https://github.com/codeboy2012/PwEevee/releases) carries the tweak's `.ipa`, install this `.ipa` file with any sideloader, such as SideStore or Feather. You do not need to build to project if you do not wish to.

Add the release source to [SideStore or Feather](https://raw.githubusercontent.com/codeboy2012/PwEevee/stable/altstore-source.json), or add the [ESign source](https://raw.githubusercontent.com/codeboy2012/PwEevee/stable/esign-source.json) in ESign.

## Build it

Bring a decrypted **Spotify 9.1.78 or 9.1.90** IPA; you get an unsigned
`PwEevee-<mod version>.ipa` to sign with SideStore, Feather or any certificate signer. Each
[release](https://github.com/codeboy2012/PwEevee/releases) also carries the tweak's `.deb`.

#### Build with GitHub Actions (recommended)

Fork the repo, enable Actions, run **Build IPA from your own Spotify IPA**. It takes a direct link to
your decrypted `.ipa` and hands the built IPA back as a workflow artifact. No Mac needed; the link is
masked in the log and the result stays in your fork.

#### Build on a Mac

Theos in `~/theos` and Xcode with an iPhoneOS 26+ SDK (`xcode-select` it). An SDK in `~/theos/sdks`
alone builds too, but without the Live Activity. Then:

    brew install make ldid dpkg zsign ideviceinstaller libimobiledevice
    uv tool install "cyan @ git+https://github.com/asdfzxcvbn/pyzule-rw"

Put the decrypted `.ipa` in `ipa/`, then:

    make release    # out/PwEevee-<version>.ipa, ready to sign
    make install    # the same, signed with your certificate and pushed over USB

`make install` reads `SIGN_P12`, `SIGN_PROFILE` and `SIGN_P12_PASSWORD` from `.signing.env`; copy
`.signing.env.example` and fill it in.

The first build spends a minute reading Spotify's flags out of your IPA. `make flags` regenerates it.

### Signing

Sign with a bundle id matching your certificate's App ID. If it doesn't match, the app still works
but tapping the player on the lock screen won't open it — and it tells you on first launch which id
to use. In Feather, copy the App ID into **Identifier** and leave **PPQ protection** off; AltStore,
SideStore and Sideloadly get this right on their own.

The app keeps Spotify's bundle id, so it installs over the real Spotify.

## Contributing

Pull requests are welcome. The pull request's description has a box for agreeing to the
[Contributor License Agreement](CLA.md), which gives the project's owner the rights to the
contribution; it is ticked once, before the first pull request is merged.

## Star history

<a href="https://star-history.com/#codeboy2012/PwEevee&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=codeboy2012/PwEevee&type=Date&theme=dark">
    <img src="https://api.star-history.com/svg?repos=codeboy2012/PwEevee&type=Date" alt="Star history chart">
  </picture>
</a>

## Credits

chroma.pw/spoti.pw by darkk

[cyan](https://github.com/asdfzxcvbn/pyzule-rw) injects, [Theos](https://theos.dev) builds, and
[FLEX](https://github.com/FLEXTool/FLEX), as hopeless's AutoFLEX build in `vendor/`, is the inspector
the view trees are read through.

All modified and distributed code from chroma.pw is licensed under GPL-3.0, no code under PolyForm Strict License 1.0.0 is distributed. 
Not affiliated with Spotify.

## Safari link opener

IPA builds include the Open in Spotify Safari extension. See [setup, coverage and verification](docs/safari-extension.md). Run `make test-safari` for regression checks; use `SAFARI=0` to build without it.
