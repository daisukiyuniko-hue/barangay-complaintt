/* ==========================================================================
   crypto.js - password hashing for the static build
   --------------------------------------------------------------------------
   Passwords are NEVER stored in plain text. Every account keeps only a random
   salt, the derived key and the iteration count.

   Two engines:
     1. Web Crypto  (crypto.subtle)  - PBKDF2-HMAC-SHA256, 150,000 rounds.
        Available in secure contexts (https:// and http://localhost).
     2. Pure JavaScript fallback - same algorithm, fewer rounds, used when the
        page is opened straight from disk (file://) or over plain http on a LAN
        address, where crypto.subtle is not exposed.

   The active engine is reported by Crypto.engine() so the UI can be honest
   about it instead of silently weakening the hashing.
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  var ITERATIONS_WEB = 150000;   // strong: used in secure contexts
  var ITERATIONS_JS  = 20000;    // fallback: pure JS is ~10x slower

  // ------------------------------------------------------------- helpers --
  function hasWebCrypto() {
    return (typeof crypto !== 'undefined' &&
            crypto && crypto.subtle &&
            typeof crypto.subtle.deriveBits === 'function' &&
            typeof crypto.getRandomValues === 'function');
  }

  // crypto.subtle only exists in a secure context.
  function isSecureContext() {
    try { return (typeof isSecureContext === 'undefined') || window.isSecureContext; }
    catch (e) { return false; }
  }

  function toBase64(bytes) {
    var binary = '';
    for (var i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    return btoa(binary);
  }

  function fromBase64(text) {
    var binary = atob(text);
    var out = new Uint8Array(binary.length);
    for (var i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
    return out;
  }

  function randomBytes(count) {
    var out = new Uint8Array(count);
    crypto.getRandomValues(out);
    return out;
  }

  function randomId(prefix) {
    return prefix + '_' + toBase64(randomBytes(9)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  function toHex(bytes) {
    var hex = '';
    for (var i = 0; i < bytes.length; i++) {
      hex += ('0' + bytes[i].toString(16)).slice(-2);
    }
    return hex;
  }

  // -------------------------------------------- pure JS SHA-256 (fallback) --
  var K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ];

  function sha256(bytes) {
    var h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
             0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];

    var len = bytes.length;
    var bitLenHi = Math.floor(len / 536870912);
    var bitLenLo = (len << 3) >>> 0;

    var paddedLen = ((len + 9 + 63) >> 6) << 6;
    var msg = new Uint8Array(paddedLen);
    msg.set(bytes);
    msg[len] = 0x80;
    msg[paddedLen - 8] = (bitLenHi >>> 24) & 0xff;
    msg[paddedLen - 7] = (bitLenHi >>> 16) & 0xff;
    msg[paddedLen - 6] = (bitLenHi >>> 8) & 0xff;
    msg[paddedLen - 5] = bitLenHi & 0xff;
    msg[paddedLen - 4] = (bitLenLo >>> 24) & 0xff;
    msg[paddedLen - 3] = (bitLenLo >>> 16) & 0xff;
    msg[paddedLen - 2] = (bitLenLo >>> 8) & 0xff;
    msg[paddedLen - 1] = bitLenLo & 0xff;

    var w = new Int32Array(64);
    for (var off = 0; off < paddedLen; off += 64) {
      var i;
      for (i = 0; i < 16; i++) {
        w[i] = ((msg[off + i * 4] << 24) | (msg[off + i * 4 + 1] << 16) |
               (msg[off + i * 4 + 2] << 8) | msg[off + i * 4 + 3]) | 0;
      }
      for (i = 16; i < 64; i++) {
        var s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        var s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
      }

      var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];

      for (i = 0; i < 64; i++) {
        var S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        var ch = (e & f) ^ (~e & g);
        var t1 = (hh + S1 + ch + K[i] + w[i]) | 0;
        var S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        var maj = (a & b) ^ (a & c) ^ (b & c);
        var t2 = (S0 + maj) | 0;

        hh = g; g = f; f = e; e = (d + t1) | 0;
        d = c; c = b; b = a; a = (t1 + t2) | 0;
      }

      h[0] = (h[0] + a) | 0; h[1] = (h[1] + b) | 0; h[2] = (h[2] + c) | 0; h[3] = (h[3] + d) | 0;
      h[4] = (h[4] + e) | 0; h[5] = (h[5] + f) | 0; h[6] = (h[6] + g) | 0; h[7] = (h[7] + hh) | 0;
    }

    var out = new Uint8Array(32);
    for (var j = 0; j < 8; j++) {
      out[j * 4]     = (h[j] >>> 24) & 0xff;
      out[j * 4 + 1] = (h[j] >>> 16) & 0xff;
      out[j * 4 + 2] = (h[j] >>> 8) & 0xff;
      out[j * 4 + 3] = h[j] & 0xff;
    }
    return out;
  }

  function rotr(x, n) { return ((x >>> n) | (x << (32 - n))) | 0; }

  function hmacSha256(key, message) {
    var blockSize = 64;
    var k = key;
    if (k.length > blockSize) k = sha256(k);

    var padded = new Uint8Array(blockSize);
    padded.set(k);

    var inner = new Uint8Array(blockSize + message.length);
    var outer = new Uint8Array(blockSize + 32);
    for (var i = 0; i < blockSize; i++) {
      inner[i] = padded[i] ^ 0x36;
      outer[i] = padded[i] ^ 0x5c;
    }
    inner.set(message, blockSize);
    outer.set(sha256(inner), blockSize);
    return sha256(outer);
  }

  function pbkdf2Js(passwordBytes, saltBytes, iterations, dkLen) {
    var hLen = 32;
    var blocks = Math.ceil(dkLen / hLen);
    var output = new Uint8Array(blocks * hLen);

    for (var block = 1; block <= blocks; block++) {
      var saltBlock = new Uint8Array(saltBytes.length + 4);
      saltBlock.set(saltBytes);
      saltBlock[saltBytes.length]     = (block >>> 24) & 0xff;
      saltBlock[saltBytes.length + 1] = (block >>> 16) & 0xff;
      saltBlock[saltBytes.length + 2] = (block >>> 8) & 0xff;
      saltBlock[saltBytes.length + 3] = block & 0xff;

      var u = hmacSha256(passwordBytes, saltBlock);
      var acc = new Uint8Array(u);
      for (var i = 1; i < iterations; i++) {
        u = hmacSha256(passwordBytes, u);
        for (var j = 0; j < hLen; j++) acc[j] ^= u[j];
      }
      output.set(acc, (block - 1) * hLen);
    }
    return output.slice(0, dkLen);
  }

  // ---------------------------------------------------------------- public --
  function engine() {
    if (hasWebCrypto() && isSecureContext()) {
      return { name: 'webcrypto', algorithm: 'PBKDF2-HMAC-SHA256', iterations: ITERATIONS_WEB, strong: true };
    }
    return {
      name: 'javascript',
      algorithm: 'PBKDF2-HMAC-SHA256',
      iterations: ITERATIONS_JS,
      strong: false,
      note: 'The secure Web Crypto API is unavailable here, so a built-in JavaScript ' +
            'implementation is used with fewer rounds. Serve the page over https:// ' +
            'or http://localhost to get the strong version.'
    };
  }

  /**
   * Hashes a password. Returns a record safe to store:
   * { algorithm, iterations, salt, hash }
   */
  function hashPassword(password) {
    var info = engine();
    var salt = randomBytes(16);
    var passwordBytes = new TextEncoder().encode(password);

    if (info.name === 'webcrypto') {
      return crypto.subtle.importKey('raw', passwordBytes, 'PBKDF2', false, ['deriveBits'])
        .then(function (key) {
          return crypto.subtle.deriveBits({
            name: 'PBKDF2',
            salt: salt,
            iterations: info.iterations,
            hash: 'SHA-256'
          }, key, 256);
        })
        .then(function (bits) {
          return {
            algorithm: 'PBKDF2-HMAC-SHA256',
            iterations: info.iterations,
            salt: toBase64(salt),
            hash: toBase64(new Uint8Array(bits))
          };
        });
    }

    // Yield once so the busy spinner can paint before the synchronous work.
    return new Promise(function (resolve) {
      setTimeout(function () {
        var derived = pbkdf2Js(passwordBytes, salt, info.iterations, 32);
        resolve({
          algorithm: 'PBKDF2-HMAC-SHA256',
          iterations: info.iterations,
          salt: toBase64(salt),
          hash: toBase64(derived)
        });
      }, 20);
    });
  }

  /**
   * Re-derives with the stored salt + iteration count and compares in
   * constant time.
   *
   * Accepts either shape:
   *   - a raw hash record  { salt, hash, iterations }
   *   - a stored account   { passwordSalt, passwordHash, passwordIterations }
   */
  function verifyPassword(password, record) {
    if (!record) return Promise.resolve(false);

    var saltB64 = record.salt || record.passwordSalt;
    var hashB64 = record.hash || record.passwordHash;
    if (!saltB64 || !hashB64) return Promise.resolve(false);

    var iterations = parseInt(record.iterations || record.passwordIterations, 10);
    if (!iterations || iterations < 1) iterations = ITERATIONS_WEB;

    var salt, expectedBytes;
    try {
      salt = fromBase64(saltB64);
      expectedBytes = fromBase64(hashB64);
    } catch (e) { return Promise.resolve(false); }
    if (!salt.length || !expectedBytes.length) return Promise.resolve(false);

    var passwordBytes = new TextEncoder().encode(password);
    var promise;

    if (typeof crypto !== 'undefined' && crypto.subtle && isSecureContext()) {
      promise = crypto.subtle.importKey('raw', passwordBytes, 'PBKDF2', false, ['deriveBits'])
        .then(function (key) {
          return crypto.subtle.deriveBits({
            name: 'PBKDF2',
            salt: salt,
            iterations: iterations,
            hash: 'SHA-256'
          }, key, expectedBytes.length * 8);
        })
        .then(function (bits) { return new Uint8Array(bits); });
    } else {
      promise = new Promise(function (resolve) {
        setTimeout(function () { resolve(pbkdf2Js(passwordBytes, salt, iterations, expectedBytes.length)); }, 20);
      });
    }

    return promise.then(function (actual) {
      if (actual.length !== expectedBytes.length) return false;
      var diff = 0;
      for (var i = 0; i < actual.length; i++) diff |= actual[i] ^ expectedBytes[i];
      return diff === 0;
    }).catch(function () { return false; });
  }

  App.Crypto = {
    engine: engine,
    hashPassword: hashPassword,
    verifyPassword: verifyPassword,
    randomId: randomId,
    randomBytes: randomBytes,
    toBase64: toBase64,
    fromBase64: fromBase64,
    toHex: toHex,
    ITERATIONS_WEB: ITERATIONS_WEB,
    ITERATIONS_JS: ITERATIONS_JS,
    _sha256: sha256,
    _pbkdf2: pbkdf2Js
  };
})(window.App);