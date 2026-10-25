# Mac readiness — PwEevee v3.1.0 build workflow (Phase 0/1 report)

Date: 2026-10-25 · Purpose: read-only verification of Mac build readiness before any
Phase 2 change. Registry of everything checked, with the exact evidence.

## 1. Windows-side preservation baseline (read-only audit)

Baseline verified intact — **no discrepancies vs the documented state**:

| Item | State |
|---|---|
| Repo | `C:\Users\sleepy\Documents\PwEevee` on `feat/v3.1.0-integration`, HEAD `43a92cecdd49cb98f7c042c7076dd1a368b710e1` |
| Working tree | 61 modified tracked files (brand assets, build-system, Eevee component update, website) + untracked `release-candidate/`, `PwEvevee/build-system/lib/bplist.pm`, `PwEvevee/brand-icons/`, source-artifacts, and more — all preserved |
| RC IPA | `release-candidate/PwEevee-0.22.0-rc1-unified-Spotify-9.1.90.ipa` — 338,031,911 bytes, sha256 `9845b1c325ac0b042e129bb892103975daed80becea0122c4977ce743ed55415` (matches `release-candidate/build-manifest.json`) |
| RC build log | `release-candidate/build.log`, manifest, settings inventory, contained Python 3.13.8 — present |
| Original IPAs (Downloads) | all four present, unmodified sizes; sha256 verified below |
| Comparison docs | `docs/comparison/{architecture,feature-matrix,licensing-and-provenance,roadmap,test-report}.md` present |

### SHA-256 of the four original IPAs (read-only, not modified)

| File | Size | SHA-256 |
|---|---|---|
| `Taurus-0.60.4.ipa` | 137,901,231 | `6e1e367b7710822207a3f36d30c35790075af1c8c541a18ef4af04ec900e03f1` |
| `chroma-1.0.0-beta.3.ipa` | 155,786,119 | `8e051f44d4d55eaa377d62d518f1c2222a0bf43f47a1e40c2e12ad2144c84ddc` |
| `com.spotify.client_9.1.90_und3fined.ipa` | 153,481,523 | `409601a58953818eea17edb92963d10256ae6fcf00c69954105e5becc08ec296` |
| `PwEevee-0.22.0-alpha.2-unified-Spotify-9.1.90.ipa` | 300,634,848 | `a76b469a8291d6650026ef1355b77ead37efcc9250517aaf057a6e6b1dab3996` |

## 2. SSH access (verified)

The exact command/client that successfully authenticates:

```bash
/c/Windows/System32/OpenSSH/ssh.exe -o BatchMode=yes pweevee-mac "echo ok"   # → ok, exit 0
```

- Windows OpenSSH 9.5p2, config alias `pweevee-mac` (HostName `192.168.1.127`, user `xcode`,
  `IdentityFile ~/.ssh/pweevee_mac`, `IdentitiesOnly yes`). Passphrase-protected key kept as-is;
  it signs through the Windows ssh-agent service, which is RUNNING.
- Known limitation (unchanged from the earlier verification): Git-Bash/MSYS OpenSSH 10.5p1 can
  reach the agent-less passphrase-protected private key only interactively, so **all remote
  invocations from build scripts must call Windows `ssh.exe` explicitly** (or use a wrapper).
- No SSH security settings touched anywhere.

## 3. Mac environment (all read-only)

| Check | Result |
|---|---|
| OS | macOS 27.0.1 (Build 26A434), Apple Silicon `arm64` |
| CPU / RAM | 8 cores, 8 GiB RAM |
| Disk free on / | **~18 GiB free** of 228 GiB (df: 13 Gi used on system volume; data volume not separately polled) |
| Xcode | Xcode 27.1 (27A9275) at `/Applications/Xcode.app/Contents/Developer` (selected path correct) |
| SDKs | iphoneos27.1, iphonesimulator27.1, custom-app support present |
| git / perl | Apple git 2.54.0; perl 5.34.1 |
| Perl modules | `JSON::PP`, `Digest::SHA` — both load OK (required by `unified.sh` steps 4–9) |
| Shell tools | bash, unzip, zip, diff, tar, scp, rsync, jq — all present |
| **`xz`** | **MISSING on the Mac** (no Homebrew installed, no `command -v xz`) — see gap G-1 |
| Theos | not installed at `~/theos` (not needed: `unified.sh` is a patch/package pipeline, no tweak compile on device targets; the shipped `spotifyglass.dylib` is pinned) |

