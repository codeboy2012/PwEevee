/* ==========================================================================
   PwEevee — progressive enhancement
   ==========================================================================
   Every page is fully functional with JavaScript disabled: all release data is
   rendered into the HTML at publish time by
   PwEvevee/build-system/release/render-site.pl.

   This file only adds behaviour on top:
     1. html.js flag (so CSS only hides revealed content when JS can show it)
     2. accessible mobile navigation
     3. scroll reveal (skipped entirely under prefers-reduced-motion)
     4. the falling-star field in the dark regions
     5. copy-to-clipboard for checksums
     6. release filtering and search on the release history page
     7. a hydration fallback: if a data region was left empty because the
        renderer has not run, fetch the generated JSON, show skeletons, and
        render a compact card — or a real error state with a retry.

   No dependencies, no framework, no build step.
   ========================================================================== */
(function () {
  'use strict';

  var doc = document;
  var root = doc.documentElement;
  var reduceMotion = window.matchMedia
    ? window.matchMedia('(prefers-reduced-motion: reduce)')
    : { matches: false };

  root.classList.add('js');

  function on(el, ev, fn, opts) { if (el) el.addEventListener(ev, fn, opts || false); }
  function all(sel, ctx) { return Array.prototype.slice.call((ctx || doc).querySelectorAll(sel)); }
  function one(sel, ctx) { return (ctx || doc).querySelector(sel); }

  /* A theme change has to reach the star field, which is painted rather than
     styled. A plain callback list keeps that dependency explicit and avoids
     relying on CustomEvent. */
  var themeWatchers = [];
  function onThemeChange(fn) { themeWatchers.push(fn); }
  function notifyThemeChange() {
    for (var i = 0; i < themeWatchers.length; i++) themeWatchers[i]();
  }

  /* Mirrors the CSS cascade exactly: an explicit data-theme wins, then the
     device preference, and with no preference at all the answer is dark. */
  var mqDark = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
  var mqLight = window.matchMedia ? window.matchMedia('(prefers-color-scheme: light)') : null;

  function effectiveTheme() {
    var set = root.getAttribute('data-theme');
    if (set === 'light' || set === 'dark') return set;
    if (mqDark && mqDark.matches) return 'dark';
    if (mqLight && mqLight.matches) return 'light';
    return 'dark';
  }

  /* ------------------------------------------------ 2. mobile navigation */

  (function nav() {
    var toggle = one('[data-nav-toggle]');
    var drawer = one('[data-nav-drawer]');
    if (!toggle || !drawer) return;

    var open = false;

    function setOpen(next) {
      open = next;
      toggle.setAttribute('aria-expanded', String(open));
      if (open) {
        drawer.setAttribute('data-open', '');
      } else {
        drawer.removeAttribute('data-open');
      }
    }

    setOpen(false);

    on(toggle, 'click', function () { setOpen(!open); });

    // Escape closes and returns focus to the button
    on(doc, 'keydown', function (e) {
      if (!open) return;
      if (e.key === 'Escape' || e.key === 'Esc') {
        setOpen(false);
        toggle.focus();
        return;
      }
      // keep tabbing inside the drawer while it is open
      if (e.key !== 'Tab') return;
      var focusable = all('a[href], button:not([disabled]), input', drawer)
        .filter(function (el) { return el.offsetParent !== null; });
      if (!focusable.length) return;
      var first = focusable[0];
      var last = focusable[focusable.length - 1];
      if (e.shiftKey && (doc.activeElement === first || doc.activeElement === toggle)) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && doc.activeElement === last) {
        e.preventDefault();
        toggle.focus();
      }
    });

    // clicking anywhere else closes it
    on(doc, 'click', function (e) {
      if (!open) return;
      if (drawer.contains(e.target) || toggle.contains(e.target)) return;
      setOpen(false);
    });

    // a link inside the drawer navigates, so close first
    on(drawer, 'click', function (e) {
      if (e.target.closest && e.target.closest('a')) setOpen(false);
    });

    // Leaving the mobile breakpoint must not leave a stranded drawer. This value
    // is the counterpart of the nav's own media query in pweevee.css
    // (max-width: 980px) and has to move with it.
    var wide = window.matchMedia('(min-width: 981px)');
    var onChange = function (e) { if (e.matches && open) setOpen(false); };
    if (wide.addEventListener) wide.addEventListener('change', onChange);
    else if (wide.addListener) wide.addListener(onChange);
  }());

  /* ---------------------------------------------------- 2b. theme control */

  /* The initial theme is decided by CSS, and assets/theme.js has already applied
     any stored override before the first paint. This block is only the control:
     it reflects the current choice, writes a new one, and persists it.

       System  removes data-theme and the stored key, so prefers-color-scheme
               takes over again — and dark when there is no preference at all.
       Light   sets data-theme="light" and stores it.
       Dark    sets data-theme="dark" and stores it.

     There are two instances of the control (the bar and the mobile drawer), so
     every write updates all of them. */
  (function theme() {
    var KEY = 'pweevee-theme';
    var groups = all('[data-theme-control]');
    if (!groups.length) return;

    var buttons = all('[data-theme-set]');

    function stored() {
      try {
        var v = window.localStorage.getItem(KEY);
        return (v === 'light' || v === 'dark') ? v : 'system';
      } catch (e) {
        return 'system';
      }
    }

    function persist(choice) {
      try {
        if (choice === 'system') window.localStorage.removeItem(KEY);
        else window.localStorage.setItem(KEY, choice);
      } catch (e) {
        /* storage unavailable: the choice still applies for this page view */
      }
    }

    function mark(choice) {
      buttons.forEach(function (b) {
        b.setAttribute('aria-pressed', String(b.getAttribute('data-theme-set') === choice));
      });
    }

    function select(choice, persistIt) {
      if (choice !== 'light' && choice !== 'dark') choice = 'system';
      if (choice === 'system') root.removeAttribute('data-theme');
      else root.setAttribute('data-theme', choice);
      if (persistIt) persist(choice);
      mark(choice);
      notifyThemeChange();
    }

    buttons.forEach(function (b) {
      on(b, 'click', function () { select(b.getAttribute('data-theme-set'), true); });
    });

    /* In System mode the device can change under us — someone flipping their OS
       to dark at sunset, for instance — and the star field has to be told. */
    var followDevice = function () {
      if (stored() !== 'system') return;
      notifyThemeChange();
    };
    [mqDark, mqLight].forEach(function (mq) {
      if (!mq) return;
      if (mq.addEventListener) mq.addEventListener('change', followDevice);
      else if (mq.addListener) mq.addListener(followDevice);
    });

    /* Reflect what is already applied. Not persisted: reading must not turn an
       implicit "follow the device" into a stored explicit choice. */
    mark(stored());
  }());

  /* ------------------------------------------------------ 3. scroll reveal */

  (function reveal() {
    var targets = all('.reveal');
    if (!targets.length) return;

    if (reduceMotion.matches || !('IntersectionObserver' in window)) {
      targets.forEach(function (el) { el.classList.add('is-in'); });
      return;
    }

    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-in');
        io.unobserve(entry.target);
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.06 });

    targets.forEach(function (el, i) {
      // a small stagger inside the same group reads as one motion, not twelve
      var group = el.getAttribute('data-reveal-group');
      if (group) el.style.transitionDelay = (Math.min(i, 6) * 55) + 'ms';
      io.observe(el);
    });
  }());

  /* ------------------------------------------------ 3b. statistics count-up */

  /* The stats band is server-rendered with final values, so this is decoration on
     top of real data, never a source of it:

       - only non-negative integers the renderer already displays animate; the
         unavailable state (.stats-band__missing) renders no numbers at all, so
         nothing is ever invented here;
       - roughly 700 ms, ease-out cubic, no bounce; intermediates are clamped at
         zero so a downward correction can never display a negative;
       - unchanged values never re-animate (a per-element "settled value" guards
         replays), and each page load is a deliberate first appearance, not a
         session-persisted state — the band animates when it scrolls into view,
         then keeps still;
       - prefers-reduced-motion, a hidden tab, missing IntersectionObserver or
         missing requestAnimationFrame all fall through to the final value
         immediately, which was the server-rendered state anyway;
       - the final string is written last and written once, so screen-reader
         output sees only meaningful amounts: the announcing paragraph below is
         created lazily and only after a value GENUINELY CHANGES, never on first
         paint, and it exists outside the <dl> because a <dl> only holds dt/dd
         groups.

     The tiny window.PwEeveeStats surface is deliberate: the site is static, so
     "data arrives mid-session" only happens if a later update path (like the
     hydration fallback) asks for it — update(el, to) animates from the value
     currently displayed to the new one, marks a genuine change, and does the
     one-time announcement. IT performs no fetching of its own. */
  (function statCount() {
    var STATS = all('.stats-band .stats-band__num');
    if (!STATS.length) return;

    var announcer = null;   // created lazily, on the first genuine change only
    var DURATION = 700;     // brief on purpose
    var flights = [];       // one entry per in-flight number; the shared driver below
                            // steps them all, exactly like the star field pattern: ONE
                            // animation loop per concern, not one per element.
    var rafId = 0;

    // Same formatting fmt_count() renders server-side: thousands separators,
    // no decimal point, no compact notation — so the mid-animation value and
    // the settled value are the same shape.
    function group(n) {
      var s = String(Math.round(n));
      return s.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    function parseStat(el) {
      var raw = (el.textContent || '').replace(/,/g, '').trim();
      return /^\d+$/.test(raw) ? parseInt(raw, 10) : null;
    }

    function setFinal(flight) {
      var el = flight.el;
      el.textContent = group(flight.to);
      el.setAttribute('data-stat-value', String(flight.to));
      el.__statSettled = flight.to;
      el.classList.remove('stats-band__num--changed');
      if (flight.changed) {
        announceOne(flight.label, group(flight.to));
        // Add the highlight on the next frame so re-adding it after a previous
        // change genuinely restarts the CSS animation instead of no-opping.
        // The rAF guard matters: a fallback caller may have arrived here because
        // requestAnimationFrame does not exist at all.
        if (window.requestAnimationFrame) {
          requestAnimationFrame(function () {
            el.classList.add('stats-band__num--changed');
            el.addEventListener('animationend', function () {
              el.classList.remove('stats-band__num--changed');
            }, { once: true });
          });
        } else {
          el.classList.add('stats-band__num--changed');
        }
      }
    }

    /* One driver for every number on the band. Timestamp-based, so a hidden tab
       pauses rAF and a returning tab simply finds the flight done — no timer, no
       per-element callback. */
    function driver(t) {
      rafId = 0;
      var keep = [];
      for (var i = 0; i < flights.length; i++) {
        var f = flights[i];
        if (f.start === null) {
          if (t < f.notBefore) { keep.push(f); continue; }  // stagger window not open yet
          f.start = t;
        }
        var p = Math.min(Math.max((t - f.start) / DURATION, 0), 1);
        var v = f.from + (f.to - f.from) * (1 - Math.pow(1 - p, 3));  // ease-out cubic
        if (v < 0) v = 0;   // never below zero mid-flight
        f.el.textContent = group(v);
        if (p < 1) keep.push(f);
        else setFinal(f);
      }
      flights = keep;
      if (flights.length && window.requestAnimationFrame) rafId = requestAnimationFrame(driver);
    }

    function ensureDriver() {
      if (!rafId && flights.length && window.requestAnimationFrame) {
        rafId = requestAnimationFrame(driver);
      }
    }

    function animate(el, from, to, changed, staggerMs) {
      if (el.__statSettled === to) return;   // identical target: no replay, nothing to update

      // rapid updates: drop any in-flight entry for the same element first, so the
      // newest target always wins and there is never a doubled number
      flights = flights.filter(function (f) { return f.el !== el; });

      var issuer = el.closest ? el.closest('.stats-band__item') : null;
      var dt = issuer && issuer.querySelector ? issuer.querySelector('dt') : null;
      var label = dt && dt.textContent ? dt.textContent.replace(/\s+/g, ' ').trim() : '';

      if (reduceMotion.matches || !window.requestAnimationFrame || doc.hidden || from === to) {
        setFinal({ el: el, to: to, changed: changed, label: label });
        return;
      }

      flights.push({
        el: el, from: from, to: to, changed: changed, label: label,
        start: null,
        notBefore: staggerMs ? (window.performance && performance.now ? performance.now() + staggerMs : 0) : 0
      });
      ensureDriver();
    }

    function announceOne(label, value) {
      if (!announcer) {
        announcer = doc.createElement('p');
        announcer.className = 'visually-hidden';
        announcer.setAttribute('aria-live', 'polite');
        var band = one('.stats-band');
        if (band && band.insertAdjacentElement) band.insertAdjacentElement('afterend', announcer);
        else return;
      }
      announcer.textContent = label ? label + ': ' + value : value;
    }

    if (reduceMotion.matches || !('IntersectionObserver' in window)) {
      // final value was already in the markup; nothing to start, nothing to store
      return;
    }

    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        var el = entry.target;
        io.unobserve(el);
        var to = parseStat(el);
        if (to === null || el.__statSettled === to) return; // unreadable or already settled — never invent
        animate(el, 0, to, false, (STATS.indexOf ? STATS.indexOf(el) : 0) * 60);
      });
    }, { rootMargin: '0px 0px -4% 0px', threshold: 0.35 });

    STATS.forEach(function (el, i) {
      // a hair of stagger so the band counts as one motion, not five
      el.style.transitionDelay = Math.min(i, 5) * 60 + 'ms';
      io.observe(el);
    });

    // The one hook a future data-refresh path uses. Guards are identical —
    // updates are only ever driven by values from the generated snapshot.
    window.PwEeveeStats = {
      update: function (el, to) {
        if (!el || typeof to !== 'number' || to < 0 || !isFinite(to)) return;
        var from = parseStat(el);
        if (from === null) from = 0;
        animate(el, from, Math.round(to), from !== Math.round(to), 0);
      }
    };
  }());

  /* ------------------------------------------------- 4. falling-star field */

  /* Restraint is the whole point. Tiny specks, very low opacity, a slow
     downward drift, three depth layers, and roughly one speck in eight a little
     brighter. It is not a galaxy, there are no shooting stars, and it only ever
     paints inside the dark regions that ask for it.

     Everything here is additive: the markup ships an empty <canvas>, so with
     JavaScript off, or under prefers-reduced-motion, the dark surface is simply
     plain. One shared rAF loop drives every field, a field that has scrolled
     out of view stops being drawn, and a hidden tab stops the loop entirely. */
  (function starfield() {
    var mounts = all('[data-starfield]');
    if (!mounts.length) return;
    if (reduceMotion.matches) return;
    if (!window.requestAnimationFrame) return;

    // Depth. Nearer specks are a touch larger, brighter and faster; the
    // difference is small on purpose — it should read as air, not as parallax.
    var LAYERS = [
      { rMin: 0.30, rMax: 0.60, aMin: 0.08, aMax: 0.18, vMin: 3,  vMax: 6  },
      { rMin: 0.45, rMax: 0.85, aMin: 0.12, aMax: 0.26, vMin: 5,  vMax: 10 },
      { rMin: 0.60, rMax: 1.15, aMin: 0.18, aMax: 0.38, vMin: 9,  vMax: 16 }
    ];
    var AREA_PER_STAR = 21000;   // CSS px² — deliberately sparse
    var MAX_STARS = 64;          // hard cap, so a 4K footer stays cheap
    var MIN_STARS = 10;
    var DPR = Math.min(window.devicePixelRatio || 1, 1.5);
    var TINT = [144, 160, 213];  // the logo blue, lifted: a few specks only

    var fields = [];
    var visible = [];
    var frame = null;
    var last = 0;

    /* How strongly to paint, read from CSS so the decision lives with the rest
       of the design: 1 on dark, 0.45 on light. The band is dark in both themes,
       so the specks stay white-on-dark and never become dark flecks on paper —
       but the light theme still has no business looking like a night sky. */
    var intensity = 1;
    function readIntensity() {
      var v = 1;
      try {
        var raw = window.getComputedStyle(root).getPropertyValue('--star-intensity');
        var n = parseFloat(raw);
        if (!isNaN(n) && n >= 0 && n <= 1) v = n;
      } catch (e) {
        // no computed style: fall back to the dark-theme value
        v = effectiveTheme() === 'light' ? 0.45 : 1;
      }
      intensity = v;
    }
    readIntensity();

    onThemeChange(function () {
      readIntensity();
      // repaint immediately so the change is not held until the next frame drops
      if (!frame && visible.length) start();
    });

    mounts.forEach(function (mount) {
      var canvas = one('canvas', mount);
      if (!canvas || !canvas.getContext) return;
      var ctx = canvas.getContext('2d');
      if (!ctx) return;
      fields.push({ mount: mount, canvas: canvas, ctx: ctx, w: 0, h: 0, stars: [] });
    });
    if (!fields.length) return;

    function rand(a, b) { return a + Math.random() * (b - a); }

    function seed(f) {
      var target = Math.round((f.w * f.h) / AREA_PER_STAR);
      if (target > MAX_STARS) target = MAX_STARS;
      if (target < MIN_STARS) target = MIN_STARS;

      f.stars = [];
      for (var i = 0; i < target; i++) {
        var L = LAYERS[i % LAYERS.length];
        var bright = (i % 8) === 3;             // "occasional", not "many"
        f.stars.push({
          x: Math.random() * f.w,
          y: Math.random() * f.h,
          r: rand(L.rMin, L.rMax) + (bright ? 0.55 : 0),
          a: rand(L.aMin, L.aMax) + (bright ? 0.18 : 0),
          vy: rand(L.vMin, L.vMax),
          vx: rand(-2.2, -0.4),                // a common, gentle drift
          tint: (i % 11) === 5,                // a handful carry the logo blue
          // a slow, shallow twinkle on the brighter ones only
          tw: bright ? rand(0.25, 0.5) : 0,
          ph: Math.random() * Math.PI * 2
        });
      }
    }

    function resize(f) {
      var r = f.mount.getBoundingClientRect();
      var w = Math.max(1, Math.round(r.width));
      var h = Math.max(1, Math.round(r.height));
      if (w === f.w && h === f.h) return;
      f.w = w;
      f.h = h;
      f.canvas.width = Math.round(w * DPR);
      f.canvas.height = Math.round(h * DPR);
      f.canvas.style.width = w + 'px';
      f.canvas.style.height = h + 'px';
      f.ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
      seed(f);
    }

    function draw(f, dt, t) {
      var ctx = f.ctx;
      ctx.clearRect(0, 0, f.w, f.h);

      for (var i = 0; i < f.stars.length; i++) {
        var s = f.stars[i];
        s.y += s.vy * dt;
        s.x += s.vx * dt;

        if (s.y - s.r > f.h) { s.y = -s.r; s.x = Math.random() * f.w; }
        if (s.x + s.r < 0) { s.x = f.w + s.r; }

        var a = s.a * intensity;
        if (a < 0.004) continue;                 // nothing to draw at this theme
        if (s.tw) a *= 0.72 + 0.28 * Math.sin(t * s.tw + s.ph);

        ctx.beginPath();
        ctx.arc(s.x, s.y, s.r, 0, 6.2832);
        ctx.fillStyle = s.tint
          ? 'rgba(' + TINT[0] + ',' + TINT[1] + ',' + TINT[2] + ',' + a.toFixed(3) + ')'
          : 'rgba(255,255,255,' + a.toFixed(3) + ')';
        ctx.fill();
      }
    }

    function tick(now) {
      frame = null;
      if (!visible.length) return;

      var dt = last ? (now - last) / 1000 : 0.016;
      if (dt > 0.05) dt = 0.05;           // a tab switch must not teleport them
      last = now;
      var t = now / 1000;

      for (var i = 0; i < visible.length; i++) draw(visible[i], dt, t);
      frame = window.requestAnimationFrame(tick);
    }

    function start() {
      if (frame || !visible.length || doc.hidden) return;
      last = 0;
      frame = window.requestAnimationFrame(tick);
    }

    function stop() {
      if (!frame) return;
      window.cancelAnimationFrame(frame);
      frame = null;
    }

    function setVisible(f, isVisible) {
      var at = visible.indexOf(f);
      if (isVisible && at === -1) {
        resize(f);
        visible.push(f);
        start();
      } else if (!isVisible && at !== -1) {
        visible.splice(at, 1);
        f.ctx.clearRect(0, 0, f.w, f.h);
        if (!visible.length) stop();
      }
    }

    if ('IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          var f = fields.filter(function (x) { return x.mount === entry.target; })[0];
          if (f) setVisible(f, entry.isIntersecting);
        });
      }, { rootMargin: '120px 0px' });
      fields.forEach(function (f) { io.observe(f.mount); });
    } else {
      fields.forEach(function (f) { setVisible(f, true); });
    }

    if ('ResizeObserver' in window) {
      var ro = new ResizeObserver(function (entries) {
        entries.forEach(function (entry) {
          var f = fields.filter(function (x) { return x.mount === entry.target; })[0];
          if (f) resize(f);
        });
      });
      fields.forEach(function (f) { ro.observe(f.mount); });
    } else {
      var resizeTimer = null;
      on(window, 'resize', function () {
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(function () {
          fields.forEach(function (f) { resize(f); });
        }, 150);
      });
    }

    on(doc, 'visibilitychange', function () {
      if (doc.hidden) stop(); else start();
    });

    // switching reduced-motion on mid-visit must actually stop the motion
    var onReduce = function (e) {
      if (!e.matches) return;
      stop();
      visible.length = 0;
      fields.forEach(function (f) { f.ctx.clearRect(0, 0, f.w, f.h); });
    };
    if (reduceMotion.addEventListener) reduceMotion.addEventListener('change', onReduce);
    else if (reduceMotion.addListener) reduceMotion.addListener(onReduce);
  }());

  /* ------------------------------------------------------- 5. copy buttons */

  (function copy() {
    /* the renderer emits only data-copy-from (the id of the value element);
       data-copy carries a literal value for hand-written buttons. Both bind. */
    var buttons = all('[data-copy], [data-copy-from]');
    if (!buttons.length) return;

    buttons.forEach(function (btn) {
      var label = btn.querySelector('[data-copy-label]') || btn;
      var original = label.textContent;

      on(btn, 'click', function () {
        var value = btn.getAttribute('data-copy');
        var target = btn.getAttribute('data-copy-from');
        if (target) {
          var src = doc.getElementById(target);
          if (src) value = src.textContent.trim();
        }
        if (!value) return;

        var done = function (ok) {
          label.textContent = ok ? 'Copied' : 'Press Ctrl+C';
          if (ok) btn.setAttribute('data-copied', '');
          btn.setAttribute('aria-live', 'polite');
          setTimeout(function () {
            label.textContent = original;
            btn.removeAttribute('data-copied');
          }, 1900);
        };

        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(value).then(function () { done(true); },
                                                    function () { selectFallback(value, done); });
        } else {
          selectFallback(value, done);
        }
      });
    });

    // no clipboard permission: select the text so the user can copy it manually
    function selectFallback(value, done) {
      var ta = doc.createElement('textarea');
      ta.value = value;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      doc.body.appendChild(ta);
      ta.select();
      var ok = false;
      try { ok = doc.execCommand('copy'); } catch (e) { ok = false; }
      doc.body.removeChild(ta);
      done(ok);
    }
  }());

  /* ------------------------------------- 5b. download click feedback */

  /* A download is a navigation, so the page gives no natural signal that the
     click landed. One short, quiet state change confirms it without pretending
     to know anything about the transfer. */
  (function downloadFeedback() {
    if (reduceMotion.matches) return;

    on(doc, 'click', function (e) {
      var btn = e.target.closest && e.target.closest('a[download], a[href$=".ipa"]');
      if (!btn) return;
      btn.setAttribute('data-fired', '');
      setTimeout(function () { btn.removeAttribute('data-fired'); }, 700);
    });
  }());

  /* --------------------------------------------- 6. release filter/search */

  /* The page arrives already filtered to its default project — render-site.pl
     writes the hidden attribute into the markup, so the intended view is correct
     with JavaScript switched off and there is no flash of the wrong content.

     This block takes over from there:
       - reads ?project= so a refresh or a shared link keeps the selection
       - filters by project and by free-text search
       - hides a month heading once everything under it is filtered out
       - keeps the URL in step, and answers browser back/forward

     Hiding uses BOTH the hidden attribute (for assistive technology and no-CSS)
     and the .is-filtered class, because the cards set `display: grid` and an
     author display rule beats the user-agent [hidden] rule. */
  (function filter() {
    var scope = one('[data-filter-scope]');
    if (!scope) return;

    var chips = all('[data-filter]', scope);
    var input = one('[data-filter-search]', scope);
    var sortSel = one('[data-filter-sort]', scope);
    var items = all('[data-release-item]', scope);
    var groups = all('[data-release-group]', scope);
    var empty = one('[data-filter-empty]', scope);
    var count = one('[data-filter-count]', scope);
    if (!items.length) return;

    var PARAM = scope.getAttribute('data-filter-param') || 'project';
    var SORT_PARAM = 'sort';
    var DEFAULT = scope.getAttribute('data-filter-default') || 'all';
    var sort = 'newest';

    var known = {};
    chips.forEach(function (c) {
      var v = c.getAttribute('data-filter');
      if (v) known[v] = c;
    });

    /* Accept the shapes people actually type or share, and normalise them onto
       the slugs the markup uses. Anything unrecognised falls back to the
       default rather than showing an empty page. */
    function normalise(value) {
      if (!value) return null;
      var v = String(value).trim().toLowerCase();
      if (known[v]) return v;
      var alias = {
        'all': 'all',
        'everything': 'all',
        'pweevee': 'pweevee',
        'pw-eevee': 'pweevee',
        'spotipw': 'spotipw',
        'spoti.pw': 'spotipw',
        'spoti-pw': 'spotipw',
        'eeveespotify': 'eeveespotify',
        'eevee': 'eeveespotify',
        'eevee-spotify': 'eeveespotify',
        'eeveespotifyreincarnated': 'eeveespotify',
        'esr': 'eeveespotify'
      }[v];
      return (alias && known[alias]) ? alias : null;
    }

    function fromUrl() {
      try {
        var params = new URLSearchParams(window.location.search);
        return normalise(params.get(PARAM));
      } catch (e) {
        var m = window.location.search.match(new RegExp('[?&]' + PARAM + '=([^&]*)'));
        return m ? normalise(decodeURIComponent(m[1].replace(/\+/g, ' '))) : null;
      }
    }

    var active = fromUrl() || DEFAULT;

    /* Sorting re-orders the rendered timeline in the DOM: each month group's
       cards are re-appended in the chosen direction, then the groups themselves.
       The empty state keeps last place so it stays below the timeline. With JS
       off the select is hidden and the rendered newest-first order simply holds. */
    function orderOf(el) { return +(el.getAttribute('data-epoch') || 0); }

    function layout() {
      groups.forEach(function (group) {
        var box = one('.timeline', group);
        if (!box) return;
        var cards = all('[data-release-item]', group);
        if (sort === 'oldest') cards.reverse();
        cards.forEach(function (c) { box.appendChild(c); });
      });
      var ordered = sort === 'oldest' ? groups.slice().reverse() : groups;
      ordered.forEach(function (g) { scope.appendChild(g); });
      if (empty) scope.appendChild(empty);
    }

    function fromUrlSort() {
      try {
        var params = new URLSearchParams(window.location.search);
        var v = (params.get(SORT_PARAM) || '').toLowerCase();
        return v === 'oldest' ? 'oldest' : null;
      } catch (e) {
        return /sort=oldest/.test(window.location.search) ? 'oldest' : null;
      }
    }

    function setChips() {
      chips.forEach(function (c) {
        c.setAttribute('aria-pressed', String(c.getAttribute('data-filter') === active));
      });
    }

    function setSortSel() {
      if (sortSel) sortSel.value = sort === 'oldest' ? 'oldest' : 'newest';
    }

    function show(el, visible) {
      el.hidden = !visible;
      el.classList.toggle('is-filtered', !visible);
    }

    function apply() {
      var q = input && input.value ? input.value.trim().toLowerCase() : '';
      var shown = 0;
      var firstVisible = null;

      items.forEach(function (item) {
        var project = item.getAttribute('data-project') || '';
        var haystack = (item.getAttribute('data-search') || item.textContent || '').toLowerCase();
        var matchProject = active === 'all' || project === active;
        var matchText = !q || haystack.indexOf(q) !== -1;
        var visible = matchProject && matchText;
        show(item, visible);
        item.classList.remove('timeline__item--first');
        if (visible) {
          shown++;
          if (!firstVisible) firstVisible = item;
        }
      });

      // the marked timeline node belongs to whatever is now at the top
      if (firstVisible) firstVisible.classList.add('timeline__item--first');

      // hide a month heading when everything under it is filtered out
      groups.forEach(function (group) {
        var any = all('[data-release-item]', group).some(function (i) { return !i.hidden; });
        show(group, any);
      });

      if (empty) empty.hidden = shown !== 0;
      if (count) {
        count.textContent = shown === items.length
          ? String(items.length) + ' releases'
          : String(shown) + ' of ' + items.length + ' releases';
      }
    }

    /* The default selection is the bare URL, so it is not pushed as a query
       string; every other selection is addressable and shareable. */
    function writeUrl(push) {
      if (!window.history || !window.history.pushState) return;
      var url;
      try {
        url = new URL(window.location.href);
        if (active === DEFAULT) url.searchParams.delete(PARAM);
        else url.searchParams.set(PARAM, active);
        if (sort === 'oldest') url.searchParams.set(SORT_PARAM, 'oldest');
        else url.searchParams.delete(SORT_PARAM);
        url = url.pathname + (url.search || '') + url.hash;
      } catch (e) {
        url = window.location.pathname;
        if (active !== DEFAULT) url += '?' + PARAM + '=' + active;
        if (sort === 'oldest') url += (active === DEFAULT ? '?' : '&') + 'sort=oldest';
      }
      if (push) window.history.pushState({ filter: active }, '', url);
      else window.history.replaceState({ filter: active }, '', url);
    }

    function select(next, push) {
      var value = normalise(next) || DEFAULT;
      if (value === active) return;
      active = value;
      setChips();
      apply();
      writeUrl(push);
    }

    chips.forEach(function (chip) {
      on(chip, 'click', function () {
        select(chip.getAttribute('data-filter'), true);
      });
    });

    if (sortSel) {
      if (reduceMotion.matches || !('IntersectionObserver' in window)) {
        /* nothing special: the select still works, ordering is just instant */
      }
      on(sortSel, 'change', function () {
        sort = sortSel.value === 'oldest' ? 'oldest' : 'newest';
        layout();
        apply();
        writeUrl(true);
      });
    }

    on(window, 'popstate', function () {
      var next = fromUrl() || DEFAULT;
      var nextSort = fromUrlSort();
      if (next === active && nextSort === sort) return;
      active = next;
      sort = nextSort || 'newest';
      setChips();
      setSortSel();
      layout();
      apply();
    });

    if (input) {
      var debounce = null;
      on(input, 'input', function () {
        clearTimeout(debounce);
        debounce = setTimeout(apply, 120);
      });
      // Escape clears the search
      on(input, 'keydown', function (e) {
        if (e.key === 'Escape' && input.value) {
          input.value = '';
          apply();
        }
      });
    }

    setChips();
    sort = fromUrlSort() || 'newest';
    setSortSel();
    if (sort === 'oldest') layout();
    apply();
    writeUrl(false);
  }());

  /* ------------------------------------------------- 7. hydration fallback */

  /* Only runs when a data region is empty, which means the site was deployed
     without running the renderer. It shows skeletons, then either a compact
     card built from the generated JSON or a real error state with a retry. */
  (function hydrate() {
    var regions = all('[data-hydrate]').filter(function (el) {
      return el.textContent.trim() === '';
    });
    if (!regions.length) return;

    var DATA_URL = '/data/releases.json';

    regions.forEach(function (region) { region.innerHTML = skeletonFor(region); });

    load();

    function load() {
      if (!window.fetch) { regions.forEach(showError); return; }
      fetch(DATA_URL, { credentials: 'same-origin' })
        .then(function (r) {
          if (!r.ok) throw new Error('HTTP ' + r.status);
          return r.json();
        })
        .then(function (data) {
          var byslug = {};
          (data.projects || []).forEach(function (p) { byslug[p.slug] = p; });
          regions.forEach(function (region) {
            var slug = region.getAttribute('data-hydrate');
            var entry = byslug[slug];
            if (!entry || !entry.latest) {
              showMissing(region, entry);
            } else {
              region.innerHTML = cardFor(entry);
            }
          });
        })
        .catch(function () { regions.forEach(showError); });
    }

    function skeletonFor(region) {
      var rows = region.getAttribute('data-hydrate-rows') === 'compact'
        ? '<div class="sk-row"><div class="skeleton sk-line sk-w-40"></div></div>'
        : '<div class="sk-row"><div class="skeleton sk-pill"></div><div class="skeleton sk-pill"></div></div>' +
          '<div class="skeleton sk-line sk-w-60"></div>' +
          '<div class="skeleton sk-line sk-line--sm sk-w-40"></div>' +
          '<div class="skeleton sk-block"></div>' +
          '<div class="sk-row"><div class="skeleton sk-btn"></div><div class="skeleton sk-btn"></div></div>';
      return '<div class="panel pad sk-stack" role="status" aria-live="polite">' +
             '<span class="visually-hidden">Loading release information…</span>' +
             '<div class="skeleton sk-line sk-line--lg sk-w-50"></div>' + rows + '</div>';
    }

    function showError(region) {
      region.innerHTML =
        '<div class="state state--error">' +
          '<div class="state__icon" aria-hidden="true">!</div>' +
          '<h3>Release information is temporarily unavailable.</h3>' +
          '<p>The generated release data could not be loaded. The releases themselves are ' +
          'unaffected — you can always get them straight from GitHub.</p>' +
          '<div class="state__actions">' +
            '<button class="btn btn--outline" type="button" data-retry>Try again</button>' +
            '<a class="btn btn--quiet" href="https://github.com/codeboy2012/PwEevee/releases" ' +
              'rel="noopener">View GitHub releases</a>' +
          '</div>' +
        '</div>';
      var retry = one('[data-retry]', region);
      on(retry, 'click', function () {
        regions.forEach(function (r) { r.innerHTML = skeletonFor(r); });
        load();
      });
    }

    function showMissing(region, entry) {
      var url = (entry && entry.releases_url) || 'https://github.com/codeboy2012/PwEevee/releases';
      region.innerHTML =
        '<div class="state state--warn">' +
          '<div class="state__icon" aria-hidden="true">?</div>' +
          '<h3>No published release was found for this project.</h3>' +
          '<p>' + esc((entry && entry.error) || 'The release index does not currently list this project.') + '</p>' +
          '<div class="state__actions">' +
            '<a class="btn btn--outline" href="' + esc(url) + '" rel="noopener">View on GitHub</a>' +
          '</div>' +
        '</div>';
    }

    /* Deliberately a COMPACT card, not a copy of the renderer's markup: the
       full presentation lives in one place (render-site.pl). This is a safety
       net, so it stays small and obviously secondary. */
    function cardFor(entry) {
      var r = entry.latest;
      var assets = (r.assets || []).filter(function (a) { return safeUrl(a.download_url); });
      var primary = assets[0];

      var badges = '<span class="badge badge--latest"><span class="badge__dot"></span>Latest release</span>';
      if (r.prerelease) badges += '<span class="badge badge--prerelease">Prerelease</span>';
      if (entry.stale) badges += '<span class="badge badge--stale">Cached data</span>';

      var action = primary
        ? '<a class="btn btn--primary btn--lg btn--stack" href="' + esc(primary.download_url) + '" rel="noopener">' +
            '<span>Download ' + esc(primary.name.split('.').pop().toUpperCase()) + '</span>' +
            '<span class="btn__sub">' + esc(primary.size_label || '') + '</span></a>'
        : '<a class="btn btn--outline btn--lg" href="' + esc(r.url) + '" rel="noopener">View release on GitHub</a>';

      var note = primary ? '' :
        '<p class="small muted">This release does not currently contain a downloadable package.</p>';

      return '<div class="panel panel--raised panel--hover download">' +
        '<div class="download__head"><div class="download__ident">' +
          '<span class="download__project">' + esc(entry.name) + '</span>' +
          '<h3 class="download__version">' + esc(r.version_label || r.version) + '</h3>' +
          '<p class="download__date">Released ' + esc(r.published_label || '') + '</p>' +
        '</div><div class="download__badges">' + badges + '</div></div>' +
        note +
        '<div class="download__actions">' + action +
          '<a class="btn btn--outline" href="' + esc(r.url) + '" rel="noopener">Release notes</a>' +
          '<a class="btn btn--quiet" href="' + esc(entry.repo_url) + '" rel="noopener">GitHub source</a>' +
        '</div></div>';
    }

    function esc(s) {
      return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
        return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
      });
    }
    function safeUrl(u) { return typeof u === 'string' && /^https:\/\/[a-z0-9.-]+\//i.test(u); }
  }());

  // Scroll-aware header: the glass bar densifies and gains a shadow once a
  // page has actually scrolled under it. Pure state class, transform/opacity
  // cheap, listener passive, and file: protocol handled with a rAF-free fast
  // path (no passive warning on those browsers).
  (function () {
    var header = document.querySelector('.site-header');
    if (!header) return;
    var setValue = function (v) {
      if (v) header.setAttribute('data-scrolled', '');
      else header.removeAttribute('data-scrolled');
    };
    var paint = function () {
      setValue(window.scrollY > 12);
    };
    var t = 0;
    var onScroll = function () {
      if (t) return;
      t = requestAnimationFrame(function () {
        t = 0;
        paint();
      });
    };
    paint();
    if (window.location.protocol === 'file:') {
      window.addEventListener('scroll', function () { paint(); }, { passive: false });
    } else {
      window.addEventListener('scroll', onScroll, { passive: true });
      window.addEventListener('resize', onScroll, { passive: true });
    }
  }());

  /* ======================================================== 8. on-visit freshness check === */

  /* Every page that displays release facts carries tiny data-* hooks the
     renderer wrote: the repo coordinates ("owner/repo") and the epoch of the
     value that was put on screen. Once per visit, quietly, we ask GitHub
     ( unauthenticated, read-only) whether each of those releases is still the
     newest, and only when something has actually moved do we update the
     visible text.

     deliberately conservative details:
       - one unauthenticated request per repo per visit, at most;
       - the same browser session never re-asks sooner than every 10 minutes
         (sessionStorage), so paging around the site does not hammer GitHub;
       - a newer release updates the displayed VERSION text and adds a link to
         the upstream release, but download URLs and SHA-256 lines are never
         rewritten from browser data — those were signed off at render time;
       - prereleases are allowed through (the site tracks them, just labeled);
         drafts are not;
       - any network failure, malformed response, rate limit or offline state
         leaves the page EXACTLY as rendered: that data was verified when the
         page was built and stays internally consistent, and the footer note
         quietly says so;
       - the browser only ever READS the public releases API and never uploads
         anything — no token, no cookie, no analytics, no "checking in".

     See docs/freshness.md for the full contract and the test coverage. */
  (function freshSession() {
    var KEY = 'pweevee-fresh';
    var MIN_MS = 10 * 60 * 1000;

    var hooks = {};
    var els = document.querySelectorAll('[data-fresh-repo], [data-release-panel]');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      var repo = el.getAttribute('data-fresh-repo') || el.getAttribute('data-release-panel');
      if (!repo) continue;
      if (el.hasAttribute('data-release-panel')) {
        var versionNode = el.querySelector('[data-release-version]');
        if (!versionNode) continue;
        (hooks[repo] = hooks[repo] || []).push({
          node: versionNode,
          kind: 'panel',
          epoch: +el.getAttribute('data-release-epoch') || 0,
          badges: el.querySelector('.download__badges') || versionNode.parentNode
        });
        continue;
      }
      var kind = el.getAttribute('data-fresh-kind') || 'version';
      if (kind === 'panel') continue;
      (hooks[repo] = hooks[repo] || []).push({
        node: el,
        kind: kind,
        epoch: +el.getAttribute('data-fresh-epoch') || 0
      });
    }
    var repos = Object.keys(hooks);
    if (!repos.length) return;

    /* Session gate: this very browser already asked in the last 10 minutes, so
       navigation to another page merely reads the fresh numbers it rendered —
       those pages were built from data no older than the render itself. */
    var seen = null;
    try { seen = JSON.parse(window.sessionStorage.getItem(KEY) || 'null'); } catch (e) { /* ok */ }
    var now = Date.now();
    if (seen && (seen.at || 0) && now - (seen.at || 0) < MIN_MS && seen.all) return;

    seen = { at: now, repos: (seen && seen.repos) || {}, all: false };
    function remember() {
      try { window.sessionStorage.setItem(KEY, JSON.stringify(seen)); } catch (e) { /* private */ }
    }
    remember();

    var pending = repos.length, failures = 0;
    function settle(ok) {
      pending--;
      if (!ok) failures++;
      if (pending > 0) return;
      var value = failures ? 'offline' : 'checked';
      document.documentElement.setAttribute('data-fresh', value);
      seen.all = true;
      remember();
      var noteEl = document.querySelector('[data-fresh-note]');
      if (noteEl) {
        noteEl.setAttribute('data-fresh-state', failures ? 'offline' : 'ok');
        if (!failures) {
          noteEl.setAttribute('title', 'Re-checked live against the GitHub API when this page was opened.');
        } else {
          noteEl.setAttribute('title', 'The live re-check could not reach GitHub; the rendered '
            + 'release data below is the most recent verified snapshot.');
        }
      }
    }

    repos.forEach(function (repo) {
      if (seen.repos[repo] && now - seen.repos[repo] < MIN_MS) { settle(true); return; }
      var url = 'https://api.github.com/repos/'
              + String(repo).split('/').map(encodeURIComponent).join('/') + '/releases/latest';
      fetch(url, {
        headers: { 'Accept': 'application/vnd.github+json' },
        credentials: 'omit',
        cache: 'no-store',
        referrerPolicy: 'strict-origin-when-cross-origin'
      }).then(function (res) {
        /* /releases/latest returns 404 when the repo has no publishable
           latest release at all — a prerelease-only or cleaned-up upstream.
           That is not an outage: the rendered data stands, the repo window
           is recorded so we do not re-ask for a while, and the page is not
           branded offline. */
        if (res.status === 404) {
          seen.repos[repo] = Date.now(); remember();
          settle(true);
          return;
        }
        if (!res.ok) throw new Error(String(res.status));
        return res.json();
      }).then(function (rel) {
        if (!rel) return;
        if (!rel || !rel.tag_name || rel.draft) throw new Error('bad payload');
        seen.repos[repo] = Date.now(); remember();
        apply(repo, rel);
        settle(true);
      }).catch(function () { settle(false); });
    });

    function tagName(rel) {
      return String(rel.tag_name || '').replace(/^v(?=\d)/i, '');
    }
    function tagEpoch(rel) {
      return Math.floor((Date.parse(rel.published_at) || 0) / 1000);
    }
    var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December'];
    function fmtDate(iso) {
      var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ''));
      if (!m) return '';
      return (+m[3]) + ' ' + MONTHS[+m[2] - 1] + ' ' + (+m[1]);
    }

    function apply(repo, rel) {
      var upstream = tagEpoch(rel);
      (hooks[repo] || []).forEach(function (h) {
        if (!h.node || !upstream || upstream <= h.epoch) return;
        if (h.kind === 'date') {
          h.node.textContent = 'Released ' + fmtDate(rel.published_at);
          return;
        }
        /* Every rendered version on the site is v-prefixed when the tag is
           digit-led (v2.0.0), so an update keeps that prefix instead of
           landing a bare 2.0.1 beside its own old v2.0.0. */
        var fresh = tagName(rel);
        if (/^v/i.test(String(h.node.textContent || '').trim()) && /^\d/.test(fresh)) {
          fresh = 'v' + fresh;
        }
        h.node.textContent = fresh;
        if (h.kind !== 'panel') return;
        /* A full release panel gets one badge: honest about what changed,
           pointing to the authoritative source, never rewriting downloads. */
        if (rel.html_url && h.badges && !h.badges.querySelector('[data-fresh-badge]')) {
          var a = document.createElement('a');
          a.setAttribute('data-fresh-badge', '');
          a.className = 'badge badge--fresh';
          a.href = rel.html_url;
          a.rel = 'noopener';
          a.textContent = 'Newer: ' + fresh + ' on GitHub';
          h.badges.appendChild(a);
        }
      });
    }
  }());
}());
