"""Optional browser UI smoke check. Requires Python Playwright and Google Chrome.
This mocks extension APIs; it does not replace on-device Safari extension testing.
"""
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / "extension/OpenSpotify/Resources"
OUT = ROOT / "out/safari-browser-check"
OUT.mkdir(parents=True, exist_ok=True)
ID = "6rqhFgbbKwnb9MLmUQDhG6"
MOCK = """
window.browser = {
  runtime: {onMessage: {addListener(fn) { window.extensionMessage = fn; }}},
  storage: {local: {async get() {return {automatic:false};}, async set(value) {window.saved=value;}},
    onChanged: {addListener(fn) {window.extensionSettings=fn;}}},
  tabs: {async query() {return [{id:1}];}, async sendMessage() {return {uri:'spotify:track:6rqhFgbbKwnb9MLmUQDhG6'};}}
};
// Open the otherwise closed shadow root solely to inspect the fallback in this test.
const attach = Element.prototype.attachShadow;
Element.prototype.attachShadow = function(options) {return attach.call(this, {...options, mode:'open'});};
"""
with sync_playwright() as p:
    browser = p.chromium.launch(channel="chrome", headless=True)
    context = browser.new_context(viewport={"width": 375, "height": 812}, device_scale_factor=1)
    context.add_init_script(MOCK)
    page = context.new_page()
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.route("https://open.spotify.com/**", lambda route: route.fulfill(
        body='<html><head><title>Spotify fixture</title></head><body><h1>Spotify page</h1><button id="page-button">Page action</button></body></html>', content_type="text/html"))
    page.goto(f"https://open.spotify.com/track/{ID}", wait_until="networkidle")
    for name in ("router.js", "content.js"):
        page.add_script_tag(content=(RESOURCES / name).read_text())
    fallback = page.get_by_role("link", name="Open in Spotify")
    fallback.wait_for()
    assert fallback.get_attribute("href") == f"spotify:track:{ID}"
    for width, height, label in [(375, 812, "portrait"), (812, 375, "landscape"), (320, 568, "small"), (1024, 768, "tablet")]:
        page.set_viewport_size({"width": width, "height": height})
        for control in (fallback, page.get_by_role("button", name="Dismiss")):
            box = control.bounding_box()
            assert box and box["height"] >= 44 and box["width"] >= 44
            assert box["x"] >= 0 and box["x"] + box["width"] <= width
            assert box["y"] >= 0 and box["y"] + box["height"] <= height
        assert page.evaluate("document.documentElement.scrollWidth <= innerWidth")
        page.screenshot(path=str(OUT / f"fallback-{label}.png"))
    # User dismissal survives polling; SPA navigation creates the next link.
    page.get_by_role("button", name="Dismiss").click()
    page.wait_for_timeout(850)
    assert fallback.count() == 0
    page.evaluate(f"history.pushState(null, '', '/album/{ID}')")
    page.get_by_role("link", name="Open in Spotify").wait_for()
    assert page.get_by_role("link", name="Open in Spotify").get_attribute("href") == f"spotify:album:{ID}"
    # Recover if a SPA replaces the body (the interval restores the fallback).
    page.evaluate("document.body.replaceChildren()")
    page.get_by_role("link", name="Open in Spotify").wait_for()
    page.emulate_media(reduced_motion="reduce")
    page.get_by_role("link", name="Open in Spotify").focus()
    assert page.get_by_role("link", name="Open in Spotify").evaluate("el => el === el.getRootNode().activeElement")
    # Serve popup resources without running a local web server.
    def resource(route):
        name = route.request.url.rsplit("/", 1)[-1]
        mime = "text/html" if name.endswith("html") else "text/css" if name.endswith("css") else "application/javascript"
        route.fulfill(body=(RESOURCES / name).read_text(), content_type=mime)
    page.route("https://extension.test/**", resource)
    page.set_viewport_size({"width": 375, "height": 600})
    page.goto("https://extension.test/popup.html", wait_until="networkidle")
    page.get_by_role("link", name="Open in Spotify").wait_for()
    checkbox = page.get_by_role("checkbox", name="Open supported links automatically")
    assert not checkbox.is_checked()
    checkbox.check()
    assert page.evaluate("window.saved.automatic") is True
    for scheme in ("light", "dark"):
        page.emulate_media(color_scheme=scheme)
        page.screenshot(path=str(OUT / f"popup-{scheme}.png"))
    assert not errors, errors
    context.close()
    browser.close()
print("Browser checks passed: fallback sizes, dismissal, SPA navigation, body replacement, keyboard focus, popup settings and light/dark rendering.")