## 4. Project presence on the Mac

`~/pweevee-build` **exists but is NOT the same checkout** — confirmed divergence:

| | Windows `~/Documents/PwEevee` (authoritative) | Mac `~/pweevee-build` |
|---|---|---|
| Branch | `feat/v3.1.0-integration` | `feat/premium-spoof-unified` |
| HEAD | `43a92ce` (169 commits) | `556f3dd` (older integration line) |
| Local changes | current v3.1.0 work (61 modified + untracked RC set) | older flow's leftovers |
| Untracked junk on disk | — | build1/2/cycle logs, `*.deb`, `*.deb.KEEP.prev`, `dylibprobe*.sh`, `data-fresh.tar`, `CarPlayProbe.sh`, `battery.txt`, `Spotify-PwEevee-Corrected.ipa` (146 MB), `spotifyglass.dylib.orig` ≈ **3.1 GB total** |

A previous session's PwEevee `unified.sh` and build-components ARE present on the Mac, but on
the superseded branch and with uncommitted local edits (e.g. `spotifyglass.dylib`,
`integration-tests.pl`) — so it cannot be trusted as a build tree for v3.1.0. **No sync, copy,
or file operation was performed there.** Overwriting `~/pweevee-build` is explicitly *not*
proposed because it holds that session's own modified/untracked files; a fresh, isolated
directory is proposed instead.

## 5. Self-hosted runner (read-only inventory)

- Lives at `/Users/xcode/actions-runner` — `Runner.Listener` binaries present, `_diag/`,
  `_work/`, `config.sh`, `env.sh`, runner tarball 2.337.0 (osx-arm64).
- Process check: no `Runner.Listener` process was running during this audit (`ps aux | grep i
  [R]unner.Listener` → none) → **idle, no job contention right now**. Nothing was started,
  stopped, or configured.

## 6. Gaps that need your decision (owners marked)

| # | Gap | Evidence | Proposed minimal remedy (awaiting approval) |
|---|---|---|---|
| G-1 | `xz` missing on the Mac — `unified.sh` step 0 hard-fails without it; `make-deb.pl` and the deb tests shell out to `xz --format=lzma` | `command -v xz` → missing; no brew | **Option 1 (recommended):** build a minimal xz in an isolated `~/pweevee-work/tools` by compiling `xz` from the official XZ utils source, with source hash verified against published digests — no Homebrew, no system-wide change, contained in the build work dir. **Option 2:** you install Homebrew yourself; build scripts then just use it. **Option 3:** switch the deb compressor to a non-xz algorithm = build-system source change (broader than approved scope — would need explicit sign-off) |
| G-2 | Repo not on the Mac at the right branch | unknown | 10.7 MB repo working tree; transfer via tar over the verified SSH alias |
| G-3 | No cryptographically identity-verified source for xz tarball | unknown | fetch from a pinned official source; verify SHA-256 first vs upstream-published digests; treat any hash mismatch as a stop |

## 7. Changed files / outputs of this phase (no tracked files touched)

- NEW: `release-candidate/mac-readiness.md` (this report — preservation + readiness evidence)
- NEW: `release-candidate/device-test-matrix.md` (simulator inventory + proposed Phase 4 test matrix)
- Nothing else was created, modified, moved, or deleted. All remote commands were strictly
  read-only (`sw_vers`, `uname`, `df`, `xcodebuild -version/-showsdks`, `simctl list`, `ls`,
  `git status`, `mdfind`, `ps aux`).
- Build commands executed: **none**.
