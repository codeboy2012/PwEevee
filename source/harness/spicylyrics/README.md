# Spicy Lyrics harness

`Shared/LyricsSources/SpicyLyrics.m` compiled and run on the Mac, with the two things it reaches
out through — the Spotify token it borrows and the POST — replaced by ones the test drives
(`stubs.m`). Everything else in it is the real file.

    ./build.sh

What it is for is the packed shape the API answers in: every distinct value in the document once,
then a stream of opcodes rebuilding it. `pack.ts` packs the test documents with the extension's
**own packer** (cloned into `build/`), so the decoder in `SpicyLyrics.m` is checked against the only
other implementation of that shape there is, rather than against a reading of it. The documents
cover all three shapes the API sends — `Syllable`, `Line` and `Static` — and the `-1` and `-3`
opcodes between them; the words in them are placeholders, not a song.

It also holds the source to what the chain needs of it: a track the server has queued (a 503 inside
a 200 envelope) counts as a failure, so `LyricsSources.m` does not keep the track as having no
lyrics, while a 404 is an answer and does not; a reply that does not hold together is refused
whole; and with no Spotify request seen yet to borrow a token from, nothing is sent at all.

What it cannot check is the live API: it is behind Cloudflare and answers only a signed-in Spotify
client, so the request as a whole is only proven on the phone.
