# PwEevee website — Debian 13 homelab deployment

Public URL: <https://pweevee.skytweak.dpdns.org/> — served through the existing
Cloudflare Tunnel (`cloudflared` token tunnel, ingress configured in the Cloudflare
dashboard) to **port 4173** on the Debian host `192.168.1.124`. HTTPS is Cloudflare
edge TLS; certificate verification passes.

## Server layout (user `sleepy`, no root involved)

```text
/home/sleepy/pweevee-site/
├── current/          deployed static site — the only directory the server reads
├── backups/          dated tar.gz snapshots of the previous live site
├── bin/start.sh      idempotent start script (user-level, no root)
├── logs/             http.log (requests) + boot.log (@reboot output)
└── pweevee-site-upload.tar.gz + pweevee-site-upload.sha256   trusted build bundle
```

The server is a plain `python3 -m http.server 4173` started detached by
`bin/start.sh` (matches the host's existing convention of user-run static servers,
e.g. `skytweaks` on :5000). The previous first deployment had been started from a
long-abandoned login session and served the git working tree directly
(`/home/sleepy/PwEevee/website`) — it would have died at the next reboot. The new
setup fixes both problems: durable boot start via a `@reboot` crontab entry and a
dedicated docroot that is never the working tree.

## Refreshing the live site

**The site now refreshes itself, every fifteen minutes.** A user-level cron
entry on this host runs the complete cycle — GitHub release metadata, repository
statistics, the AltSource, the render, the validation suite — and publishes the
result only after it passed validation: the live document root can move forward
to a state that passed, or stay exactly where it is, and nothing else.

```cron
*/15 * * * * /home/sleepy/pweevee-site/bin/refresh-cron.sh
```

`bin/refresh-cron.sh`:

1. takes an exclusive `flock` on `~/pweevee-site/refresh.lock`, so two runs can
   never overlap — a run that finds the lock held records a `skipped` attempt,
   touches nothing else, alerts nobody, and exits 0;
2. `git fetch`es `origin/main` into `~/pweevee-site/src` — a `--no-checkout`
   clone, so the fetch cannot disturb a working tree — and extracts exactly the
   committed tree with `git archive` into a per-run scratch directory;
3. runs `scripts/refresh-site.sh --publish ~/pweevee-site/current`, which
   refreshes the data, re-renders every page, runs `website-tests.pl`, and only
   then replaces the document root (a rename on the same filesystem, never a
   half-copied directory);
4. writes `logs/refresh-status.json` (`state`, `stage`, the release it found,
   the before/after digests, whether it published, and the incident fields) and
   appends the full run to `logs/refresh.log`;
5. updates `logs/refresh-health.json` through `bin/refresh-health.pl` — the
   counters that survive between runs (consecutive failures, first failure,
   last success, last notification);
6. delivers one notification through `bin/refresh-notify.sh` when the incident
   policy says an alert is due.

