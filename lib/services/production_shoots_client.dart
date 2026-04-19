// PixelVault — Production shoots Gist client.
//
// Manages production shoot lists stored as a YAML file inside the same
// GitHub Gist used by the inventory overlay. Each shoot is a named map
// of equipment IDs to their checked-off state and bring-quantity.
//
// YAML shape (production_shoots.yaml):
//
//     "My Shoot":
//       canon_c200:
//         c: false
//         q: 2
//       rode_ntg5:
//         c: true
//         q: 1
//     "Another Shoot":
//       aputure_300d:
//         c: false
//         q: 3
//
// Read and write paths mirror [InventoryOverlayClient] — raw CDN first,
// API fallback, authenticated PATCH for writes.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../models/admin_config_model.dart';

/// A single equipment entry inside a production shoot.
///
/// Regular catalog items leave [name] null — the display name comes from
/// the Equipment record in the repo. Custom items (ids starting with
/// `custom_`) store their user-given name here instead.
class ShootEquip {
  bool checked;
  int qty;
  String? name;

  ShootEquip({this.checked = false, this.qty = 1, this.name});
}

/// CRUD client for production shoot lists stored in a GitHub Gist.
class ProductionShootsClient {
  final AdminConfigModel admin;

  const ProductionShootsClient(this.admin);

  // ── Public read API ─────────────────────────────────────────────

  /// Fetch all shoots: `shootName -> { equipId -> ShootEquip }`.
  Future<Map<String, Map<String, ShootEquip>>?> fetch() async {
    final raw = await _tryRaw();
    if (raw != null) return raw;

    final api = await _tryApi();
    if (api != null) return api;

    return null;
  }

  // ── Read: raw CDN ───────────────────────────────────────────────

  Future<Map<String, Map<String, ShootEquip>>?> _tryRaw() async {
    final String rawUrl = admin.shootsRawUrl.trim();
    if (rawUrl.isEmpty || !rawUrl.contains('gist.githubusercontent.com')) {
      return null;
    }

    try {
      final base = Uri.parse(rawUrl);
      final uri = base.replace(
        queryParameters: {
          ...base.queryParameters,
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );

      final resp = await http.get(uri);
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        return _parseYaml(resp.body);
      }
      debugPrint('shoots raw non-OK ${resp.statusCode}: ${resp.reasonPhrase}');
      return null;
    } catch (e) {
      debugPrint('shoots raw exception $e');
      return null;
    }
  }

  // ── Read: GitHub API fallback ───────────────────────────────────

