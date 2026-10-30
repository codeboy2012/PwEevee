# Upstream metadata

## Chroma

[`chroma.json`](chroma.json) records the publicly available Chroma release for
PwEevee's compatibility metadata. Chroma is a separate upstream project and an
official browser-based IPA patcher. It is **not** a PwEevee component, it is not
bundled or mirrored here, and PwEevee does not ship or depend on a Chroma
`.deb`.

The source of truth is the official installation page:

- <https://chroma.pw/>
- <https://chroma.pw/patch>

The checked-in record is refreshed with:

```bash
python PwEvevee/build-system/release/check-chroma-version.py
```

The detector selects the release marked `recommended` on the installation page,
ignores prerelease entries, and records:

- the Chroma version;
- the Spotify version that release supports;
- `source_url` and `checked_at` for the most recent check attempt;
- a copy of the successful result under `last_success`, including its own
  `checked_at` time.

### Unavailable state

If the page cannot be fetched, changes shape, or no longer presents one
unambiguous recommended release, the detector writes:

```json
{
  "status": "unavailable",
  "version": null,
  "spotify_version": null,
  "last_success": { "...": "historical values only" }
}
```

Consumers must check `status == "current"` before displaying a version. The
`last_success` object is historical and must never be presented as the current
Chroma release.

The detector exits successfully for an expected fetch/parse failure after
recording the unavailable state, so an offline status check does not break an
IPA or Debian build. Use `--check` to compare without writing the metadata file.

### Licensing and distribution

Only factual version, compatibility, attribution, and official-link metadata is
stored here. Chroma's binaries and restricted components are not copied,
modified, bundled, or redistributed. Use Chroma's official patcher and follow
its published terms.
