"use strict";
const checkbox = document.querySelector("#automatic");
const status = document.querySelector("#status");
const openLink = document.querySelector("#open");
async function setup() {
    checkbox.disabled = true;
    try {
        const settings = await browser.storage.local.get("automatic");
        checkbox.checked = settings.automatic !== false;
        checkbox.disabled = false;
    } catch { status.textContent = "Settings are unavailable. Reopen the extension to try again."; return; }
    checkbox.addEventListener("change", async () => {
        try { await browser.storage.local.set({ automatic: checkbox.checked }); }
        catch { checkbox.checked = !checkbox.checked; status.textContent = "Could not save the setting. Please try again."; }
    });
    try {
        const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
        const result = await browser.tabs.sendMessage(tab.id, { type: "openSpotify.status" });
        if (!result?.uri) { status.textContent = "No supported Spotify content link on this page."; return; }
        status.textContent = "This link can open in the Spotify app.";
        openLink.href = result.uri;
        openLink.hidden = false;
    } catch { status.textContent = "Open a Spotify link and allow this extension on that website."; }
}
setup();
