// PixelVault — Client-side image-to-AVIF converter.
//
// Uses the browser's OffscreenCanvas (or HTMLCanvasElement fallback)
// to re-encode an arbitrary image (PNG, JPG, WebP, …) as AVIF.
// Falls back to WebP if the browser does not support AVIF encoding.

(function () {
  'use strict';

  // ── Capability detection ──────────────────────────────────────

  /** @type {boolean|null} cached result */
  let _canAvif = null;

  /**
   * Test whether the browser can encode AVIF via canvas.
   * Caches the result after the first call.
   *
   * The probe uses a 64×64 canvas with actual pixel content rather
   * than a 1×1 blank one. AV1 (AVIF's underlying codec) has block-size
   * minimums and Chromium's encoder bails to PNG silently for tiny
   * blank inputs even on builds that handle real images fine — the
   * old 1×1 probe gave a false negative on every browser we ship to,
   * making `convertToAvif` always fall through to WebP.
   *
   * Per the canvas spec, when the requested MIME isn't supported the
   * resulting blob is PNG, so the type check at the end stays the
   * authoritative signal.
   *
   * @returns {Promise<boolean>}
   */
  async function canEncodeAvif() {
    if (_canAvif !== null) return _canAvif;
    try {
      const c = new OffscreenCanvas(64, 64);
      const ctx = c.getContext('2d');
      // Solid fill so the encoder has real pixel data to work with.
      ctx.fillStyle = '#ff0000';
      ctx.fillRect(0, 0, 64, 64);
      const blob = await c.convertToBlob({ type: 'image/avif', quality: 0.5 });
      _canAvif = blob.type === 'image/avif';
    } catch (_) {
      _canAvif = false;
    }
    return _canAvif;
  }

  // ── Conversion ────────────────────────────────────────────────

  /**
   * Convert arbitrary image bytes to AVIF (or WebP fallback).
   *
   * @param {ArrayBuffer} arrayBuffer  Raw image bytes (any browser-decodable format).
   * @param {number}      quality      Encode quality 0..1 (default 0.75).
   * @returns {Promise<{buffer: ArrayBuffer, ext: string}>}
   *          The encoded bytes and the file extension that was actually used
   *          ('avif' or 'webp').
   */
  async function convertToAvif(arrayBuffer, quality) {
    if (quality === undefined || quality === null) quality = 0.75;

    // Decode the source image.
    const blob = new Blob([arrayBuffer]);
    const bitmap = await createImageBitmap(blob);

    // Draw onto an OffscreenCanvas.
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
    const ctx = canvas.getContext('2d');
    ctx.drawImage(bitmap, 0, 0);
    bitmap.close();

    // Try AVIF first (subject to capability probe), then fall back to
    // WebP. The runtime check on `encoded.type` is the safety net for
    // a probe false positive: per the canvas spec, an unsupported MIME
    // yields a PNG blob, which we'd otherwise upload mislabelled as
    // `.avif`.
    if (await canEncodeAvif()) {
      const encoded = await canvas.convertToBlob({
        type: 'image/avif',
        quality: quality,
      });
      if (encoded.type === 'image/avif') {
        return { buffer: await encoded.arrayBuffer(), ext: 'avif' };
      }
      // Probe lied — invalidate the cache so we don't ask again.
      _canAvif = false;
    }

    const encoded = await canvas.convertToBlob({
      type: 'image/webp',
      quality: quality,
    });
    return { buffer: await encoded.arrayBuffer(), ext: 'webp' };
  }

  // ── Expose to Dart via window globals ─────────────────────────

  window.pvCanEncodeAvif = canEncodeAvif;
  window.pvConvertToAvif = convertToAvif;
})();