Cost and churn: `update-stats.pl` uses one conditional `GET` per repository per
run (304s do not count against GitHub's anonymous 60/hour budget), and
`refresh-site.sh` skips the swap entirely when the staged site is identical to
the live one — comparison ignores refresh timestamps, so an idle fifteen minutes
neither replaces the docroot nor writes a backup. `GITHUB_TOKEN` can be exported
in the cron job if the host ever hits the anonymous rate limit; none is required.

Failure behaviour: an unreachable GitHub keeps the last known-good data and marks
it stale (the page says so); a render or validation failure publishes nothing and
the previous site keeps serving; every failure is recorded in the status file and
the log. A failed run never takes the live site down, and a failed notification
never changes the run's own exit status.

### Failure notifications

Two files carry the running story across runs:

- `logs/refresh-status.json` — the last attempt: `state` (`ok` / `failed` /
  `skipped`), `stage` (which step failed: `fetch`, `releases`, `stats`,
  `altsource`, `render`, `validate`, `publish`, or `lock`), the release it
  served, the before/after digests, `changed`, `published`, and the incident
  fields `consecutive_failures`, `incident`, `last_success_at`,
  `last_published_release` and `notification` (`status`, `at`, `error`).
- `logs/refresh-health.json` — the counters and notification bookkeeping
  (`first_failure_at`, `last_notified_at`, retry state). Deleting it starts a
  fresh incident history; the next run recreates it.

Alert policy, implemented once in `scripts/refresh-health.pl`:

| Situation | What happens |
|---|---|
| First failure of an incident | one alert immediately |
| Still failing, inside the cooldown (1 h) | no alert; the failure is still counted |
| Still failing, cooldown elapsed | one alert, then silence for another hour |
| Success after an open incident | one recovery alert; the incident closes only after it is delivered |
| Lock held by the previous run | recorded as `skipped`, never alerts |
| No endpoint configured | recorded as `not-configured`; the failure itself is unchanged |
| Delivery returns an error | recorded as `failed`; the incident stays open and retries after the cooldown |

Configure it with one value, kept out of the repository:

```bash
install -d -m 700 ~/.config/pweevee-site
printf 'PWEEVEE_NOTIFY_URL=%s\n' 'https://…' > ~/.config/pweevee-site/notify.conf
chmod 600 ~/.config/pweevee-site/notify.conf
```

`PWEEVEE_NOTIFY_URL` in the environment wins over the file. The payload shape is
chosen from the endpoint, so no schema has to be described: Slack
(`hooks.slack.com`) gets `{"text":…}`, Discord gets `{"content":…}`, an ntfy
topic gets a plain body with `Title`/`Tags` headers, and anything else gets
`{"title","text","source"}`. The URL is never printed, logged, or written to
the status file, and message text is redacted before it leaves the process.

Test the wiring without sending anything:

```bash
PWEEVEE_NOTIFY_URL='https://…' PWEEVEE_NOTIFY_TITLE='test' \
  PWEEVEE_NOTIFY_TEXT='wiring check' bash scripts/refresh-notify.sh --dry-run
```

Exit statuses are distinct on purpose: `0` delivered, `2` nothing configured,
`3` delivery failed. `refresh-status.json` reports the same three outcomes, so
"no alert arrived" is never ambiguous. To see what the last run did:

```bash
cat ~/pweevee-site/logs/refresh-status.json ~/pweevee-site/logs/refresh-health.json
tail -30 ~/pweevee-site/logs/refresh.log
```

Rollback: each swap backs the previous docroot up to
`backups/site-<UTC-stamp>.tar.gz` (the newest ten are kept).

```bash
rm -rf /tmp/rollback && mkdir /tmp/rollback
tar -xzf ~/pweevee-site/backups/site-<stamp>.tar.gz -C /tmp/rollback
mv ~/pweevee-site/current ~/pweevee-site/current.failed
mv /tmp/rollback ~/pweevee-site/current
```

### Deploying or updating the refresh trio

The wrapper and its two helpers have their source of truth in the repository and
must be deployed together — the wrapper resolves the other two from its own
directory:

| Repository file | Deployed to |
|---|---|
| `scripts/refresh-cron.sh` | `~/pweevee-site/bin/refresh-cron.sh` |
| `scripts/refresh-health.pl` | `~/pweevee-site/bin/refresh-health.pl` |
| `scripts/refresh-notify.sh` | `~/pweevee-site/bin/refresh-notify.sh` |

```bash
for f in refresh-cron.sh refresh-health.pl refresh-notify.sh; do
  scp "scripts/$f" sleepy@homelab:~/pweevee-site/bin/
done
chmod +x ~/pweevee-site/bin/refresh-cron.sh ~/pweevee-site/bin/refresh-notify.sh \
         ~/pweevee-site/bin/refresh-health.pl
```

The cron entry never changes:

```cron
*/15 * * * * /home/sleepy/pweevee-site/bin/refresh-cron.sh >> /home/sleepy/pweevee-site/logs/cron.log 2>&1
```

### Boot survival

`cron.service` is enabled (`systemctl is-enabled cron` → `enabled`) and pulled in
by `multi-user.target`; on this host it starts at boot (its
`ActiveEnterTimestamp` equals the boot time), and user crontabs live in
`/var/spool/cron/crontabs/`, so the crontab is read again at every boot. The
server still starts from the `@reboot` entry (`bin/start.sh`). A reboot has
**not** been performed to prove the end-to-end story; the service state plus the
record of unattended runs are the evidence.

### If the refresh stops running

1. `crontab -l` — is the `*/15` line still there?
2. `systemctl is-active cron` and `systemctl is-enabled cron`.
3. `tail -50 ~/pweevee-site/logs/refresh.log` — did runs start, and when?
4. `cat ~/pweevee-site/logs/refresh-status.json` — `state`, `stage` and
   `consecutive_failures` say what failed and for how long.
5. `ls -l ~/pweevee-site/logs/cron.log` — cron writes here only when the wrapper
   itself cannot run.
6. Run the cycle by hand, exactly as cron would:
   `env -i HOME="$HOME" PATH=/usr/bin:/bin /home/sleepy/pweevee-site/bin/refresh-cron.sh`
7. If the host clock is wrong the schedule still fires, but digests and
   timestamps become misleading — check `date -u`.

## Update procedure (by hand, if the cron is unavailable)

One command does the whole cycle — refresh, render, validate, and (with
`--publish`) swap the document root:

```bash
bash scripts/refresh-site.sh                    # refresh + render + validate
bash scripts/refresh-site.sh --publish DIR      # ... and publish into DIR
bash scripts/refresh-site.sh --digest-only      # what the live tree hashes to
```

For a tarball handed to another host, render first and ship the rendered tree:

```bash
tar -czf site.tgz -C website .
sha256sum site.tgz | tee site.tgz.sha256
```

Upload `site.tgz` + `.sha256` to `/home/sleepy/pweevee-site/incoming/`, then on the
server:

```bash
cd ~/pweevee-site
sha256sum -c incoming/*.sha256
mkdir -p /tmp/px && tar -xzf incoming/site.tgz -C /tmp/px && find /tmp/px -type f | wc -l
mv -T current current.prev && mv /tmp/px current   # atomic-ish swap
~/pweevee-site/bin/start.sh                        # restart server if it died
```

Rollback: `mv -T current.prev current` (or restore a tarball from `backups/`).

## What has been verified (2026-10-26)

- Render + 4,429 website tests pass from a clean tree.
- Homepage, `/downloads/`, `/install/`, `/releases/`, `/projects/…`, `/credits/`,
  `/robots.txt`, `/sitemap.xml`, `/assets/brand/pweevee-app-icon.png` all 200 over
  HTTPS with correct content types; unknown route → 404.
- `/pweevee/apps.json` (AltStore/SideStore source), `/data/altsource.json`,
  `/data/releases.json`, `/data/stats.json` return 200 `application/json` and match
  the validate build byte-for-byte (md5 compared public vs deployed vs local).
- Browser: page title/H1 correct, download links resolve to
  `github.com/codeboy2012/PwEevee/releases`, zero failed site-asset requests; the
  only console 404 is the GitHub API `spoti.pw/releases/latest`
  (upstream repo has no non-draft/latest release — freshness check is fail-open).
- Restart tested: kill + `start.sh` recovers, public returns 200.
- `@reboot` crontab entry installed for boot survival (**reboot itself not tested**).
- Frostfall panel/Mongo backend, DerList app/db, SkyTweaks (:5000), MCSM, cloudflared,
  Docker: all active after the swap; first-time-site tarball backup exists
  (`backups/live-website-20261026-152244.tar.gz`).

## What the automatic refresh has been verified doing (2026-10-27)

Runner: `~/pweevee-site/bin/refresh-cron.sh` (sha256
`270be014cca8fca43219ed8512685be1fe41df34fd9125c58bc3d56d98a0166d`), from the
committed tree at `b54d298`, on this host.

| Check | Result |
|---|---|
| First run (stale site: the world was being served v2.0.0) | 8.9 s, `website-tests.pl` 4409 checks passed, then published: `state: ok`, `release: 3.1.0`, `published: true`; previous docroot backed up to `backups/site-20261027T221538Z.tar.gz` |
| Second run, same upstream data | `changed: false`, `published: false`, note `live site already current`; no swap, no new backup (one backup on disk) |
| Overlap guard | with the lock held, a second run logged `another refresh is still running — skipping this cycle` and exited 0 without touching anything |
| Live homepage | `v3.1.0` present, `v2.0.0` absent; `last-modified: Tue, 27 Oct 2026 22:15:35 GMT` |
| Live `/data/releases.json` | `pweevee -> 3.1.0 (27 October 2026)`, `spotipw -> v0.50.0`, `eeveespotify -> v7.0.0` |
| `refresh-pipeline-tests.pl` | 73 checks pass on this host (the `flock` overlap test runs here; it self-skips where `flock` is absent), 79 pass including the on-visit-recheck section on the workstation |
| GitHub Actions `website-refresh.yml` | dispatched on `ed560c3`: all five steps green, and it committed `b54d298` — a genuine change (download counts moved 6411 -> 6412, `pushed_at` moved, a stale repository recovered), not timestamp churn |
| Unattended cron fire | the `22:30:02Z` run started itself, refreshed from GitHub, passed 4409 checks, and published (`state: ok`, `release: 3.1.0`, backup `site-20261027T223010Z.tar.gz`) — no hand-holding, no manual step |
| Reboot survival of the refresh | not tested (the `@reboot` entry for the server is unchanged; the refresh cron needs no boot-time action) |

## Known limitations

- The refresh runs as a crontab entry rather than a systemd timer: without root
  on this host that is the available scheduler. Its logs are files under
  `logs/`, not `journalctl`; a failed run is visible in
  `logs/refresh-status.json` and does not stop the next cycle.
- No root on the host without interactive sign-in: a proper systemd unit
  (`/etc/systemd/system/pweevee-website.service`) would be the cleaner long-term
  arrangement; the `@reboot` crontab covers reboot survival meanwhile.
- Unknown routes return Python's minimal 404 page, not the site's styled
  `/404.html` (that nicety comes with a real web server / systemd unit reinstallation).
- The tunnel ingress (`pweevee.skytweak.dpdns.org` → :4173) is managed in the
  Cloudflare Zero Trust dashboard and must not be re-pointed casually.
