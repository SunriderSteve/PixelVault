// PixelVault — Inventory overlay HTTP client.
//
// Thin wrapper around the GitHub Gist-backed inventory overlay file.
// All reads and writes go through here so [DataRepository] doesn't
// need to know about HTTP, CORS, or the gist API shape.
//
// Read path: [_tryRaw] → [_tryApi] fallback
//   • [_tryRaw] hits `gist.githubusercontent.com/.../<sha>/...` with a
//     cache-busting query param. Fastest endpoint, but served by a
//     CDN that can lag a write by up to a few minutes.
//   • [_tryApi] calls `api.github.com/gists/<id>` and pulls the file
//     contents out of the JSON response. Slower but always current.
//   • Both are called without custom headers on purpose — that keeps
//     browsers from firing a CORS preflight, which the raw endpoint
//     does not support.
//
// Write path: PATCH `api.github.com/gists/<id>` with the merged YAML.
// GitHub's PATCH response echoes the updated gist file, so the caller
// can use it as ground truth without a follow-up GET.
//
// YAML shape (overlay file):
//
//     <equipment_id>:
//       quantity: <int>
//       storage: "<string>"
//
// Exactly one entry per equipment id, holding only the mutable
// inventory fields. All static fields (name, brand, images, …) live
// in the bundled asset YAMLs instead.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../models/admin_config_model.dart';

/// Fetches and mutates the inventory overlay stored in a public
/// GitHub Gist. One instance is owned by [DataRepository] — callers
/// should not create their own.
class InventoryOverlayClient {
  final AdminConfigModel admin;

  const InventoryOverlayClient(this.admin);

  // ── Public read API ─────────────────────────────────────────────

  /// Fetch the overlay map `id -> {quantity, storage}`.
  ///
  /// Tries the raw CDN first and falls back to the GitHub API. Returns
  /// null only if both endpoints fail — an empty map is returned when
  /// the gist file exists but is blank.
  Future<Map<String, Map<String, dynamic>>?> fetch() async {
    final raw = await _tryRaw();
    if (raw != null) return raw;

    final api = await _tryApi();
    if (api != null) return api;

    return null;
  }

  // ── Read: raw CDN (fast, can be stale) ──────────────────────────

  /// Attempt a raw gist fetch without custom headers so the browser
  /// doesn't fire a CORS preflight. Returns null on any failure so
  /// [fetch] can cleanly fall back to the API path.
  Future<Map<String, Map<String, dynamic>>?> _tryRaw() async {
    final String rawUrl = admin.gistRawUrl.trim();
    if (rawUrl.isEmpty || !rawUrl.contains('gist.githubusercontent.com')) {
      return null;
    }

    try {
      final base = Uri.parse(rawUrl);
      // Cache-bust with a millisecond timestamp — the CDN keys on the
      // full URL, so this forces a fresh lookup even while the shared
      // edge cache is still serving stale content to other clients.
      final uri = base.replace(
        queryParameters: {
          ...base.queryParameters,
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );

      // Keep the request header-less so it stays a "simple request"
      // under the CORS spec and skips the OPTIONS preflight.
      final resp = await http.get(uri);
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        return _parseYaml(resp.body);
      }
      debugPrint('overlay raw non-OK ${resp.statusCode}: ${resp.reasonPhrase}');
      return null;
    } catch (e) {
      debugPrint('overlay raw exception $e');
      return null;
    }
  }

  // ── Read: GitHub API fallback ───────────────────────────────────