  Future<Map<String, Map<String, ShootEquip>>?> _tryApi() async {
    final String id = admin.gistId.trim();
    final String file = admin.shootsFile.trim();
    if (id.isEmpty) return null;

    try {
      final uri = Uri.parse('https://api.github.com/gists/$id');
      final resp = await http.get(uri);
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final files = body['files'] as Map<String, dynamic>?;
        final f = files?[file] as Map<String, dynamic>?;
        final content = f?['content'] as String?;
        if (content != null) return _parseYaml(content);

        // File doesn't exist yet — return empty.
        return {};
      }
      debugPrint('shoots api non-OK ${resp.statusCode}: ${resp.reasonPhrase}');
      return null;
    } catch (e) {
      debugPrint('shoots api exception $e');
      return null;
    }
  }

  // ── YAML parse ──────────────────────────────────────────────────

  Map<String, Map<String, ShootEquip>> _parseYaml(String yamlStr) {
    final String trimmed = yamlStr.trim();
    if (trimmed.isEmpty) return {};
    final y = loadYaml(trimmed);
    if (y is! YamlMap) return {};

    final out = <String, Map<String, ShootEquip>>{};
    for (final e in y.entries) {
      final String shootName = e.key?.toString() ?? '';
      if (shootName.isEmpty) continue;
      final val = e.value;
      if (val is! YamlMap) {
        out[shootName] = {};
        continue;
      }
      final items = <String, ShootEquip>{};
      for (final ie in val.entries) {
        final String equipId = ie.key?.toString() ?? '';
        if (equipId.isEmpty) continue;

        // Handle both old format (bool) and new format (map with c/q/n).
        if (ie.value is bool) {
          items[equipId] = ShootEquip(checked: ie.value as bool, qty: 1);
        } else if (ie.value is YamlMap) {
          final m = ie.value as YamlMap;
          items[equipId] = ShootEquip(
            checked: m['c'] == true,
            qty: (m['q'] as int?) ?? 1,
            name: m['n'] as String?,
          );
        } else {
          items[equipId] = ShootEquip();
        }
      }
      out[shootName] = items;
    }
    return out;
  }

  // ── Write: full replace ─────────────────────────────────────────

  /// Write the entire shoots map to the gist. Returns the parsed
  /// ground-truth from the PATCH response.
  Future<Map<String, Map<String, ShootEquip>>> writeAll(
    Map<String, Map<String, ShootEquip>> shoots, {
    required String token,
  }) async {
    final String yaml = _shootsToYaml(shoots);
    final patchUri = Uri.parse('https://api.github.com/gists/${admin.gistId}');
    final body = jsonEncode({
      'files': {
        admin.shootsFile: {'content': yaml.isEmpty ? ' ' : yaml},
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
        'shoots write failed: ${patchResp.statusCode} ${patchResp.body}',
      );
    }

    try {
      final respJson = jsonDecode(patchResp.body) as Map<String, dynamic>;
      final files = respJson['files'] as Map<String, dynamic>?;
      final f = files?[admin.shootsFile] as Map<String, dynamic>?;
      final content = f?['content'] as String?;
      if (content != null) return _parseYaml(content);
    } catch (e) {
      debugPrint('shoots patch response parse failed: $e');
    }

    return shoots;
  }

  /// Read via authenticated API (fresh, no CDN lag).
  Future<Map<String, Map<String, ShootEquip>>> readViaApi(String token) async {
    final String id = admin.gistId.trim();
    final String file = admin.shootsFile.trim();
    if (id.isEmpty) throw Exception('gistId missing in admin config');

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
      throw Exception('shoots read failed: ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final files = body['files'] as Map<String, dynamic>?;
    final f = files?[file] as Map<String, dynamic>?;
    final content = f?['content'] as String?;
    if (content == null) return {};
    return _parseYaml(content);
  }

  /// Poll via authenticated API with conditional request (ETag).
  /// Returns `null` when the data hasn't changed (HTTP 304), which
  /// does NOT count against GitHub's rate limit. Otherwise returns
  /// the fresh data together with the new ETag for the next poll.
  Future<({Map<String, Map<String, ShootEquip>> data, String etag})?>
      pollViaApi(String token, {String? etag}) async {
    final String id = admin.gistId.trim();
    final String file = admin.shootsFile.trim();
    if (id.isEmpty) throw Exception('gistId missing in admin config');

    final uri = Uri.parse('https://api.github.com/gists/$id');
    final headers = <String, String>{
      'Authorization': 'token $token',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    if (etag != null) headers['If-None-Match'] = etag;

    final resp = await http.get(uri, headers: headers);

    // 304 Not Modified — data unchanged, doesn't consume rate limit.
    if (resp.statusCode == 304) return null;

    if (resp.statusCode ~/ 100 != 2) {
      throw Exception('shoots poll failed: ${resp.statusCode}');
    }

    final newEtag = resp.headers['etag'] ?? '';
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final files = body['files'] as Map<String, dynamic>?;
    final f = files?[file] as Map<String, dynamic>?;
    final content = f?['content'] as String?;
    final data = content == null
        ? <String, Map<String, ShootEquip>>{}
        : _parseYaml(content);
    return (data: data, etag: newEtag);
  }

  // ── YAML serialize ──────────────────────────────────────────────

  String _shootsToYaml(Map<String, Map<String, ShootEquip>> shoots) {
    final names = shoots.keys.toList()..sort();
    final b = StringBuffer();
    for (final name in names) {
      b.writeln('${jsonEncode(name)}:');
      final items = shoots[name] ?? {};
      final ids = items.keys.toList()..sort();
      for (final id in ids) {
        final entry = items[id]!;
        b.writeln('  $id:');
        b.writeln('    c: ${entry.checked}');
        b.writeln('    q: ${entry.qty}');
        if (entry.name != null) {
          b.writeln('    n: ${jsonEncode(entry.name)}');
        }
      }
    }
    return b.toString();
  }
}
