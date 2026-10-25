/* ============================================================================
   installer.js — PwEevee /install workshop, browser-local validation engine

   Policy (re-verified by website-tests.pl section 8):
   - network I/O:     NONE. There is no HTTP client, no realtime socket, no
                      statistics beacon and no dynamic module loading in this
                      file — the tab performs zero network activity while the
                      engine runs, and the suite greps for every primitive name
                      to enforce that claim (which is why this comment spells
                      none of them).
   - persistent state: NONE. No Web-Storage key, no Indexed-DB record, no
                      cookie is ever written or read.
   - third-party code: NONE. Vendored, self-written, dependency-free.
   - only APIs used:  DOM, Blob/File slicing, FileReader, TextEncoder/Decoder,
                      DOMParser (XML plists), DecompressionStream (deflate-raw).

   Parses and cross-validates, entirely inside this tab:
     .ipa             — ZIP walk (central directory) + targeted entry reads
     .mobileprovision — DER/CMS walk → embedded plist → all profile facts
     .p12             — PKCS#12 ENVELOPE ONLY (contents stay encrypted on
                        purpose; see parseP12Bytes)
   Never uploads, never persists, never claims an installation result.
   ============================================================================ */
(function () {
'use strict';

/* ------------------------------------------------------------ tiny helpers */
var $ = function (s, root) { return (root || document).querySelector(s); };

var VERDICT = { VALID: 'validated', UNSUPPORTED: 'unsupported', UNVERIFIED: 'unable to verify' };
var BADGE_CLS = {};
BADGE_CLS[VERDICT.VALID]       = 'inst-badge--ok';
BADGE_CLS[VERDICT.UNSUPPORTED] = 'inst-badge--bad';
BADGE_CLS[VERDICT.UNVERIFIED]  = 'inst-badge--warn';

var DAYS_IN_MS = 86400000;

function daysUntil(isoDate) {
  if (!isoDate) return null;
  var t = Date.parse(isoDate);
  return isNaN(t) ? null : Math.floor((t - Date.now()) / DAYS_IN_MS);
}

function row(name, verdict, detail) {
  return { name: name, verdict: verdict, detail: detail || '' };
}
function resultRow(r) {
  var li = document.createElement('li');
  li.className = 'inst-row';
  var badge = document.createElement('span');
  badge.className = 'inst-badge ' + (BADGE_CLS[r.verdict] || 'inst-badge--warn');
  badge.dataset.verdict = r.verdict;
  badge.textContent = r.verdict;
  li.appendChild(badge);
  var body = document.createElement('div');
  body.className = 'inst-row__body';
  var strong = document.createElement('strong');
  strong.textContent = r.name;
  body.appendChild(strong);
  if (r.detail) {
    var span = document.createElement('span');
    span.className = 'small dim';
    span.textContent = ' — ' + r.detail;
    body.appendChild(span);
  }
  li.appendChild(body);
  return li;
}
function drawRows(listEl, rows) {
  var ul = document.createElement('ul');
  ul.className = 'inst-list';
  rows.forEach(function (r) { ul.appendChild(resultRow(r)); });
  listEl.textContent = '';
  listEl.appendChild(ul);
}

/* ================================================================ SHA-256 */
var SHA256 = (function () {
  var K = new Uint32Array([
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]);
  function rotr(x, n) { return (x >>> n) | (x << (32 - n)); }
  function Hasher() {
    this.h = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    this.buf = new Uint8Array(64); this.bufLen = 0; this.len = 0;
  }
  Hasher.prototype.update = function (u8) {
    var i = 0, n = u8.length;
    while (i < n) {
      if (this.bufLen === 0 && n - i >= 64) { this._block(u8, i); i += 64; this.len += 64; continue; }
      var take = Math.min(64 - this.bufLen, n - i);
      this.buf.set(u8.subarray(i, i + take), this.bufLen);
      this.bufLen += take; i += take; this.len += take;
      if (this.bufLen === 64) { this._block(this.buf, 0); this.bufLen = 0; }
    }
  };
  Hasher.prototype._block = function (p, off) {
    var w = new Uint32Array(64), j, t, t2;
    for (j = 0; j < 16; j++) {
      w[j] = ((p[off + 4 * j] << 24) | (p[off + 4 * j + 1] << 16) |
              (p[off + 4 * j + 2] << 8) | p[off + 4 * j + 3]) >>> 0;
    }
    for (j = 16; j < 64; j++) {
      t  = (rotr(w[j-15], 7) ^ rotr(w[j-15], 18) ^ (w[j-15] >>> 3)) >>> 0;
      t2 = (rotr(w[j-2], 17) ^ rotr(w[j-2], 19) ^ (w[j-2] >>> 10)) >>> 0;
      w[j] = (w[j-16] + t + w[j-7] + t2) >>> 0;
    }
    var a=this.h[0],b=this.h[1],c=this.h[2],d=this.h[3],e=this.h[4],f=this.h[5],g=this.h[6],h=this.h[7];
    for (j = 0; j < 64; j++) {
      var S1 = (rotr(e,6) ^ rotr(e,11) ^ rotr(e,25)) >>> 0;
      var ch = (e & f) ^ (~e & g);
      var tt = (h + S1 + (ch >>> 0) + K[j] + w[j]) >>> 0;
      var S0 = (rotr(a,2) ^ rotr(a,13) ^ rotr(a,22)) >>> 0;
      var mj = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      h = g; g = f; f = e;
      e = (d + tt) >>> 0;
      d = c; c = b; b = a;
      a = (tt + S0 + mj) >>> 0;
    }
    this.h[0]=(this.h[0]+a)>>>0; this.h[1]=(this.h[1]+b)>>>0; this.h[2]=(this.h[2]+c)>>>0;
    this.h[3]=(this.h[3]+d)>>>0; this.h[4]=(this.h[4]+e)>>>0; this.h[5]=(this.h[5]+f)>>>0;
    this.h[6]=(this.h[6]+g)>>>0; this.h[7]=(this.h[7]+h)>>>0;
  };
  Hasher.prototype.finish = function () {
    var totalBits = this.len * 8;
    var hi = Math.floor(totalBits / 0x100000000);
    var lo = totalBits >>> 0;   // low 32 bits of the bit count
    var padLen = ((this.len % 64) < 56) ? (56 - (this.len % 64)) : (120 - (this.len % 64));
    var pad = new Uint8Array(padLen + 1 + 8);
    pad.fill(0);
    pad[0] = 0x80;
    pad[padLen + 1] = (hi >>> 24) & 255; pad[padLen + 2] = (hi >>> 16) & 255;
    pad[padLen + 3] = (hi >>> 8)  & 255; pad[padLen + 4] = hi & 255;
    pad[padLen + 5] = (lo >>> 24) & 255; pad[padLen + 6] = (lo >>> 16) & 255;
    pad[padLen + 7] = (lo >>> 8)  & 255; pad[padLen + 8] = lo & 255;
    this.update(pad);
    var out = new Uint8Array(32);
    for (var i = 0; i < 8; i++) {
      out[4*i]   = (this.h[i] >>> 24) & 255; out[4*i+1] = (this.h[i] >>> 16) & 255;
      out[4*i+2] = (this.h[i] >>> 8)  & 255; out[4*i+3] = this.h[i] & 255;
    }
    return out;
  };
  return Hasher;
})();

function hex(u8) {
  var s = '';
  for (var i = 0; i < u8.length; i++) {
    s += ((u8[i] >>> 4) & 15).toString(16) + (u8[i] & 15).toString(16);
  }
  return s;
}

/* digestFile: read a File in 4 MiB slices through FileReader; the whole file
   is never materialised at once (a 300 MB buffer is what low-memory phones
   cannot promise). Resolves { hex }. */
function digestFile(file, onProgress) {
  return new Promise(function (resolve, reject) {
    var CHUNK = 4194304; // 4 MiB
    var hasher = new SHA256();
    var pos = 0;
    var fr = new FileReader();
    fr.onerror = function () { reject(new Error('FileReader failed while hashing.')); };
    function next() {
      if (pos >= file.size) {
        try { resolve({ hex: hex(hasher.finish()) }); } catch (e) { reject(e); }
        return;
      }
      var end = Math.min(pos + CHUNK, file.size);
      fr.onload = function () {
        try {
          hasher.update(new Uint8Array(fr.result));
        } catch (e) { reject(e); return; }
        pos = end;
        if (onProgress) {
          try { onProgress(pos / file.size); } catch (e) { /* UI-only */ }
        }
        next();
      };
      fr.readAsArrayBuffer(file.slice(pos, end));
    }
    next();
  });
}

/* ================================================================ byte IO */
function asciiStartsWith(u8a, s, off) {
  off = off || 0;
  for (var i = 0; i < s.length; i++) {
    if (off + i >= u8a.length || u8a[off + i] !== s.charCodeAt(i)) return false;
  }
  return true;
}

/* base64 (armored or raw), tolerating base64url and surrounding whitespace. */
function b64Decode(s) {
  s = s.replace(/-----[^-]*-----/g, '').replace(/\s+/g, '');
  var cut = s.search(/[^A-Za-z0-9+/=]/);
  if (cut > 4) s = s.slice(0, cut);
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  var bin = atob(s);
  var out = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/* =============================================================== binary plist */
/* Minimal Apple binary plist reader (bplist00). Supports the object types a
   provisioning profile / Info.plist actually carries; every read is bounded. */
function parseBplist(u8a) {
  if (!u8a || u8a.length < 40 || !asciiStartsWith(u8a, 'bplist00', 0)) return null;
  var t = u8a.length;
  // trailer layout: 6 unused | 1 unused | 1 offsetIntSize | 1 refSize
  //                 | 8 numObjects | 8 topObject | 8 tableOffset
  var offsetIntSize = u8a[t - 25];
  var refSize       = u8a[t - 24];
  var numObjects    = readU64(u8a, t - 22);
  var top           = readU64(u8a, t - 15);
  var tableOff      = readU64(u8a, t - 8);
  if (offsetIntSize < 1 || offsetIntSize > 8 || refSize < 1 || refSize > 8) return null;
  if (!tableOff || tableOff >= t) return null;
  if (numObjects === 0 || numObjects > 262144) return null;

  function readU64(a, p) {
    // acceptable for plist sizes (never near 2^53 in these files)
    var v = 0;
    for (var i = 0; i < 8; i++) v = v * 0x100 + a[p + i];
    return v;
  }
  function readBe(a, p, size) {
    var v = 0;
    for (var i = 0; i < size; i++) v = v * 0x100 + a[p + i];
    return v;
  }
  function tableRef(i) {
    if (i < 0 || i >= numObjects) throw new Error('bplist ref #' + i + ' out of range');
    return readBe(u8a, tableOff + i * offsetIntSize, offsetIntSize);
  }
  function refAt(p) { return readBe(u8a, p, refSize); }
  function byteLenOfLong(pos) {
    // long-length ints: nibble n (0..3) → next object holds the count;
    // when the nibble is n, the int itself is n bytes wide after the 0x1 tag.
    var nib = u8a[pos] & 15;
    return 1 + (1 << nib);
  }
  var budget = 200000, depthLimit = 200, depth = 0;
  function objAt(pos) {
    if (--budget < 0) throw new Error('bplist budget exceeded');
    if (++depth > depthLimit) { depth--; throw new Error('bplist nesting too deep'); }
    if (pos < 0 || pos >= tableOff) { depth--; throw new Error('bplist object position out of range'); }
    var tag = u8a[pos], kind = tag >>> 4, nib = tag & 15;
    try {
      switch (kind) {
        case 0:
          if (nib === 8) return false;
          if (nib === 9) return true;
          if (nib === 0 || nib === 15) return null;
          throw new Error('bplist: odd primitive tag 0x' + tag.toString(16));
        case 1: {
          if (nib === 0xf) throw new Error('bplist: wide int form not supported');
          if (nib !== 0 && nib !== 1 && nib !== 2 && nib !== 3)
            throw new Error('bplist: int width ' + nib);
          var n = 1 << nib, v = 0;
          for (var i = 0; i < n; i++) v = v * 0x100 + u8a[pos + 1 + i];
          if (n === 8 && v >= 0x8000000000000000) v -= 0x10000000000000000;
          return v;
        }
        case 2: {
          if (nib === 1) {
            return readBeFloat64(u8a, pos + 1);
          }
          if (nib === 0) {
            return readBeFloat32(u8a, pos + 1);
          }
          throw new Error('bplist: real width ' + nib);
        }
        case 3: {
          if (nib !== 1) throw new Error('bplist: date width ' + nib);
          var secs = readBeFloat64(u8a, pos + 1);
          return new Date(Math.round((secs + 978307200) * 1000)).toISOString();
        }
        case 4: case 5: case 6: case 8: {
          var cnt = nib, hdr = 1;
          if (nib === 0xf) {
            var ln = objAt(pos + 1);
            if (typeof ln !== 'number') throw new Error('bplist: bad long length');
            cnt = ln; hdr = 1 + byteLenOfLong(pos + 1);
          }
          if (cnt > 16 * 1024 * 1024) throw new Error('bplist: element too large');
          var start = pos + hdr;
          if (kind === 4) return u8a.subarray(start, start + cnt);
          if (kind === 8) return { uid: cnt };
          if (kind === 5) return latin1At(start, cnt);
          return utf16beAt(start, cnt);
        }
        case 10: case 11: case 12: {
          return collectionAt(pos, nib, true);
        }
        case 13: {
          return collectionAt(pos, nib, false);
        }
        default:
          throw new Error('bplist: unsupported tag 0x' + tag.toString(16));
      }
    } finally { depth--; }
  }
  function collectionAt(pos, nib, isArr) {
    var cnt = nib, hdr = 1;
    if (nib === 0xf) {
      var ln = objAt(pos + 1);
      if (typeof ln !== 'number') throw new Error('bplist: bad long length');
      cnt = ln; hdr = 1 + byteLenOfLong(pos + 1);
    }
    if (cnt > 16384) throw new Error('bplist: collection too large');
    var vals = [], keys = [];
    for (var i = 0; i < cnt; i++) {
      vals.push(objAt(tableRef(refAt(pos + hdr + i * refSize))));
      if (isArr) keys.push(null);
      else keys.push(objAt(tableRef(refAt(pos + hdr + (cnt + i) * refSize))));
    }
    if (isArr) return vals;
    var d = {};
    for (var k = 0; k < cnt; k++) d[keys[k]] = vals[k];
    return d;
  }
  /* JS typed arrays are little-endian on every real browser, but plist
     floats/doubles are stored big-endian. Reverse the bytes first. */
  function readBeFloat64(a, p) {
    var b = new Uint8Array(8);
    for (var i = 0; i < 8; i++) b[7 - i] = a[p + i];
    return new Float64Array(b.buffer)[0];
  }
  function readBeFloat32(a, p) {
    var b = new Uint8Array(4);
    for (var i = 0; i < 4; i++) b[3 - i] = a[p + i];
    return new Float32Array(b.buffer)[0];
  }
  function latin1At(start, cnt) {
    var s = '';
    for (var i = 0; i < cnt; i++) s += String.fromCharCode(u8a[start + i]);
    return s;
  }
  function utf16beAt(start, cnt) {
    var s = '';
    for (var i = 0; i < cnt; i++) {
      var c = (u8a[start + 2*i] << 8) | u8a[start + 2*i + 1];
      if (c >= 0xd800 && c <= 0xdbff && i + 1 < cnt) {
        var c2 = (u8a[start + 2*(i+1)] << 8) | u8a[start + 2*(i+1) + 1];
        if (c2 >= 0xdc00 && c2 <= 0xdfff) { s += String.fromCharCode(c, c2); i++; continue; }
      }
      s += String.fromCharCode(c);
    }
    return s;
  }
  try {
    return { top: objAt(tableRef(top)) };
  } catch (e) {
    return null;
  }
}

/* XML plist — used by crafted and human-edited profiles. */
function parseXmlPlist(u8a) {
  var txt;
  try { txt = new TextDecoder('utf-8').decode(u8a); } catch (e) { return null; }
  if (txt.indexOf('<plist') < 0) return null;
  var doc;
  try { doc = new DOMParser().parseFromString(txt, 'text/xml'); } catch (e) { return null; }
  if (doc.getElementsByTagName('parsererror').length) return null;
  var rootEl = doc.documentElement;
  if (!rootEl || !rootEl.children || !rootEl.children.length) return null;
  try { return { top: xmlNode(rootEl.children[0]) }; } catch (e) { return null; }
}
function xmlNode(n) {
  if (!n || !n.tagName) return n ? n.textContent : null;
  switch (n.tagName) {
    case 'true':    return true;
    case 'false':   return false;
    case 'string':  return n.textContent;
    case 'key':     return n.textContent;
    case 'integer': return parseInt(n.textContent, 10);
    case 'real':    return parseFloat(n.textContent);
    case 'date':    return n.textContent;
    case 'data':
      try { return b64Decode(n.textContent); } catch (e) { return null; }
    case 'dict': {
      var out = {}, kids = n.children, i, ks = [];
      for (i = 0; i < kids.length; i++) if (kids[i].tagName === 'key') ks.push(kids[i].textContent);
      var vi = 0;
      for (i = 0; i < kids.length && vi < ks.length; i++) {
        var c = kids[i];
        if (c.tagName === 'key') continue;
        out[ks[vi++]] = xmlNode(c);
      }
      return out;
    }
    case 'array': {
      var a = [];
      for (var j = 0; j < n.children.length; j++) a.push(xmlNode(n.children[j]));
      return a;
    }
  }
  return n.textContent;
}

function parsePlist(u8a) {
  return parseBplist(u8a) || parseXmlPlist(u8a);
}

/* ================================================================ DER reader */
/* Definite lengths plus BER indefinite encoding (files some tools still emit).
   All walks are bounded. */
function readLen(a, p, out) {
  if (p + 1 > a.length) throw new Error('BER length past end of file');
  var b = a[p];
  if (b < 0x80) { out.len = b; return p + 1; }
  var n = b & 0x7f;
  if (n === 0) { out.len = -1; return p + 1; }
  if (n > 4) throw new Error('BER length encoding too wide');
  var l = 0;
  for (var i = 0; i < n; i++) {
    if (p + 1 + i >= a.length) throw new Error('BER long length truncated');
    l = l * 0x100 + a[p + 1 + i];
  }
  out.len = l;
  return p + 1 + n;
}
function derNext(a, p) {
  if (p >= a.length) throw new Error('DER cursor past end');
  var tag = a[p];
  var li = {};
  var q = readLen(a, p + 1, li);
  var node = { tag: tag, indef: li.len < 0, contentStart: q, len: li.len };
  if (li.len < 0) {
    var steps = 0, cur = q;
    for (;;) {
      if (cur + 1 >= a.length) throw new Error('unterminated indefinite-length TLV');
      if (a[cur] === 0x00 && a[cur + 1] === 0x00) {
        node.contentEnd = cur; node.next = cur + 2; break;
      }
      var inner = derNext(a, cur);
      cur = inner.next;
      if (++steps > 2048) throw new Error('unbounded indefinite nesting');
    }
  } else {
    if (q + li.len > a.length) throw new Error('DER content past end of file');
    node.contentEnd = q + li.len;
    node.next = node.contentEnd;
  }
  return node;
}
function derChildren(a, node) {
  var out = [], q = node.contentStart, steps = 0;
  while (q < node.contentEnd) {
    var c = derNext(a, q);
    out.push(c); q = c.next;
    if (++steps > 4096) throw new Error('too many DER children');
  }
  return out;
}
function oidDotted(node, a) {
  var b = a[node.contentStart];
  if (b === undefined) return '';
  var s = (b >> 3) + '.' + (b & 7), v = 0;
  for (var i = node.contentStart + 1; i < node.contentEnd; i++) {
    v = v * 0x80 + (a[i] & 0x7f);
    if (!(a[i] & 0x80)) { s += '.' + v; v = 0; }
  }
  return s;
}

/* ==================================================== provisioning profile */
/* .mobileprovision = DER CMS SignedData wrapping the plist. Walk exactly
   ContentInfo → [0] → SignedData SEQ → encapContentInfo → [0] → OCTET STRING,
   then parse the embedded plist. If that does not resolve, say so — never
   guess. */
function parseMobileprovisionBytes(u8a) {
  if (!u8a || u8a.length < 32) return { error: 'File is too short to be a provisioning profile.' };
  var data = u8a;
  var head = asciiStartsWith(u8a, '-----', 0) || (u8a[0] >= 65 && u8a[0] <= 90);
  if (head) {
    try { data = b64Decode(new TextDecoder('latin1').decode(u8a)); }
    catch (e) { /* keep raw */ }
  }
  var plist = null, how = null;
  try {
    var ci = derNext(data, 0);
    if (ci.tag !== 0x30) throw new Error('not a CMS ContentInfo sequence');
    var ch = derChildren(data, ci);
    if (ch.length < 2 || ch[0].tag !== 0x06)
      throw new Error('outermost structure has no content-type OID');
    if (oidDotted(ch[0], data) !== '1.2.840.113549.1.7.2')
      throw new Error('CMS content OID is not SignedData — this file does not carry a signed profile');
    var sdWrap = ch[1];
    if (sdWrap.tag !== 0xa0) throw new Error('no explicit [0] wrapper after the OID');
    var sdInner = derNext(data, sdWrap.contentStart);
    if (sdInner.tag !== 0x30) throw new Error('SignedData sequence missing');
    var sch = derChildren(data, sdInner);
    for (var i = 0; i < sch.length; i++) {
      var c = sch[i];
      if (c.tag !== 0x30) continue;
      var ec = derChildren(data, c);
      if (ec.length >= 2 && ec[1].tag === 0xa0) {
        var oct = derNext(data, ec[1].contentStart);
        if (oct.tag === 0x04) {
          var pb = data.subarray(oct.contentStart, oct.contentEnd);
          var pz = parsePlist(pb);
          if (pz) { plist = pz.top; how = 'CMS → embedded plist'; break; }
        }
      }
    }
  } catch (e) {
    /* fall through to the embedded-plist scan */
  }
  if (!plist) {
    for (var j = 0; j + 32 < data.length; j++) {
      if (asciiStartsWith(data, 'bplist00', j)) {
        var p = parseBplist(data.subarray(j));
        if (p) { plist = p.top; how = 'embedded bplist (envelope scan)'; break; }
      }
      if (asciiStartsWith(data, '<?xml', j)) {
        var x = parseXmlPlist(data.subarray(j));
        if (x) { plist = x.top; how = 'embedded XML plist (envelope scan)'; break; }
      }
    }
  }
  if (!plist) {
    return { error: 'No provisioning-profile plist could be located inside this file — not a CMS SignedData envelope, and neither a bplist00 nor an "<?xml" plist is embedded. Corrupted, stripped, or not a mobileprovision at all.' };
  }
  return { profile: plist, how: how };
}

function describeProfile(p) {
  p = p || {};
  var ent = p.Entitlements || {};
  var appId = ent['application-identifier'] || '';
  var slash = appId.indexOf('.');
  var team = (p.TeamIdentifier && p.TeamIdentifier.length) ? p.TeamIdentifier[0] : '';
  return {
    name: p.Name || '',
    team: team,
    teamName: p.TeamName || '',
    uuid: p.UUID || '',
    created: p.CreationDate || null,
    expires: p.ExpirationDate || null,
    prefix: slash > 0 ? appId.slice(0, slash) : '',
    bundle: slash > 0 ? appId.slice(slash + 1) : appId,
    devices: Array.isArray(p.ProvisionedDevices) ? p.ProvisionedDevices : null,
    provisionsAllDevices: !!p.ProvisionsAllDevices,
    aps: ent['aps-environment'] || null,
    groups: Array.isArray(ent['com.apple.security.application-groups'])
              ? ent['com.apple.security.application-groups'] : [],
    getTaskAllow: ent['get-task-allow'] === true,
    keychain: ent['keychain-access-groups'] || []
  };
}

/* ==================================================================== .p12 */
/* PKCS#12 STRUCTURE ONLY. The cert/key bags inside an Apple-exported .p12 are
   PBE-encrypted (PKCS#12 KDF + 3DES/RC2); this build deliberately does not
   implement that key derivation, so certificate identity and expiry are
   reported as "unable to verify" rather than invented. */
function parseP12Bytes(u8a) {
  if (!u8a || u8a.length < 64) return { error: 'File is too short to be a PKCS#12 container.' };
  var data = u8a;
  try {
    var top = derNext(data, 0);
    if (top.tag !== 0x30)
      return { structural: false, why: 'Top-level is not a SEQUENCE — not a PKCS#12 container.' };
    var ch = derChildren(data, top);
    if (!ch.length || ch[0].tag !== 0x06)
      return { structural: false, why: 'No content-type OID at the top level.' };
    if (oidDotted(ch[0], data) !== '1.2.840.113549.1.7.1')
      return { structural: false, why: 'First OID is 1.2.840.113549.1.7.' +
        oidDotted(ch[0], data).split('.').pop() + ', not PKCS#7 Data as PKCS#12 requires.' };
    var macPresent = false, authSafeSeen = false, authSafeContent = null;
    for (var i = 1; i < ch.length; i++) {
      var c = ch[i];
      if (c.tag === 0x30 || c.tag === 0xa0) {
        var inner = derChildren(data, c);
        for (var j = 0; j < inner.length; j++) {
          var sub = inner[j];
          if (sub.tag === 0x06 && oidDotted(sub, data) === '1.2.840.113549.1.7.1') authSafeSeen = true;
          if (sub.tag === 0xa0) {
            var payload = derNext(data, sub.contentStart);
            if (payload.tag === 0x04 && !authSafeContent)
              authSafeContent = data.subarray(payload.contentStart, payload.contentEnd);
          }
        }
      } else if (c.tag === 0x2e) {
        macPresent = true;   // MAC (IMPLICIT SEQ, tag 0x2E)
      }
    }
    var structural = authSafeSeen || !!authSafeContent;
    if (!structural)
      return { structural: false, why: 'PKCS#12 header parsed but no authenticated safe (PFX authSafe) was found.' };
    return {
      structural: true,
      macPresent: macPresent,
      hasAuthSafe: authSafeSeen,
      hasAuthSafeContent: !!authSafeContent,
      whyEmpty: 'Apple exporting tools wrap the certificate and private key in a PBE-encrypted (PKCS#12 KDF) bag. This build never derives that key: decrypting credentials in a browser tab would leave plaintext key material in memory beyond what we can guarantee erasure of. Structure was read; contents stay encrypted. The on-device signing tool unpacks them with the OS crypto stack.'
    };
  } catch (e) {
    return { structural: false, why: 'Not parseable as PKCS#12: ' + e.message };
  }
}

/* ================================================================ ZIP reader */
function ZipReader(file) {
  this.file = file;
  this.entries = null;
  this.eocd = null;
  this.localBase = 0;   // archives with prepended data shift local headers by this
}
ZipReader.prototype.init = function () {
  var self = this, file = this.file;
  if (!file.size) return Promise.reject(new Error('File is empty.'));
  var tailLen = Math.min(file.size, 66000);
  return file.slice(file.size - tailLen).arrayBuffer().then(function (ab) {
    var tail = new Uint8Array(ab);
    var eocdPos = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (tail[i] === 0x50 && tail[i+1] === 0x4b && tail[i+2] === 0x05 && tail[i+3] === 0x06) {
        eocdPos = i; break;
      }
    }
    if (eocdPos < 0) throw new Error('Not a ZIP archive — no End-of-Central-Directory record found.');
    var e      = file.size - tailLen + eocdPos;
    var diskNo = le16(tail, eocdPos + 4);
    var diskCd = le16(tail, eocdPos + 6);
    var nHere  = le16(tail, eocdPos + 10);
    var cdSize = le32(tail, eocdPos + 12);
    var cdOfs  = le32(tail, eocdPos + 16);
    if (nHere === 0xffff || cdOfs === 0xffffffff || cdSize === 0xffffffff)
      throw new Error('ZIP64 archives are not supported by this validator.');
    if (diskNo !== 0 || diskCd !== 0)
      throw new Error('Multi-part ZIP archives are not supported.');
    var base = e - (cdOfs + cdSize);
    if (base < 0) throw new Error('ZIP structure inconsistent — central directory overflows the file.');
    self.localBase = base;
    self.eocd = { entries: nHere, cdSize: cdSize, cdOfs: cdOfs, base: base, eocdAt: e };
    // cdOfs is an offset inside the archive; prepended data (base) shifts it.
    return file.slice(base + cdOfs, base + cdOfs + cdSize).arrayBuffer();
  }).then(function (cdb) {
    var cd = new Uint8Array(cdb), ents = [], q = 0;
    for (var k = 0; k < self.eocd.entries; k++) {
      if (q + 46 > cd.length || !(cd[q] === 0x50 && cd[q+1] === 0x4b && cd[q+2] === 0x01 && cd[q+3] === 0x02))
        throw new Error('Central directory truncated or corrupted at entry #' + k + '.');
      var method   = le16(cd, q + 10);
      var crc      = le32(cd, q + 16);
      var compSize = le32(cd, q + 20);
      var size     = le32(cd, q + 24);
      var nameLen  = le16(cd, q + 28);
      var extraLen = le16(cd, q + 30);
      var cmtLen   = le16(cd, q + 32);
      var lho      = le32(cd, q + 42);
      var name = '';
      for (var i = 0; i < nameLen; i++) name += String.fromCharCode(cd[q + 46 + i]);
      ents.push({ name: name, method: method, crc: crc, compSize: compSize, size: size, lho: lho });
      q += 46 + nameLen + extraLen + cmtLen;
    }
    self.entries = ents;
    return self;
  });
};
function le16(a, p) { return a[p] | (a[p+1] << 8); }
function le32(a, p) { return (a[p] | (a[p+1]<<8) | (a[p+2]<<16) | (a[p+3]<<24)) >>> 0; }

ZipReader.prototype.find = function (pred) { return this.entries.filter(pred); };
ZipReader.prototype.byName = function (name) {
  var hits = this.find(function (e) { return e.name === name; });
  return hits.length ? hits[0] : null;
};

/* Read one entry's bytes, inflating with deflate-raw when the archive says so.
   Memory is bounded by the entry's declared size. */
ZipReader.prototype.bytesAt = function (entry) {
  if (!entry) return Promise.reject(new Error('ZIP entry not found.'));
  if (entry.compSize > 512 * 1024 * 1024)
    return Promise.reject(new Error('Refusing to decompress an entry larger than 512 MB.'));
  var self = this;
  return self.file.slice(self.localBase + entry.lho, self.localBase + entry.lho + 30)
    .arrayBuffer().then(function (ab) {
      var lh = new Uint8Array(ab);
      if (!(lh[0] === 0x50 && lh[1] === 0x4b && lh[2] === 0x03 && lh[3] === 0x04))
        throw new Error('Local header of "' + entry.name + '" is missing or corrupted.');
      var nameLen = le16(lh, 26), extraLen = le16(lh, 28);
      var start = self.localBase + entry.lho + 30 + nameLen + extraLen;
      var blob = self.file.slice(start, start + entry.compSize);
      if (entry.method === 0) return blob.arrayBuffer();
      if (typeof DecompressionStream !== 'function')
        throw new Error('This browser cannot inflate compressed ZIP entries (no DecompressionStream). Use Safari 16.4+, or Chrome / Edge / Firefox.');
      var ds = new DecompressionStream('deflate-raw');
      var stream = blob.stream ? blob.stream().pipeThrough(ds) : null;
      if (!stream) throw new Error('Blob.stream() missing in this browser.');
      return readStreamBounded(stream, entry.size);
    })
    .then(function (r) {
      if (r instanceof Uint8Array) return r;
      var u = new Uint8Array(r);
      if (u.length !== entry.size)
        throw new Error('Entry "' + entry.name + '" decompressed to ' + u.length +
                        ' bytes but its record says ' + entry.size + '.');
      return u;
    });
};

function readStreamBounded(stream, expected) {
  var reader = stream.getReader(), chunks = [], total = 0, capped = false;
  return reader.read().then(function step(res) {
    if (res.done) {
      if (capped) throw new Error('ZIP-bomb guard: entry expanded far beyond its declared size.');
      var out = new Uint8Array(total), o = 0;
      chunks.forEach(function (c) { out.set(c, o); o += c.length; });
      if (out.length !== expected) throw new Error('Decompressed length mismatch.');
      return out;
    }
    total += res.value.length;
    if (total > expected * 2 + 4096) { capped = true; chunks.length = 0; }
    else chunks.push(res.value);
    return reader.read().then(step);
  });
}

/* ============================================================ the IPA facts */
function analyzeIpa(zr) {
  var out = {
    warnings: [], extensions: [], frameworks: [], dylibs: [],
    largestEntry: { size: 0, name: '' }
  };
  var roots = zr.find(function (e) {
    return /^Payload\/[^/]+\.app\/$/.test(e.name) && e.method === 0;
  });
  if (!roots.length) {
    out.error = 'No Payload/<App>.app directory at the archive root — this appears not to be an iOS application archive.';
    return Promise.resolve(out);
  }
  var appDir = roots[0].name.replace(/\/$/, '');
  out.appDir = appDir;
  var appPrefix = appDir + '/';
  var infoEntry = zr.byName(appPrefix + 'Info.plist');
  if (!infoEntry) {
    out.error = appPrefix + 'Info.plist is missing inside the archive.';
    return Promise.resolve(out);
  }
  return zr.bytesAt(infoEntry).then(function (b) {
    var pl = parsePlist(b);
    if (!pl) {
      out.error = appPrefix + 'Info.plist parses as neither a binary nor an XML plist.';
      return out;
    }
    var info = pl.top;
    out.info = {
      bundleId: info && info.CFBundleIdentifier,
      name: (info && info.CFBundleName) || (info && info.CFBundleDisplayName) || '',
      version: (info && info.CFBundleShortVersionString) || '',
      build: (info && info.CFBundleVersion) || '',
      minOs: (info && info.MinimumOSVersion) || ''
    };
    var extPrefix = appPrefix + 'PlugIns/';
    out.extensions = zr.find(function (e) {
      return e.name.indexOf(extPrefix) === 0 && /\.appex\/Info\.plist$/.test(e.name);
    });
    var fwPrefix = appPrefix + 'Frameworks/';
    out.frameworks = zr.find(function (e) {
      return e.name.indexOf(fwPrefix) === 0 && /\.framework\/$/.test(e.name);
    }).map(function (e) { return e.name.slice(fwPrefix.length).replace(/\/$/, ''); });
    out.dylibs = zr.find(function (e) { return e.name.indexOf(appPrefix) === 0 && /\.dylib$/.test(e.name); })
      .map(function (e) { return e.name.slice(appPrefix.length); });
    zr.entries.forEach(function (e) {
      if (e.compSize > out.largestEntry.size) out.largestEntry = { size: e.compSize, name: e.name };
    });
    out.ok = true;
    return out;
  }, function (e) {
    out.error = 'Could not read Info.plist bytes: ' + e.message;
    return out;
  });
}
function labelInfo(i) {
  if (!i || !i.bundleId) return 'Info.plist parsed but no CFBundleIdentifier — this IPA is not installable as-is.';
  var s = i.bundleId + ' v' + (i.version || '?');
  if (i.name) s += ' (“' + i.name + '”)';
  if (i.minOs) s += ', requires iOS ' + i.minOs + '+';
  return s;
}

/* ==================================================== profile fact → checks */
function profileFactRows(f, ipaAnalysis) {
  var rows = [];
  rows.push(row('App ID prefix + bundle', VERDICT.VALID,
    (f.prefix || '(no team prefix)') + '.' + (f.bundle || '(no bundle)')));
  if (f.expires) {
    var d = daysUntil(f.expires);
    if (d === null) rows.push(row('Profile expiration', VERDICT.UNVERIFIED, 'ExpirationDate did not parse as a date.'));
    else if (d < 0) rows.push(row('Profile expiration', VERDICT.UNSUPPORTED,
      'this profile expired ' + (-d) + ' day' + (d === -1 ? '' : 's') + ' ago — request a fresh one from your account.'));
    else if (d < 14) rows.push(row('Profile expiration', VERDICT.UNVERIFIED,
      'only ' + d + ' day' + (d === 1 ? '' : 's') + ' left — the signed app will stop launching soon.'));
    else rows.push(row('Profile expiration', VERDICT.VALID,
      d + ' day' + (d === 1 ? '' : 's') + ' of validity left.'));
  } else {
    rows.push(row('Profile expiration', VERDICT.UNVERIFIED, 'this profile carries no ExpirationDate field.'));
  }
  rows.push(row('Team identity', VERDICT.VALID,
    (f.team || '(team id not recorded in the profile)') + (f.teamName ? ' — ' + f.teamName : '')));
  if (f.devices && f.devices.length > 0) {
    rows.push(row('Provisioned devices', VERDICT.VALID,
      f.devices.length + ' UDID' + (f.devices.length === 1 ? '' : 's') + ' registered. Whether YOUR device is one of them cannot be determined inside a browser — the signing tool on the device shows that.'));
  } else if (f.provisionsAllDevices) {
    rows.push(row('Provisioned devices', VERDICT.VALID,
      'not device-bound (ProvisionsAllDevices — an enterprise / In-House profile).'));
  } else {
    rows.push(row('Provisioned devices', VERDICT.UNVERIFIED,
      'no ProvisionedDevices list and no ProvisionsAllDevices flag.'));
  }
  if (f.groups && f.groups.length) {
    rows.push(row('App Groups entitlement', VERDICT.UNVERIFIED,
      'authorised for ' + f.groups.join(', ') + '. Apple free accounts cannot provision App Groups; a signing tool may drop it and widgets will degrade to placeholders rather than crash.'));
  } else {
    rows.push(row('App Groups entitlement', VERDICT.VALID, 'none declared in this profile.'));
  }
  rows.push(row('Push entitlement (aps-environment)', VERDICT.VALID, f.aps ? ('present: ' + f.aps) : 'absent.'));
  rows.push(row('get-task-allow (debuggable)', VERDICT.VALID, f.getTaskAllow ? 'yes (development profile).' : 'no.'));
  if (ipaAnalysis && ipaAnalysis.info && ipaAnalysis.info.bundleId) {
    if (f.prefix && f.bundle) {
      if (f.bundle === ipaAnalysis.info.bundleId) {
        rows.push(row('Profile ↔ app bundle ID', VERDICT.VALID,
          'profile authorises exactly “' + f.bundle + '”.'));
      } else {
        rows.push(row('Profile ↔ app bundle ID', VERDICT.UNSUPPORTED,
          'profile authorises “' + f.bundle + '” but this IPA is signed for “' + ipaAnalysis.info.bundleId +
          '” — use a profile for that exact bundle ID or a matching wildcard.'));
      }
    } else {
      rows.push(row('Profile ↔ app bundle ID', VERDICT.UNVERIFIED,
        'profile does not record an application-identifier entitlement to compare against.'));
    }
  } else {
    rows.push(row('Profile ↔ app bundle ID', VERDICT.UNVERIFIED, 'load the IPA first to cross-check.'));
  }
  return rows;
}

/* ============================================================ state machine */
var STATE = {
  ipa: null, profile: null, p12: null,
  ipaAnalysis: null, profileFacts: null, p12Facts: null,
  ipaDigest: null, busy: false
};
var IDS = {
  file: { ipa: 'file-ipa', profile: 'file-profile', p12: 'file-p12' },
  list: { ipa: 'ipa-results', profile: 'profile-results', p12: 'p12-results' },
  prog: { ipa: 'ipa-progress', profile: 'profile-progress', p12: 'p12-progress' }
};

function beginProgress(kind) {
  var box = document.getElementById(IDS.prog[kind]);
  if (!box) return { progress: function () {}, finish: function () {} };
  box.hidden = false;
  var bar = $('.inst-bar', box), lbl = $('.inst-progress-label', box);
  return {
    progress: function (frac, note) {
      if (frac !== undefined && bar) bar.style.width = Math.max(0, Math.min(100, Math.round(frac * 100))) + '%';
      if (note !== undefined && lbl) lbl.textContent = note;
    },
    finish: function () {
      if (bar) bar.style.width = '100%';
      if (lbl) lbl.textContent = '';
    }
  };
}

function handleFile(file, kind) {
  var listEl = document.getElementById(IDS.list[kind]);
  if (!listEl || !file) return;
  if (STATE.busy) return;
  STATE.busy = true;
  listEl.textContent = '';
  var upd = beginProgress(kind);
  var promise = kind === 'ipa'     ? runIpa(file, listEl, upd)
              : kind === 'profile' ? runProfile(file, listEl)
              : runP12(file, listEl);
  promise.then(function () {
    STATE.busy = false;
    upd.finish(); setStage(); renderSummary();
  }, function (err) {
    STATE.busy = false;
    upd.finish();
    drawRows(listEl, [row(kind.toUpperCase() + ' check', VERDICT.UNVERIFIED,
      err && err.message ? err.message : String(err))]);
    if (kind === 'ipa')     { STATE.ipa = null; STATE.ipaAnalysis = null; STATE.ipaDigest = null; }
    if (kind === 'profile') { STATE.profile = null; STATE.profileFacts = null; }
    if (kind === 'p12')     { STATE.p12 = null; STATE.p12Facts = null; }
    setStage(); renderSummary();
  });
}

/* Stage 1 — one IPA. */
function runIpa(file, listEl, upd) {
  STATE.ipa = null; STATE.ipaAnalysis = null; STATE.ipaDigest = null;
  upd.progress(0.03, 'reading ZIP directory …');
  var zr = new ZipReader(file);
  return zr.init().then(function () {
    return analyzeIpa(zr);
  }).then(function (an) {
    if (an.error) {
      drawRows(listEl, [row('ZIP structure', VERDICT.UNVERIFIED, an.error)]);
      return;
    }
    STATE.ipaAnalysis = an;
    STATE.ipa = file;
    var rows = [];
    rows.push(row('ZIP structure', VERDICT.VALID, zr.eocd.entries + ' entries; Payload root ' + an.appDir + '.'));
    rows.push(row('Main app', VERDICT.VALID, labelInfo(an.info)));
    if (an.frameworks.length)
      rows.push(row('Embedded frameworks (' + an.frameworks.length + ')', VERDICT.VALID,
        an.frameworks.join(', ') + ' — every one must be signed for the profile.'));
    else
      rows.push(row('Embedded frameworks', VERDICT.VALID, 'none.'));
    if (an.dylibs.length)
      rows.push(row('Injected dylibs (' + an.dylibs.length + ')', VERDICT.VALID,
        an.dylibs.join(', ') + ' — tweak dylibs must be signed with the same profile.'));
    else
      rows.push(row('Injected dylibs', VERDICT.VALID, 'none.'));
    var extNames = an.extensions.map(function (e) {
      return e.name.slice(an.appDir.length + 1 + 'PlugIns/'.length).replace('.appex/Info.plist', '');
    });
    rows.push(row('App extensions (' + an.extensions.length + ')', VERDICT.VALID,
      an.extensions.length ? extNames.join(', ') + ' — they need signing coverage too.' : 'none.'));
    drawRows(listEl, rows);
    // SHA-256 in the background so the user can compare against the published checksum.
    return digestFile(file, function (frac) {
      upd.progress(0.2 + frac * 0.78, 'computing SHA-256 … ' + Math.round(frac * 100) + '%');
    }).then(function (d) {
      STATE.ipaDigest = d.hex;
      var li = resultRow(row('SHA-256 of the file you loaded', VERDICT.VALID,
        'computed locally in this tab:'));
      var body = li.querySelector('.inst-row__body');
      var code = document.createElement('code');
      code.className = 'small dim';
      code.style.wordBreak = 'break-all';
      code.textContent = d.hex;
      body.appendChild(code);
      var note = resultRow(row('Compare it yourself', VERDICT.UNVERIFIED,
        'against the checksum that ships NEXT to the release in its own field — this page does not fetch it during use; the string above is the pure local hash of the bytes you picked.'));
      var ul = listEl.querySelector('ul');
      ul.appendChild(li);
      ul.appendChild(note);
    });
  });
}

/* Stage 2 — one .mobileprovision. */
function runProfile(file, listEl) {
  STATE.profile = null; STATE.profileFacts = null;
  return file.arrayBuffer().then(function (ab) {
    var res = parseMobileprovisionBytes(new Uint8Array(ab));
    if (res.error) {
      drawRows(listEl, [row('Profile', VERDICT.UNVERIFIED, res.error)]);
      return;
    }
    var f = describeProfile(res.profile);
    STATE.profile = res.profile;
    STATE.profileFacts = f;
    drawRows(listEl, profileFactRows(f, STATE.ipaAnalysis));
  });
}

/* Stage 2 — one .p12. Structure-only, per the privacy brief. */
function runP12(file, listEl) {
  STATE.p12 = null; STATE.p12Facts = null;
  return file.arrayBuffer().then(function (ab) {
    var r = parseP12Bytes(new Uint8Array(ab));
    STATE.p12 = r;
    STATE.p12Facts = r;
    var rows = [];
    if (r.error) {
      rows.push(row('PKCS#12 container', VERDICT.UNVERIFIED, r.error));
    } else if (r.structural === false) {
      rows.push(row('PKCS#12 container', VERDICT.UNSUPPORTED, r.why));
    } else {
      rows.push(row('PKCS#12 container', VERDICT.VALID,
        'readable PKCS#12 structure' + (r.macPresent ? ' with an integrity MAC.' : '.')));
      rows.push(row('Certificate contents', VERDICT.UNVERIFIED, r.whyEmpty));
    }
    drawRows(listEl, rows);
  });
}

function setStage() {
  var a = document.getElementById('stp-ipa');
  var b = document.getElementById('stp-cred');
  var cJ = document.getElementById('stp-summary');
  var ipaOk = !!(STATE.ipaAnalysis && STATE.ipaAnalysis.ok);
  if (a) a.classList.toggle('done', ipaOk);
  if (b) b.classList.toggle('done', !!(STATE.profileFacts || STATE.p12Facts));
  if (cJ) cJ.classList.toggle('done', !!(ipaOk && STATE.profileFacts));
}

/* ------------------------------------------------------------ the summary */
function renderSummary() {
  var box = document.getElementById('summary');
  if (!box) return;
  var ipaOk = STATE.ipaAnalysis && STATE.ipaAnalysis.ok;
  if (!ipaOk && !STATE.profileFacts && !STATE.p12Facts) { box.hidden = true; return; }
  box.hidden = false;
  box.textContent = '';
  var h = document.createElement('h3');
  h.textContent = 'Review before anything touches a signing tool';
  box.appendChild(h);
  var ul = document.createElement('ul');
  ul.className = 'inst-list';
  if (ipaOk) ul.appendChild(resultRow(row('IPA', VERDICT.VALID, labelInfo(STATE.ipaAnalysis.info))));
  if (STATE.profileFacts) {
    var pf = STATE.profileFacts;
    ul.appendChild(resultRow(row('Profile', VERDICT.VALID,
      pf.name + (pf.prefix ? ' — App ID ' + pf.prefix + '.' + pf.bundle : ''))));
  }
  if (STATE.p12Facts && STATE.p12Facts.structural)
    ul.appendChild(resultRow(row('Certificate', VERDICT.UNVERIFIED,
      'container structure read; contents stayed encrypted on purpose.')));
  box.appendChild(ul);
  var warn = document.createElement('div');
  warn.className = 'callout inst-summary-note';
  warn.innerHTML = '<p class="mb-0"><strong>Next step is not this tab.</strong> ' +
    'Signing runs inside the tool you choose (AltStore, SideStore, Feather, Sideloadly, Xcode) ' +
    'with your credentials on that device — the same property this page promises, ' +
    'enforced by your own operating system. No file was uploaded; no “installation state” ' +
    'is claimed here, because no web page can truthfully observe one.</p>';
  box.appendChild(warn);
}

/* ------------------------------------------------------------- self-test */
/* Builds its own fixtures in memory and exercises the exact code paths the
   workshop uses. Pure, local, zero network. */
function buildZip(entries) {
  var enc = new TextEncoder();
  var parts = [], central = [], off = 0;
  function u16(n) { return [n & 255, (n >> 8) & 255]; }
  function u32(n) { return [n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >>> 24) & 255]; }
  function concatBytes(list) {
    var n = list.reduce(function (a, b) { return a + b.length; }, 0);
    var out = new Uint8Array(n), o = 0;
    list.forEach(function (c) { out.set(c, o); o += c.length; });
    return out;
  }
  function fakeCrc(d) {
    var c = 0x811c9dc5;
    for (var i = 0; i < d.length; i++) { c ^= d[i]; c = (c * 0x01000193) >>> 0; }
    return c >>> 0;
  }
  entries.forEach(function (en) {
    var data = en.bytes || new Uint8Array(0);
    var name = enc.encode(en.name);
    var c = fakeCrc(data);
    central.push({ name: en.name, lho: off, size: data.length, crc: c });
    var localHeader = new Uint8Array([0x50,0x4b,0x03,0x04].concat(
      u16(20), u16(0), u16(0), u16(0), u16(0),
      u32(c), u32(c), u32(data.length), u16(name.length), u16(0)));
    parts.push(localHeader); parts.push(name); parts.push(data);
    off += 30 + name.length + data.length;
  });
  var cdStart = off, cdParts = [], cdLen = 0;
  central.forEach(function (ce) {
    var head = u16(20).concat(u16(20), u16(0), u16(0), u16(0), u16(0),
                              u32(ce.crc), u32(ce.size), u32(ce.size), u16(ce.name.length),
                              u16(0), u16(0), u16(0), u16(0), u32(0), u32(ce.lho));
    var nm = enc.encode(ce.name);
    cdParts.push(new Uint8Array([0x50,0x4b,0x01,0x02].concat(head, Array.prototype.slice.call(nm))));
    cdLen += 46 + nm.length;
  });
  var eocd = new Uint8Array([0x50,0x4b,0x05,0x06].concat(
    u16(0), u16(0), u16(central.length), u16(central.length), u32(cdLen), u32(cdStart), u16(0)));
  parts.push.apply(parts, cdParts);
  parts.push(eocd);
  return concatBytes(parts);
}
var xmlPlistWrap = function (inner) {
  return new TextEncoder().encode(
    '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n' + inner + '</dict>\n</plist>\n');
};
function kv(k, v) { return '<key>' + k + '</key>\n' + v; }
function vs(v) { return '<string>' + v + '</string>\n'; }
function concatBytes2(list) {
  var n = list.reduce(function (a, b) { return a + b.length; }, 0);
  var out = new Uint8Array(n), o = 0;
  list.forEach(function (c) { out.set(c, o); o += c.length; });
  return out;
}
function derTlv(tag, content) {
  var l = content.length, len;
  if (l < 0x80) { len = [l]; }
  else if (l < 0x100) { len = [0x81, l]; }
  else { len = [0x82, (l >> 8) & 255, l & 255]; }
  var out = new Uint8Array(1 + len.length + l);
  out[0] = tag; out.set(len, 1); out.set(content, 1 + len.length);
  return out;
}
function derOid(bytes) { return derTlv(0x06, new Uint8Array(bytes)); }
var OID_SIGNEDDATA = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02];
var OID_P7DATA     = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x01];
function makeCmsEnvelope(plistBytes) {
  var encapObj = derTlv(0xa0, derTlv(0x04, plistBytes));   // [0] → OCTET STRING
  var encapSeq = derTlv(0x30, concatBytes2([derOid(OID_P7DATA), encapObj]));
  var ver      = derTlv(0x02, new Uint8Array([1]));
  var sd       = derTlv(0x30, concatBytes2([ver, encapSeq]));
  var sdWrap   = derTlv(0xa0, sd);                          // [0] → SignedData
  return derTlv(0x30, concatBytes2([derOid(OID_SIGNEDDATA), sdWrap]));
}
function synthProfile(inDays, opts) {
  opts = opts || {};
  var expires = new Date(Date.now() + inDays * DAYS_IN_MS).toISOString();
  var prefix = opts.prefix || 'SELFTESTTEAM';
  var bundle = opts.bundle || 'com.pweevee.selftest';
  var inner =
    kv('Name', vs(opts.name || 'PwEevee SelfTest Profile')) +
    kv('UUID', vs('11111111-2222-3333-4444-555555555555')) +
    kv('TeamName', vs('SelfTest Team')) +
    kv('ExpirationDate', vs(expires)) +
    kv('ApplicationIdentifierPrefix', '<array><string>' + prefix + '</string></array>\n') +
    kv('Entitlements', '<dict>' +
      kv('application-identifier', vs(prefix + '.' + bundle)) +
      kv('get-task-allow', '<' + (opts.getTaskAllow === false ? 'false' : 'true') + '/>') +
      '</dict>\n');
  if (opts.devices) {
    inner += kv('ProvisionedDevices', '<array><string>' + opts.devices.join('</string><string>') + '</string></array>\n');
  }
  return makeCmsEnvelope(xmlPlistWrap(inner));
}
function runSelfTestSuite(hostEl) {
  hostEl.textContent = '';
  var ul = document.createElement('ul');
  ul.className = 'inst-list';
  hostEl.appendChild(ul);
  function verdict(name, cond, note) {
    ul.appendChild(resultRow(row(name, cond ? VERDICT.VALID : VERDICT.UNSUPPORTED, note || '')));
  }
  var enc = new TextEncoder();
  var ipaBytes = buildZip([
    { name: 'Payload/SelfTest.app/', bytes: new Uint8Array(0) },
    { name: 'Payload/SelfTest.app/Info.plist',
      bytes: xmlPlistWrap(kv('CFBundleIdentifier', vs('com.pweevee.selftest')) +
        kv('CFBundleName', vs('SelfTest')) +
        kv('CFBundleShortVersionString', vs('1.2.3')) +
        kv('MinimumOSVersion', vs('15.0'))) },
    { name: 'Payload/SelfTest.app/PlugIns/Widget.appex/', bytes: new Uint8Array(0) },
    { name: 'Payload/SelfTest.app/PlugIns/Widget.appex/Info.plist',
      bytes: xmlPlistWrap(kv('CFBundleIdentifier', vs('com.pweevee.selftest.Widget'))) },
    { name: 'Payload/SelfTest.app/Frameworks/F.framework/', bytes: new Uint8Array(0) },
    { name: 'Payload/SelfTest.app/Frameworks/hook.dylib', bytes: enc.encode('MACHO-BYTES') }
  ]);
  var zr = new ZipReader(new File([ipaBytes], 'selftest.ipa'));
  zr.init().then(function () { return analyzeIpa(zr); }).then(function (an) {
    verdict('IPA reader and analyzer',
      !an.error && an.info && an.info.bundleId === 'com.pweevee.selftest' &&
      an.extensions.length === 1 && an.frameworks.length === 1 &&
      an.dylibs.length === 1 && an.dylibs[0] === 'Frameworks/hook.dylib',
      'bundleId=' + (an.info ? an.info.bundleId : '?') +
      ', appexes=' + an.extensions.length + ', frameworks=' + an.frameworks.length +
      ', dylibs=' + an.dylibs.length);
    var t = checkProfile('Profile parser on a valid synth profile', synthProfile(30, {}),
      function (f) { return f && f.prefix === 'SELFTESTTEAM' && f.bundle === 'com.pweevee.selftest'; },
      function (f, r) { return 'App ID=' + (f ? f.prefix + '.' + f.bundle : '?') + ', expires in ' + (f ? daysUntil(f.expires) : '?') + 'd, via ' + r.how; });
    return t.then(function () {
      return checkProfile('Expired profile is flagged', synthProfile(-5, {}),
        function (f) { return f && daysUntil(f.expires) < 0; },
        function (f) { return 'expired ' + (-daysUntil(f.expires)) + ' day' + (daysUntil(f.expires) === -1 ? '' : 's') + ' ago'; });
    }).then(function () {
      return checkProfile('Profile ↔ bundle mismatch is flagged', synthProfile(40, { bundle: 'com.other.app' }),
        function (f) { return f && f.bundle !== 'com.pweevee.selftest'; },
        function (f) { return 'authorises ' + f.bundle + ' ≠ analyzed bundle com.pweevee.selftest'; });
    }).then(function () {
      // non-profile garbage must say "unsupported" not pass
      var junk = new File([enc.encode('this is not a profile at all')], 'junk.mobileprovision');
      return junk.arrayBuffer().then(function (ab) {
        var r = parseMobileprovisionBytes(new Uint8Array(ab));
        verdict('Non-profile file rejected', !!r.error, (r.error || '').slice(0, 110));
      });
    }).then(function () {
      // synthesized valid PKCS#12 keeps its contents unreadable but structurally detected
      var p12 = makePkcs12Structure();
      return new File([p12], 'identity.p12').arrayBuffer().then(function (ab) {
        var r = parseP12Bytes(new Uint8Array(ab));
        verdict('PKCS#12 structure is detected, contents stay encrypted',
          r && r.structural === true, r.whyEmpty ? r.whyEmpty.slice(0, 110) : '');
      });
    }).then(function () {
      var junk2 = new File([new Uint8Array([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,
        21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,
        49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,
        77,78,79,80])], 'junk.p12');
      return junk2.arrayBuffer().then(function (ab) {
        var r = parseP12Bytes(new Uint8Array(ab));
        verdict('Non-PKCS#12 rejected', r && r.structural === false && !!r.why, r.why);
      });
    });
  }).catch(function (e) {
    verdict('selftest aborted early', false, String(e && e.message || e));
  });
  function checkProfile(testName, profileBytes, cond, note) {
    return new File([profileBytes], 'p.mobileprovision').arrayBuffer().then(function (ab) {
      var r = parseMobileprovisionBytes(new Uint8Array(ab));
      var f = r.profile ? describeProfile(r.profile) : null;
      verdict(testName, !!cond(f, r), note(f, r));
    });
  }
}
function makePkcs12Structure() {
  var ver      = derTlv(0x02, new Uint8Array([3]));
  var encapObj = derTlv(0xa0, derTlv(0x04, new Uint8Array([0x30, 0x80]))); // degenerate auth safe
  var encapSeq = derTlv(0x30, concatBytes2([derOid(OID_P7DATA), encapObj]));
  var mac = derTlv(0x2e, new Uint8Array([0x30, 0x00])); // MAC, IMPLICIT SEQ
  return derTlv(0x30, concatBytes2([derOid(OID_P7DATA), ver, encapSeq, mac]));
}

