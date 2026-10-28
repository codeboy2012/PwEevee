# PwEevee website refresh — hardening and verification report (2026-10-28)

Scope: the fifteen-minute refresh on the homelab host that serves
<https://pweevee.skytweak.dpdns.org/>, and the three gaps named in the previous
report: unverified boot survival, silent failures, and status that only answered
"did the last run work?".

Everything below was executed against the live host (`192.168.1.124`, Debian 13,
user `sleepy`) or against the repository on the workstation. No reboot was
performed; wherever that matters it is stated.

## 1. Findings

**Already correct, and left alone**

- The cron entry exists for user `sleepy` and fires on time: runs at `22:30`,
  `22:45`, `23:00`, `23:15`, `23:30`, `23:45`, `00:20` (manual), `00:23` (manual),
  `00:30` UTC — the scheduled runs started at `:01` past the quarter.
- `cron.service` is `enabled`, `WantedBy=multi-user.target`, and its
  `ActiveEnterTimestamp` is the boot time (`Sun 2026-08-09 22:41:45 EDT` for a
  `22:41:21` boot), so it is brought up at boot and reads
  `/var/spool/cron/crontabs/sleepy` then.
- The wrapper runs correctly with no interactive environment: `env -i HOME=…
  PATH=/usr/bin:/bin /bin/sh` was used for every manual run in this report.
- Publishing is still gated by validation and done by rename; the live tree was
  never left in a partial state.

**Missing, now fixed**

1. **A failure was silent.** The status file recorded `failed` but not which of
   the six steps failed, nothing carried an incident across runs, and there was
   no way to be told at all. `refresh-cron.sh` only logged.
2. **The recovery message counted nothing.** A success branch reset
   `consecutive_failures` before composing the alert, so the one message sent
   after an outage always read "after 0 failed run(s)".
3. **An unchanged repository could still publish every fifteen minutes.** The
   `304 Not Modified` path in `update-stats.pl` deleted the `stale` key instead
   of setting it false, so the stored record differed from a fetched one and the
   digest moved. This had been masked by the numbers themselves moving; it showed
   up plainly here when two runs fetched the same data.
4. **A snapshot commit could re-trigger itself.** `pushed_at` is part of the
   repository statistics, and committing a refreshed snapshot *is* a push, so
   the next scheduled run saw its own previous commit as new data. On a
   scheduler that commits on change (the GitHub workflow) that is a
   self-perpetuating commit loop; on the host it is a needless publish after
   every push to the repository.
5. **A relative site path broke every path after the first `cd`.** The wrapper
   `cd`s into the extracted tree before the pipeline runs; with
   `PWEEVEE_SITE_DIR` set to a relative path, the status and log writes landed in
   the throwaway run directory and vanished with it. The wrapper now resolves
   `$D` to an absolute path before doing anything else.

## 2. Changes

| File | Why |
|---|---|
| `scripts/refresh-health.pl` (new) | Incident state across runs (consecutive failures, first failure, last success, last notified), notification decisions with a cooldown, recovery detection, status merge, secret redaction, tolerant handling of corrupt state/status. |
| `scripts/refresh-notify.sh` (new) | One configurable endpoint; payload shape chosen from the URL (Slack / Discord / ntfy / generic JSON); URL never printed; message redacted; distinct exit codes (`0` sent, `2` unconfigured, `3` failed); `--check` reports service/format/config mode without the URL, and `--check --send-test` sends one labelled test and reports the HTTP result. |
| `scripts/refresh-cron.sh` (new, tracked) | The wrapper was previously only on the host. Now versioned: absolute paths, lock-skip recorded as `skipped`, stage recorded on every failure, health update and alert after each run, notification errors never change the run's exit status. `PWEEVEE_SITE_DIR` exists so the tests can drive the real wrapper. |
| `scripts/refresh-site.sh` | Records the failing stage (`releases`, `stats`, `altsource`, `render`, `validate`, `publish`) in the status file; keeps every existing key. |
| `PwEvevee/build-system/release/update-stats.pl` | The 304 path keeps `stale: false` so an unchanged record has one stable shape. |
| `PwEvevee/build-system/release/data-digest.pl` | `pushed_at` is normalized for change detection: it is repository bookkeeping, never rendered, and it moves on the snapshot commit itself. |
| `PwEvevee/build-system/tests/refresh-pipeline-tests.pl` | 181 checks (187 on Linux) with new sections E–H: incident decisions, the wrapper end to end against a stub tree and a mock endpoint, the schedule contract, and the notifier's payloads/redaction. |
| `docs/homelab-deployment.md` | Scheduler, boot survival, deployment of the trio, notification configuration, dedup/recovery, diagnosis, and the verification table below. |

