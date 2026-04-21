// PixelVault — Clipboard image reader (web only).
//
// Uses the browser Clipboard API to read image data that the user
// has copied (e.g. screenshot, image from another app).

import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Read all image items currently on the system clipboard.
///
/// Returns a list of raw image bytes (one per clipboard item that has
/// an image MIME type). Returns an empty list if nothing is available,
/// the API is not supported, or the user denies permission.
Future<List<Uint8List>> getClipboardImages() async {
  try {
    final clipboard = web.window.navigator.clipboard;
    final items = await clipboard.read().toDart;

    final results = <Uint8List>[];
    for (var i = 0; i < items.length; i++) {
      final item = items.toDart[i];
      final types = item.types.toDart;

      for (final type in types) {
        final mimeType = type.toDart;
        if (!mimeType.startsWith('image/')) continue;

        final blob = await item.getType(mimeType).toDart;
        final buffer = await blob.arrayBuffer().toDart;
        results.add(buffer.toDart.asUint8List());
      }
    }
    return results;
  } catch (e) {
    debugPrint('Clipboard read failed: $e');
    return [];
  }
}
