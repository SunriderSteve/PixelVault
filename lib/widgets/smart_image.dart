// PixelVault — Image widget that auto-selects AVIF vs standard decoder.
//
// Drop-in replacement for `AvifImage.network` / `Image.memory` that
// falls back to the regular Flutter decoder for formats the AVIF
// decoder can't handle (WebP, PNG, JPEG, ...). Network selection is
// based on the URL extension; memory selection sniffs the magic bytes
// because picked/pasted bytes have no filename to inspect.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_avif/flutter_avif.dart';

class SmartImage extends StatelessWidget {
  final String? url;
  final Uint8List? bytes;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  const SmartImage.network(
    String this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.errorBuilder,
  }) : bytes = null;

  const SmartImage.memory(
    Uint8List this.bytes, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.errorBuilder,
  }) : url = null;

  bool get _urlIsAvif {
    final path = url!.split('?').first.toLowerCase();
    return path.endsWith('.avif');
  }

  // ISOBMFF AVIF: bytes 4..7 are 'ftyp' and the major brand at 8..11
  // starts with 'avi' (covers 'avif', 'avis', 'avio'). Sniffing is
  // necessary because picked/pasted bytes don't carry a filename.
  static bool _bytesAreAvif(Uint8List b) {
    if (b.length < 12) return false;
    return b[4] == 0x66 && // 'f'
        b[5] == 0x74 && // 't'
        b[6] == 0x79 && // 'y'
        b[7] == 0x70 && // 'p'
        b[8] == 0x61 && // 'a'
        b[9] == 0x76 && // 'v'
        b[10] == 0x69; // 'i'
  }

  @override
  Widget build(BuildContext context) {
    if (bytes != null) {
      if (_bytesAreAvif(bytes!)) {
        return AvifImage.memory(
          bytes!,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: errorBuilder,
        );
      }
      return Image.memory(
        bytes!,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: errorBuilder,
      );
    }
    if (_urlIsAvif) {
      return AvifImage.network(
        url!,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: errorBuilder,
      );
    }
    return Image.network(
      url!,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: errorBuilder,
    );
  }
}
