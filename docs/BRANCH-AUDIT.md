# Branch & Tag Audit

Date: 2026-10-11 · Scope: `codeboy2012/PwEevee` = `codeboy2012/spoti.pw-builds`

## Repository identity

`github.com/codeboy2012/PwEevee` and `github.com/codeboy2012/spoti.pw-builds`
resolve to the **same repository** (identical HEAD `d560a91` and identical tag
set). PwEevee is a vanity name for the spoti.pw-builds project. All statements
below apply to both URLs.

## Remote branches (verified 2026-10-11, `git ls-remote --heads`)

| Branch | HEAD | Status | Assessment |
|---|---|---|---|
| `main` (only branch advertised) | `d560a91` | default | The only live branch. Carries the unified PwEevee layout (`Spotipw/`, `PwEvevee/`, `Evevee Spotify/`, `website/`). |

A stale local clone listed extra remote-tracking branches
(`ci/release-please-bootstrap`, `feat/own-entity-header`,
`live-activity-demo`, `redesign`, `release-please--branches--main--…`,
`chore/deb-package-id`, `chore/issue-forms`, `ci/release-please`). After
`git fetch --prune` **all of them were deleted from the tracking refs**, i.e.
they no longer exist on the remote (either deleted upstream or the remote
never re-advertised them). **Nothing was merged from them; no action is
recommended.** Their content predates the unified-restructure merge
(`fa025a3`/`a3063fb`) and is superseded by it.

## Tags (9 total, all reachable)

`v0.18.0`, `v0.19.0`, `v0.21.1`, `v0.22.0`, `v0.22.0-alpha`,
`v0.22.0-alpha.2`, `v1.0.2`, `v2.0.0`, `v2.1.0-pre`

- `v0.22.0` is the last release carrying Spoof Premium / Hide Ads (upstream note).
- `v2.0.0` is the newest **stable** release.
- `v2.1.0-pre` is a **pre-release** (regex-confirmed: `-pre` suffix). The
  GitHub API does not set its `prerelease` flag; both
  `update-releases.pl` (website) and `update-readme.pl` (README) now
  recognize conventional pre-release suffixes and never present them as
  stable. This was the root cause of the website README drift audited on
  2026-10-11.

## Related-runners note

The self-hosted Mac runner at `~/actions-runner` is registered against
`codeboy2012/Ani.pm` ( surveyed 2026-10-11; `.runner` `gitHubUrl` field), not
against this repository. The `PwEevee deb` workflow therefore runs on hosted
`macos-15` runners. Moving it onto the Mac requires re-registering the runner
for this repo — not attempted, since it changes the shared runner's
configuration.

## Local uncommitted work snapshot

The workspace carries a prior audit's untracked artifacts under `work/`
(reference .deb extractions) plus new build-system tests and this session's
`PwEvevee/build-system/watch/` pipeline stage; they are intentionally left
uncommitted pending the owner's review. No branch, tag, or remote state was
modified during this audit.