## 3. Scheduling

Installed user crontab (unchanged by this work):

```cron
@reboot sleep 10 && /home/sleepy/pweevee-site/bin/start.sh >> /home/sleepy/pweevee-site/logs/boot.log 2>&1
*/15 * * * * /home/sleepy/pweevee-site/bin/refresh-cron.sh >> /home/sleepy/pweevee-site/logs/cron.log 2>&1
```

- `systemctl is-enabled cron` → `enabled`; `is-active` → `active`.
- `systemctl show cron` → `WantedBy=multi-user.target`,
  `ActiveEnterTimestamp` = boot time.
- Per-user crontabs live in `/var/spool/cron/crontabs/`, so the schedule is
  re-read at boot; the `@reboot` line additionally restarts the static server.
- **A reboot was not performed.** Boot survival is established from service
  enablement, the target dependency, and the fact that cron started at the last
  boot — not from a post-reboot observation.

## 4. Notifications

- **Channel:** none is configured on this host, and none could be authorised
  here. A fresh audit found no `mail`/`msmtp`, no ntfy or Gotify server (native
  or container), no existing webhook config, and no credential for one. The
  only mail service present is Mailpit on `127.0.0.1:8025`, which is a local
  *catcher* another service uses for test mail — it cannot deliver to a person,
  and is explicitly documented as not a destination.
  The interface is complete and the value is the only missing input:
  `PWEEVEE_NOTIFY_URL` in `~/.config/pweevee-site/notify.conf` (mode 0600), or
  in the environment. `refresh-notify.sh --check` now reports
  `configured=no`, the expected path, and exit 2 from the cron environment
  without printing anything secret, so activation is verifiable in one command.
- **Payload:** auto-detected — `hooks.slack.com` → `{"text":…}`,
  `discord.com` → `{"content":…}`, `*ntfy*` → plain body with `Title`/`Tags`
  headers, anything else → `{"title","text","source"}`.
- **Dedup:** first failure of an incident alerts immediately; further failures
  are counted but silent for `PWEEVEE_NOTIFY_COOLDOWN` (default 3600 s), then one
  more alert per hour while it keeps failing.
- **Recovery:** exactly one alert when a run succeeds with an incident open; the
  incident closes only after that alert is delivered (or when no endpoint is
  configured). A failed recovery delivery is retried after the cooldown.
- **Not configured:** recorded as `notification.status: not-configured`; the
  failure itself is unchanged and nothing is sent. The status never pretends an
  alert was delivered.
- **Delivery failure:** recorded as `failed` with a redacted error; the incident
  stays open; the pipeline's exit code and its own error note are untouched.
- **Secret hygiene:** the endpoint never appears in `refresh.log`, the status
  file, or a notification body; URLs and `token=`/`secret=`-style assignments in
  an error are stored as `<url>` / `<redacted>`.

## 5. Tests and their outcomes

Commands, run from the repository root:

| Command | Result |
|---|---|
| `perl PwEvevee/build-system/tests/*.pl` (all 19, one by one) | all PASS |
| `perl PwEvevee/build-system/tests/website-tests.pl` | `OK 4409 checks passed` |
| `perl PwEvevee/build-system/tests/refresh-pipeline-tests.pl` (workstation) | `OK 181 checks passed` |
| same suite, from a fresh `git archive` of `main` on the host | `OK 187 checks passed` (the `flock` lock checks run there) |

Negative controls (each mutation applied to a copy, suite rerun, file restored
byte-identically):

| Mutation | Caught by |
|---|---|
| Cooldown condition replaced with `if (1)` | E3, F3, F4, F5 — 4 checks fail |
| URL redaction line removed | E10 — the stored note keeps the endpoint |
| Recovery branch disabled | E6 (incident never closes), F5 — 3 checks fail |
| `pushed_at` removed from the volatile list | B6 — the digest moves on a push that changed nothing visible |

Failure modes exercised by the suite (mocked GitHub and a mock endpoint, never
the live site): updater failure, validator failure, publication failure, lock
contention, missing checkout, notification not configured, notification delivery
500, dedup, cooldown expiry, recovery, corrupt state file, corrupt status file,
invalid arguments, and that a failed delivery cannot mask the pipeline failure.