  /// Fallback read via the GitHub API. Used for public gists when the
  /// raw endpoint is unavailable and as the authoritative source on
  /// any code path that needs fresh data ([_readViaApi] is the
  /// authenticated variant used by the write path).
  Future<Map<String, Map<String, dynamic>>?> _tryApi() async {
    final String id = admin.gistId.trim();
    final String file = admin.gistFile.trim();
    if (id.isEmpty) return null;

    try {
      final uri = Uri.parse('https://api.github.com/gists/$id');
      // Same header-less request strategy as the raw path — avoids
      // preflight on the web build.
      final resp = await http.get(uri);
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final files = body['files'] as Map<String, dynamic>?;
        final f = files?[file] as Map<String, dynamic>?;
        final content = f?['content'] as String?;
        if (content != null) return _parseYaml(content);

        debugPrint('overlay api file missing $file');
        return null;
      }
      debugPrint('overlay api non-OK ${resp.statusCode}: ${resp.reasonPhrase}');
      return null;
    } catch (e) {
      debugPrint('overlay api exception $e');
      return null;
    }
  }

  // ── YAML parse ──────────────────────────────────────────────────

  /// Parse the overlay YAML into the canonical `id -> {quantity,
  /// storage}` map shape. Silently drops entries with an empty id or a
  /// non-map value so a malformed record can't crash the app.
  Map<String, Map<String, dynamic>> _parseYaml(String yamlStr) {
    final String trimmed = yamlStr.trim();
    if (trimmed.isEmpty) return {};
    final y = loadYaml(trimmed);
    if (y is! YamlMap) return {};

    final out = <String, Map<String, dynamic>>{};
    for (final e in y.entries) {
      final String id = e.key?.toString() ?? '';
      final val = e.value;
      if (id.isEmpty || val is! YamlMap) continue;
      out[id] = {
        'quantity': (val['quantity'] as num?)?.toInt(),
        'storage': val['storage'] as String?,
      };
    }
    return out;
  }

  // ── Write path ──────────────────────────────────────────────────

  /// Update a single equipment entry in the overlay gist.
  ///
  /// Pass only the fields you want to change — nulls are left alone so
  /// the caller can send a quantity update without wiping the storage,
  /// and vice versa. A call with both arguments null does no write and
  /// just returns a fresh read, so callers don't end up with a stale
  /// view after a no-op.
  ///
  /// Returns the authoritative post-write overlay map parsed from the
  /// PATCH response so callers can apply ground truth without a second
  /// GET round trip.
  Future<Map<String, Map<String, dynamic>>> updateEntry(
    String equipmentId, {
    int? quantity,
    String? storage,
    required String token, // GitHub PAT with gist scope
  }) async {
    if (quantity == null && storage == null) {
      // Nothing to change — hand back current state via a fresh API
      // read so the caller doesn't end up with a stale view.
      return _readViaApi(token);
    }

    // Read the pre-write baseline via the authenticated API rather
    // than the raw CDN — the raw endpoint serves cached content and
    // can miss a concurrent admin's edit, which would cause us to
    // clobber their change on write.
    final current = await _readViaApi(token);

    // Merge the minimal change into the existing entry (or create a
    // brand-new entry for an id that had no overlay record yet).
    final entry = Map<String, dynamic>.from(current[equipmentId] ?? const {});
    if (quantity != null) entry['quantity'] = quantity;
    if (storage != null) entry['storage'] = storage;
    current[equipmentId] = entry;

    // Serialize back to YAML and PATCH the gist file.
    final String updatedYaml = _overlayMapToYaml(current);
    final patchUri = Uri.parse('https://api.github.com/gists/${admin.gistId}');
    final body = jsonEncode({
      'files': {
        admin.gistFile: {'content': updatedYaml},
      },
    });

    final headers = {
      'Authorization': 'token $token',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Content-Type': 'application/json',
    };

    final patchResp = await http.patch(patchUri, headers: headers, body: body);
    if (patchResp.statusCode ~/ 100 != 2) {
      throw Exception(
        'overlay write failed: ${patchResp.statusCode} ${patchResp.body}',
      );
    }

    // GitHub's PATCH response echoes the updated gist including file
    // content, so we can return ground truth directly — no extra
    // fetch, no CDN lag.
    try {
      final respJson = jsonDecode(patchResp.body) as Map<String, dynamic>;
      final files = respJson['files'] as Map<String, dynamic>?;
      final f = files?[admin.gistFile] as Map<String, dynamic>?;
      final content = f?['content'] as String?;
      if (content != null) return _parseYaml(content);
    } catch (e) {
      debugPrint('overlay patch response parse failed: $e');
    }

    // Fallback: the PATCH succeeded but we couldn't parse its echo —
    // we still know exactly what we just wrote, so hand that back.
    return current;
  }

  /// Read the overlay map via the authenticated GitHub API. Always
  /// fresh (bypasses the raw CDN) and therefore safe to use as the
  /// pre-write baseline for a merge.
  Future<Map<String, Map<String, dynamic>>> _readViaApi(String token) async {
    final String id = admin.gistId.trim();
    final String file = admin.gistFile.trim();
    if (id.isEmpty) {
      throw Exception('gistId missing in admin config');
    }

    final uri = Uri.parse('https://api.github.com/gists/$id');
    final resp = await http.get(
      uri,
      headers: {
        'Authorization': 'token $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (resp.statusCode ~/ 100 != 2) {
      throw Exception('overlay read failed: ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final files = body['files'] as Map<String, dynamic>?;
    final f = files?[file] as Map<String, dynamic>?;
    final content = f?['content'] as String?;
    if (content == null) return {};
    return _parseYaml(content);
  }

  // ── YAML serialize ──────────────────────────────────────────────

  /// Emit a stable, minimal YAML document for the overlay map. Keys
  /// are sorted so successive writes produce byte-identical output
  /// when nothing changed — this keeps diffs in the gist history
  /// meaningful rather than a churn of reordered entries.
  ///
  /// Storage values are JSON-encoded to get proper string escaping
  /// (quotes, unicode, etc.) without pulling in a YAML writer.
  String _overlayMapToYaml(Map<String, Map<String, dynamic>> m) {
    final ids = m.keys.toList()..sort();
    final b = StringBuffer();
    for (final id in ids) {
      final v = m[id] ?? const {};
      b.writeln('$id:');
      if (v['quantity'] != null) b.writeln('  quantity: ${v['quantity']}');
      if (v['storage'] != null) {
        b.writeln('  storage: ${jsonEncode(v['storage'])}');
      }
    }
    return b.toString();
  }
}
