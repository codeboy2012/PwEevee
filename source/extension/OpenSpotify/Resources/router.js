/* Pure routing shared by the content script and regression tests. */
(function (root) {
    "use strict";
    const hosts = new Set(["open.spotify.com", "play.spotify.com", "spotify.link", "spotify.app.link", "spoti.fi"]);
    const shortHosts = new Set(["spotify.link", "spotify.app.link", "spoti.fi"]);
    const contentTypes = new Set(["track", "album", "artist", "playlist", "show", "episode", "audiobook"]);
    const token = /^[A-Za-z0-9_-]{1,200}$/;
    function parse(input, depth = 0) {
        if (typeof input !== "string" || input.length > 8192 || depth > 3) return null;
        let url;
        try { url = new URL(input); } catch { return null; }
        // Convert known URI forms back through the same path validator.
        if (url.protocol === "spotify:") {
            const body = input.slice(8).replace(/^\/\//, "");
            if (body.includes("?") || body.includes("#")) return null;
            return parse("https://open.spotify.com/" + body.replace(/:/g, "/"), depth + 1);
        }
        if (!["https:", "http:"].includes(url.protocol) || !hosts.has(url.hostname) || url.username || url.password || url.port) return null;
        if (shortHosts.has(url.hostname)) {
            // Branch share links sometimes contain their destination, sometimes redirect server-side.
            for (const key of ["$deeplink_path", "$canonical_url", "$fallback_url", "$ios_url", "$desktop_url", "link", "url"]) {
                const value = url.searchParams.get(key);
                if (!value) continue;
                const result = parse(value, depth + 1) ||
                    (!value.includes(":") && !value.startsWith("//") ? parse("https://open.spotify.com/" + value.replace(/^\//, ""), depth + 1) : null);
                if (result) return result;
            }
            return null;
        }
        let parts;
        try { parts = url.pathname.split("/").filter(Boolean).map(decodeURIComponent); } catch { return null; }
        // Locale and embed prefixes may occur in either order.
        for (let i = 0; i < 2; i++) {
            if (/^intl-[a-z]{2}(?:-[a-z]{2})?$/i.test(parts[0]) || parts[0] === "embed") parts.shift();
        }
        let uri = null;
        if (contentTypes.has(parts[0]) && parts.length === 2 && /^[A-Za-z0-9]{22}$/.test(parts[1])) {
            uri = "spotify:" + parts.join(":");
        } else if (parts[0] === "user" && parts.length === 4 && token.test(parts[1]) && parts[2] === "playlist" && /^[A-Za-z0-9]{22}$/.test(parts[3])) {
            uri = "spotify:playlist:" + parts[3];
        } else if (["user", "genre"].includes(parts[0]) && parts.length === 2 && token.test(parts[1])) {
            uri = "spotify:" + parts.join(":");
        } else if (parts[0] === "collection" && parts.length === 2 && ["tracks", "albums", "artists", "playlists", "your-episodes"].includes(parts[1])) {
            uri = "spotify:collection:" + parts[1];
        } else if (parts[0] === "search" && parts.length <= 2) {
            const query = parts[1] || url.searchParams.get("q");
            if (query && query.length <= 500) uri = "spotify:search:" + encodeURIComponent(query);
        }
        if (!uri) return null;
        // Preserve playback position; discard marketing/referral parameters.
        const time = url.searchParams.get("t");
        if (time && /^(?:\d{1,7}(?:\.\d{1,3})?|(?:\d{1,3}h)?(?:\d{1,3}m)?\d{1,3}s)$/.test(time) && ["track", "episode", "audiobook"].includes(parts[0])) uri += "?t=" + encodeURIComponent(time);
        return uri;
    }
    function resolve(href, hints = []) {
        let page;
        try { page = new URL(href); } catch { return null; }
        if (!hosts.has(page.hostname) || !["http:", "https:"].includes(page.protocol) || page.username || page.password || page.port) return null;
        const direct = parse(href);
        if (direct) return direct;
        // Metadata can lag behind SPA navigation: use it only on unresolved short links.
        if (!shortHosts.has(page.hostname)) return null;
        for (const hint of hints) { const uri = parse(hint); if (uri) return uri; }
        return null;
    }
    const api = { parse, resolve };
    if (typeof module !== "undefined" && module.exports) module.exports = api;
    else root.OpenSpotifyRouter = api;
})(globalThis);