## 6. Operational verification on the host

Deployed trio (sha256): `refresh-cron.sh` `7141542448c897e0d25c1ae870e1b4fc39717a725b35504199a4e7f6519fa9ff`,
`refresh-health.pl` `9160520e48c0b109ddaecc86897c8854c4dd6a4beb20396b5240e7512aff98ee`,
`refresh-notify.sh` `f261abd1f2a68e0b8782beea7c91f83096ef27c1266421b4a3fe582169f1f682`.
Local and remote hashes matched after upload.

| Check | Result |
|---|---|
| Run A (cron-like env) | `state: ok`, `stage: done`, published, `last_published_release: 3.1.0` |
| Run B (immediately after) | `changed: false`, `published: false`, `live site already current` |
| Three renders of unchanged data | digest `7942d23d…` three times; only normalized timestamps differ |
| 00:30 scheduled run | started at `00:30:01Z`, `website-tests.pl` 4409 passed, published because another project's fork count changed (4931 → 4932, new ETag) |
| Isolated drill, first failure | `notify:1`, exactly 1 POST, `notification.status: ok` |
| Isolated drill, repeat inside cooldown | `notify:0 reason:cooldown`, still 1 POST |
| Isolated drill, after cooldown | `notify:1 reason:cooldown elapsed`, 2 POSTs, `consecutive_failures: 3` |
| Isolated drill, recovery | `notify:1 kind:recovery`, text `after 3 failed run(s)`, 3 POSTs, incident `none` |
| Isolated drill, lock held | `skipped`, `stage: lock`, counters unchanged, no alert |
| Log hygiene | the loopback endpoint URL does not appear in `refresh.log` |

Drill artefacts live only under `/tmp/drill` and `/tmp/suite-tree` on the host;
the live document root and its status file were not used by the drill.

## 7. Live verification

At `2026-10-28T00:31Z`:

- `https://pweevee.skytweak.dpdns.org/` → 200, `text/html`,
  `last-modified: Wed, 28 Oct 2026 00:30:06 GMT`.
- Homepage: `v3.1.0`, `Published 27 October 2026`, download link
  `…/releases/download/3.1.0/com.spotify.client_9.1.90_und3fined.ipa`;
  `v2.0.0` occurs 0 times.
- `/data/releases.json` → `pweevee 3.1.0 (27 October 2026) stale=0`,
  `spotipw v0.50.0 stale=1`, `eeveespotify v7.0.0 stale=0`.

`spotipw` is stale because its upstream repository has no published release;
that is the documented fail-open behaviour, not a refresh failure.

## 8. Git status

- `7030b58` — the hardening (wrapper, health, notifier, stage recording,
  idempotency fix, tests, operator doc) — pushed to `main`.
- `c713486` — recovery message counts the real failures; docs verification table
  and the 178-check figure — pushed to `main`.
- This report is committed on top; the working tree otherwise still carries the
  user's pre-existing modifications and untracked files, untouched.

## 9. Limitations and remaining work

1. **No reboot was performed**, so boot survival remains service-state evidence,
   not an observation. If a reboot is acceptable, the check afterwards is:
   `crontab -l`, `systemctl is-active cron`, and a `refresh.log` line within
   fifteen minutes.
2. **No notification endpoint is configured**, so this task's delivery proof is
   still outstanding. Until `PWEEVEE_NOTIFY_URL` is set, failures are recorded
   as `not-configured` and nobody is told. The delivery path itself is verified
   against loopback endpoints (first failure, cooldown, recovery), and
   `--check`/`--send-test` are in place so the remaining step is: create the
   destination, write the one line, run `--check --send-test`, confirm receipt.
3. The three `bin/` scripts are deployed copies; a change to them requires the
   copy step in the operator doc. They are hash-checked after deployment but the
   host does not verify them automatically.
4. The host has no root access from here, so the schedule is a user crontab
   rather than a systemd timer, and its logs are files rather than `journalctl`.
5. GitHub API calls remain anonymous (conditional requests keep an idle run
   free); `GITHUB_TOKEN` can be exported in the cron environment if the host
   ever meets the rate limit.
6. The website still has no public health surface; freshness is visible through
   the release data's own timestamps and the `stale` flags, which is honest but
   not a substitute for an operator alert.
