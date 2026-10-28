'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const router = require('../../extension/OpenSpotify/Resources/router.js');
const content = fs.readFileSync(require.resolve('../../extension/OpenSpotify/Resources/content.js'), 'utf8');
const id = '6rqhFgbbKwnb9MLmUQDhG6';
const track = `https://open.spotify.com/track/${id}`;
function harness({ href = track, automatic = true, session = new Map(), framed = false, storageFails = false } = {}) {
    const listeners = {}, nodes = [], launches = [], intervals = [];
    let storageListener, messageListener, mutation;
    function element(tag) {
        const node = { tag, children: [], events: {}, isConnected: false,
            append(...items) { this.children.push(...items); items.forEach(x => { x.isConnected = true; }); },
            attachShadow() { return this.shadow = element('shadow'); },
            setAttribute() {}, getAttribute(key) { return this[key]; },
            addEventListener(event, callback) { this.events[event] = callback; },
            remove() { this.isConnected = false; }
        };
        nodes.push(node); return node;
    }
    const location = { get href() { return href; }, set href(value) { launches.push(value); } };
    const document = { visibilityState: 'visible', body: element('body'), head: element('head'),
        createElement: element, hints: [], querySelectorAll() { return this.hints; },
        addEventListener(name, fn) { listeners[name] = fn; }
    };
    const window = { location, addEventListener(name, fn) { listeners[name] = fn; } };
    window.top = framed ? {} : window;
    const browser = {
        runtime: { onMessage: { addListener(fn) { messageListener = fn; } } },
        storage: { local: { get: async () => { if (storageFails) throw Error('unavailable'); return { automatic }; } },
            onChanged: { addListener(fn) { storageListener = fn; } } }
    };
    const context = vm.createContext({ window, document, location, browser, OpenSpotifyRouter: router, Date, Set,
        sessionStorage: { getItem(key) { return session.get(key); }, setItem(key, value) { session.set(key, value); } },
        MutationObserver: class { constructor(fn) { mutation = fn; } observe() {} },
        setInterval(fn) { intervals.push(fn); }
    });
    vm.runInContext(content, context);
    const flush = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };
    return { launches, nodes, listeners, document, session, flush, context,
        tick() { intervals.forEach(fn => fn()); }, navigate(url) { href = url; },
        mutate() { mutation(); }, changeAutomatic(value) { storageListener({ automatic: { newValue: value } }, 'local'); },
        status() { return messageListener({ type: 'openSpotify.status' }); }
    };
}
test('opens once per destination despite DOM mutations, focus and repeated polling', async () => {
    const h = harness(); await h.flush();
    for (let i = 0; i < 10; i++) { h.tick(); h.mutate(); h.listeners.pageshow(); }
    assert.deepEqual(h.launches, [`spotify:track:${id}`]);
    h.navigate(`https://open.spotify.com/album/${id}`); h.tick();
    assert.deepEqual(h.launches, [`spotify:track:${id}`, `spotify:album:${id}`]);
    h.navigate(track); h.listeners.popstate(); assert.equal(h.launches.length, 2);
});
test('does not re-prompt after immediate reload', async () => {
    const first = harness(); await first.flush();
    const reload = harness({ session: first.session }); await reload.flush();
    assert.equal(reload.launches.length, 0);
    assert.ok(reload.nodes.some(node => node.tag === 'a' && node.href === `spotify:track:${id}`));
});
test('manual mode shows a real app link, with dismiss and setting changes', async () => {
    const h = harness({ automatic: false }); await h.flush();
    assert.equal(h.launches.length, 0);
    const link = h.nodes.find(node => node.tag === 'a');
    assert.equal(link.href, `spotify:track:${id}`);
    const dismiss = h.nodes.find(node => node.tag === 'button'); dismiss.events.click(); h.tick();
    assert.equal(h.document.body.children.filter(node => node.isConnected).length, 0);
    h.navigate(`https://open.spotify.com/album/${id}`); h.tick();
    assert.equal(h.document.body.children.filter(node => node.isConnected).length, 1);
    h.changeAutomatic(true); assert.deepEqual(h.launches, [`spotify:album:${id}`]);
});
test('hidden tabs wait until visible and subframes never launch', async () => {
    const h = harness(); h.document.visibilityState = 'hidden'; await h.flush();
    assert.equal(h.launches.length, 0);
    h.document.visibilityState = 'visible'; h.listeners.visibilitychange();
    assert.equal(h.launches.length, 1);
    const child = harness({ framed: true }); await child.flush(); assert.equal(child.launches.length, 0);
});
test('unknown pages remove fallback; delayed short-link metadata gets resolved', async () => {
    const h = harness({ href: 'https://spotify.link/abc' }); await h.flush();
    assert.equal(h.launches.length, 0);
    h.document.hints = [{ getAttribute(key) { return key === 'content' ? `spotify:track:${id}` : null; } }];
    h.mutate(); assert.equal(h.launches.length, 1);
    h.navigate('https://open.spotify.com/login'); h.tick();
    assert.equal(h.document.body.children.filter(node => node.isConnected).length, 0);
    assert.equal((await h.status()).uri, null);
});
test('storage failure falls back to manual and reinjection is idempotent', async () => {
    const h = harness({ storageFails: true }); await h.flush();
    assert.equal(h.launches.length, 0);
    assert.equal(h.nodes.filter(node => node.tag === 'a').length, 1);
    vm.runInContext(content, h.context); await h.flush();
    assert.equal(h.nodes.filter(node => node.tag === 'a').length, 1);
});