/* ------------------------------------------------------------------ boot */
function wireInputs() {
  var ipa  = document.getElementById(IDS.file.ipa);
  var prof = document.getElementById(IDS.file.profile);
  var p12  = document.getElementById(IDS.file.p12);
  if (!ipa || !prof || !p12) return;
  function attach(inp) {
    inp.addEventListener('change', function () {
      var lbl = document.querySelector('[data-file-name="' + inp.id + '"]');
      if (lbl) lbl.textContent = inp.files[0] ? inp.files[0].name : 'no file chosen';
    });
  }
  attach(ipa); attach(prof); attach(p12);
  ipa.addEventListener('change',  function () { handleFile(ipa.files[0], 'ipa'); });
  prof.addEventListener('change', function () { handleFile(prof.files[0], 'profile'); });
  p12.addEventListener('change',  function () { handleFile(p12.files[0], 'p12'); });
}

function boot() {
  wireInputs();
  var st = document.getElementById('selftest-btn');
  if (st) st.addEventListener('click', function () { runSelfTestSuite(document.getElementById('selftest')); });
  var clr = document.getElementById('installer-clear');
  if (clr) clr.addEventListener('click', clearSession);
  if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    document.documentElement.classList.add('reduced-motion');
  }
  var notice = document.getElementById('android-notice');
  if (notice && /Android/i.test(navigator.userAgent)) notice.hidden = false;
}

