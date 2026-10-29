(() => {
    "use strict";
    if (window.top !== window || globalThis.__pweeveeOpenSpotify) return;
    globalThis.__pweeveeOpenSpotify = true;
    const api = globalThis.browser;
    let automatic = true, current = null, panel = null, dismissed = null;
    let lastHref = "", lastAttempt = null, ready = false;
    const attempted = new Set();
    const storageKey = "pweevee.openSpotify.lastAttempt";
    try { lastAttempt = JSON.parse(sessionStorage.getItem(storageKey)); } catch { /* private browsing/storage disabled */ }
    function remember(uri) {
        attempted.add(uri);
        if (attempted.size > 100) attempted.delete(attempted.values().next().value);
        lastAttempt = { uri, time: Date.now() };
        try { sessionStorage.setItem(storageKey, JSON.stringify(lastAttempt)); } catch { /* optional */ }
    }
    function open(uri) {
        remember(uri); // Record before leaving; cancellation must not cause a prompt loop.
        try { window.location.href = uri; } catch { /* Safari may require a tap; keep the fallback. */ }
    }
    function render() {
        if (panel) panel.remove();
        panel = null;
        if (!current || dismissed === current || !document.body) return;
        panel = document.createElement("div");
        const shadow = panel.attachShadow({ mode: "closed" });
        const style = document.createElement("style");
        style.textContent = `:host{all:initial;position:fixed;bottom:calc(16px + env(safe-area-inset-bottom,0px));left:max(12px,env(safe-area-inset-left,0px));right:max(12px,env(safe-area-inset-right,0px));z-index:2147483647;display:flex;justify-content:center;pointer-events:none;color-scheme:dark}section{flex-wrap:wrap;font:16px/1.4 system-ui,sans-serif;display:flex;gap:8px;padding:8px;border:1px solid #777;border-radius:16px;background:#181818;box-shadow:0 4px 24px #0006;pointer-events:auto;max-width:400px}a,button{font:inherit;min-height:44px;box-sizing:border-box;display:flex;align-items:center;justify-content:center;border-radius:10px;padding:10px 14px;border:0;cursor:pointer}a{background:#1ed760;color:#000;text-decoration:none;font-weight:650}button{background:#333;color:#fff}a:active,button:active{filter:brightness(.8)}a:focus-visible,button:focus-visible{outline:3px solid #fff;outline-offset:2px}`;
        const section = document.createElement("section");
        section.setAttribute("aria-label", "Spotify app link");
        const link = document.createElement("a");
        link.textContent = "Open in Spotify";
        link.href = current;
        link.addEventListener("click", () => remember(current));
        const close = document.createElement("button");
        close.type = "button";
        close.textContent = "Dismiss";
        close.addEventListener("click", () => { dismissed = current; panel.remove(); panel = null; });
        section.append(link, close);
        shadow.append(style, section);
        document.body.append(panel);
    }
    function check() {
        if (!ready || document.visibilityState === "hidden") return;
        const href = location.href;
        const hints = [...document.querySelectorAll('link[rel="canonical"],meta[property="og:url"],meta[property="al:ios:url"]')]
            .map(node => node.getAttribute("href") || node.getAttribute("content"));
        const next = OpenSpotifyRouter.resolve(href, hints);
        if (next !== current || href !== lastHref) {
            current = next; lastHref = href;
            render();
        } else if (current && (!panel || !panel.isConnected) && dismissed !== current) render();
        if (!current || !automatic || attempted.has(current)) return;
        // Also suppress immediate re-prompts after reload/back navigation.
        if (lastAttempt?.uri === current && Date.now() - lastAttempt.time < 30000) {
            attempted.add(current);
            return;
        }
        open(current);
    }
    api.runtime.onMessage.addListener(message => {
        if (message?.type === "openSpotify.status") {
            check();
            return Promise.resolve({ uri: current, automatic });
        }
        return undefined;
    });
    api.storage.onChanged.addListener((changes, area) => {
        if (area === "local" && changes.automatic) {
            automatic = changes.automatic.newValue !== false;
            check();
        }
    });
    // A content script's History object is isolated from page JavaScript in Safari.
    // A lightweight URL poll catches pushState/replaceState without page-world injection.
    setInterval(check, 750);
    window.addEventListener("pageshow", check);
    window.addEventListener("popstate", check);
    window.addEventListener("hashchange", check);
    document.addEventListener("visibilitychange", check);
    new MutationObserver(check).observe(document.head || document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ["content", "href"] });
    api.storage.local.get("automatic").then(value => { automatic = value.automatic !== false; })
        .catch(() => { automatic = false; })
        .finally(() => { ready = true; check(); });
})();
