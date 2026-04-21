// PixelVault — AVIF image converter (web only).
//
// Wraps the browser-side canvas encoder exposed by `web/avif_encoder.js`.
// Falls back to WebP if the browser does not support AVIF encoding.

import 'dart:js_interop';

import 'package:flutter/foundation.dart';

// ── JS interop bindings ─────────────────────────────────────────

@JS('pvCanEncodeAvif')
external JSPromise<JSBoolean> _pvCanEncodeAvif();

@JS('pvConvertToAvif')
external JSPromise<_JsConvertResult> _pvConvertToAvif(
  JSArrayBuffer arrayBuffer,
  JSNumber quality,
);

/// Mirrors the JS object `{ buffer: ArrayBuffer, ext: string }`.
extension type _JsConvertResult._(JSObject _) implements JSObject {
  external JSArrayBuffer get buffer;
  external JSString get ext;
}

// ── Result type ─────────────────────────────────────────────────

/// Result of an image conversion: the encoded bytes and the file
/// extension that was actually produced ('avif' or 'webp').
class ConvertResult {
  final Uint8List bytes;
  final String ext;
  const ConvertResult({required this.bytes, required this.ext});
}

// ── Public API ──────────────────────────────────────────────────

/// Whether the current browser supports AVIF encoding via canvas.
/// Caches the result after the first call.
Future<bool> canEncodeAvif() async {
  try {
    final result = await _pvCanEncodeAvif().toDart;
    return result.toDart;
  } catch (_) {
    return false;
  }
}

/// Convert image bytes (any browser-decodable format) to AVIF,
/// falling back to WebP if AVIF encoding is not supported.
///
/// Returns the encoded bytes and the file extension used.
Future<ConvertResult> convertToAvif(
  Uint8List input, {
  double quality = 0.75,
}) async {
  try {
    final jsBuffer = input.buffer.toJS;
    final jsResult = await _pvConvertToAvif(jsBuffer, quality.toJS).toDart;

    return ConvertResult(
      bytes: jsResult.buffer.toDart.asUint8List(),
      ext: jsResult.ext.toDart,
    );
  } catch (e) {
    debugPrint('AVIF conversion failed: $e');
    rethrow;
  }
}
