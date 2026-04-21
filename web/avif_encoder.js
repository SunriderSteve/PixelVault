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
   * @returns {Promise<boolean>}
   */
  async function canEncodeAvif() {
    if (_canAvif !== null) return _canAvif;
    try {
      const c = new OffscreenCanvas(1, 1);
      const blob = await c.convertToBlob({ type: 'image/avif' });
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

    // Encode — prefer AVIF, fall back to WebP.
    const useAvif = await canEncodeAvif();
    const mime = useAvif ? 'image/avif' : 'image/webp';
    const ext = useAvif ? 'avif' : 'webp';

    const encoded = await canvas.convertToBlob({ type: mime, quality: quality });
    const buffer = await encoded.arrayBuffer();

    return { buffer: buffer, ext: ext };
  }

  // ── Expose to Dart via window globals ─────────────────────────

  window.pvCanEncodeAvif = canEncodeAvif;
  window.pvConvertToAvif = convertToAvif;
})();