/* Clear: release the file references and blank the UI state. The page copy is
   candid that closing the tab is the reliable cleanup — clearing the references
   lets the engine drop its last strong refs, but browser memory is not
   forensic-grade and we say so plainly in the summary area. */
function clearSession() {
  STATE.ipa = STATE.profile = STATE.p12 = null;
  STATE.ipaAnalysis = STATE.profileFacts = STATE.p12Facts = null;
  STATE.ipaDigest = null;
  STATE.busy = false;
  ['file-ipa', 'file-profile', 'file-p12'].forEach(function (id) {
    var inp = document.getElementById(id);
    if (inp && inp.type === 'file') {
      try { inp.value = ''; } catch (e) { /* some browsers forbid clearing */ }
    }
    var lbl = document.querySelector('[data-file-name="' + id + '"]');
    if (lbl) lbl.textContent = 'no file chosen';
  });
  ['ipa-results', 'profile-results', 'p12-results'].forEach(function (id) {
    var n = document.getElementById(id);
    if (n) n.textContent = '';
  });
  ['ipa-progress', 'profile-progress', 'p12-progress'].forEach(function (id) {
    var n = document.getElementById(id);
    if (!n) return;
    n.hidden = true;
    var bar = $('.inst-bar', n), lbl = $('.inst-progress-label', n);
    if (bar) bar.style.width = '0%';
    if (lbl) lbl.textContent = '';
  });
  setStage();
  renderSummary();
}

/* ------------------------------------------------------- export for tests */
window.__pweeveeInstaller = {
  VERDICT: VERDICT,
  SHA256: SHA256,
  ZipReader: ZipReader,
  parsePlist: parsePlist,
  parseMobileprovisionBytes: parseMobileprovisionBytes,
  parseP12Bytes: parseP12Bytes,
  describeProfile: describeProfile,
  profileFactRows: profileFactRows,
  analyzeIpa: analyzeIpa,
  buildZip: buildZip,
  synthProfile: synthProfile,
  makeCmsEnvelope: makeCmsEnvelope,
  daysUntil: daysUntil,
  digestFile: digestFile,
  runSelfTestSuite: runSelfTestSuite,
  STATE: STATE
};
})();
