// PixelVault — Image widget that auto-selects AVIF vs standard decoder.
//
// Drop-in replacement for `AvifImage.network` that falls back to the
// regular `Image.network` for formats the AVIF decoder can't handle
// (WebP, PNG, JPEG, ...). The choice is based on the file extension.

import 'package:flutter/material.dart';
import 'package:flutter_avif/flutter_avif.dart';

class SmartImage extends StatelessWidget {
  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;

  const SmartImage.network(
    this.url, {
    super.key,
    this.fit,
    this.width,
    this.height,
    this.errorBuilder,
  });

  bool get _isAvif {
    final path = url.split('?').first.toLowerCase();
    return path.endsWith('.avif');
  }

  @override
  Widget build(BuildContext context) {
    if (_isAvif) {
      return AvifImage.network(
        url,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: errorBuilder,
      );
    }
    return Image.network(
      url,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: errorBuilder,
    );
  }
}
