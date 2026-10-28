'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { parse, resolve } = require('../../extension/OpenSpotify/Resources/router.js');
const id = '6rqhFgbbKwnb9MLmUQDhG6';
for (const kind of ['track', 'album', 'artist', 'playlist', 'show', 'episode', 'audiobook']) {
    test(`routes ${kind} links with locale/embed prefixes and tracking`, () => {
        for (const prefix of ['', 'intl-en/', 'intl-pt-BR/', 'embed/', 'intl-de/embed/', 'embed/intl-fr/']) {
            assert.equal(parse(`https://open.spotify.com/${prefix}${kind}/${id}?si=tracking&utm_source=test`), `spotify:${kind}:${id}`);
        }
    });
}
test('retains playback timestamps but filters untrusted query data', () => {
    for (const t of ['32', '32.5', '1m30s', '1h2m3s']) assert.equal(parse(`https://open.spotify.com/episode/${id}?t=${t}&si=test`), `spotify:episode:${id}?t=${t}`);
    assert.equal(parse(`https://open.spotify.com/track/${id}?t=javascript:alert(1)`), `spotify:track:${id}`);
    assert.equal(parse(`https://open.spotify.com/album/${id}?t=23`), `spotify:album:${id}`);
});
test('search, users, collections and legacy playlists', () => {
    assert.equal(parse('https://open.spotify.com/search/Bj%C3%B6rk%20%26%20friends'), 'spotify:search:Bj%C3%B6rk%20%26%20friends');
    assert.equal(parse('https://open.spotify.com/search?q=hello+world'), 'spotify:search:hello%20world');
    assert.equal(parse('https://open.spotify.com/user/alice'), 'spotify:user:alice');
    assert.equal(parse(`https://open.spotify.com/user/alice/playlist/${id}`), `spotify:playlist:${id}`);
    assert.equal(parse('https://play.spotify.com/collection/tracks'), 'spotify:collection:tracks');
    assert.equal(parse('https://open.spotify.com/genre/pop-page'), 'spotify:genre:pop-page');
});
test('short-link destinations and URI metadata', () => {
    for (const host of ['spotify.link', 'spotify.app.link', 'spoti.fi']) {
        assert.equal(parse(`https://${host}/abc?%24deeplink_path=track%2F${id}`), `spotify:track:${id}`);
        assert.equal(parse(`https://${host}/abc?link=${encodeURIComponent(`https://open.spotify.com/track/${id}`)}`), `spotify:track:${id}`);
        assert.equal(resolve(`https://${host}/abc`, [`spotify:track:${id}`]), `spotify:track:${id}`);
        assert.equal(resolve(`https://${host}/abc`, ['https://evil.example/track/' + id]), null);
        assert.equal(parse(`https://${host}/opaque`), null);
    }
    assert.equal(parse(`spotify://track/${id}`), `spotify:track:${id}`);
});
test('never trusts stale metadata on main Spotify pages or external pages', () => {
    const stale = `https://open.spotify.com/track/${id}`;
    for (const page of ['https://open.spotify.com/', 'https://open.spotify.com/login', 'https://example.com/', 'https://open.spotify.com/search']) assert.equal(resolve(page, [stale]), null);
    assert.equal(resolve(`https://open.spotify.com/album/${id}`, [stale]), `spotify:album:${id}`);
});
test('rejects malformed inputs, fake hosts, credentials, unsupported routes and embedded code', () => {
    for (const input of [null, {}, '', 'not a URL', 'javascript:alert(1)', `https://open.spotify.com.evil.test/track/${id}`, `https://evil.test/?url=https://open.spotify.com/track/${id}`, `https://open.spotify.com@evil.test/track/${id}`, `https://user@open.spotify.com/track/${id}`, `https://open.spotify.com:8443/track/${id}`, `ftp://open.spotify.com/track/${id}`, 'https://open.spotify.com/track/bad', `https://open.spotify.com/track/${id}/extra`, 'https://open.spotify.com/search/%E0%A4%A', 'https://open.spotify.com/login', 'https://open.spotify.com/premium', 'spotify:eevee/open.spotify.com/track/' + id, 'https://spotify.app.link/a?url=javascript%3Aalert(1)', 'https://spotify.app.link/a?url=' + 'x'.repeat(9000)]) assert.equal(parse(input), null, String(input));
});
test('bounds nested short links', () => {
    let url = `https://open.spotify.com/track/${id}`;
    for (let i = 0; i < 12; i++) url = 'https://spotify.link/a?url=' + encodeURIComponent(url);
    assert.equal(parse(url), null);
});
