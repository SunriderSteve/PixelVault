import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../models/admin_config_model.dart';

/// fetches inventory overlay from GitHub Gist
/// tries raw first with cache bust, then API fallback
class InventoryOverlayClient {
  final AdminConfigModel admin;

  const InventoryOverlayClient(this.admin);

  /// fetch overlay map id -> {quantity, cabinet}
  /// returns null if unavailable
  Future<Map<String, Map<String, dynamic>>?> fetch() async {
    final raw = await _tryRaw();
    if (raw != null) return raw;

    final api = await _tryApi();
    if (api != null) return api;

    return null;
  }

  /// attempt raw gist fetch without custom headers to avoid CORS preflight
  Future<Map<String, Map<String, dynamic>>?> _tryRaw() async {
    final rawUrl = admin.gistRawUrl.trim();
    if (rawUrl.isEmpty || !rawUrl.contains('gist.githubusercontent.com')) {
      return null;
    }

    try {
      final base = Uri.parse(rawUrl);
      final uri = base.replace(
        queryParameters: {
          ...base.queryParameters,
          't': DateTime.now().millisecondsSinceEpoch.toString(), // cache bust
        },
      );

      final resp = await http.get(
        uri,
      ); // keep request simple to avoid preflight
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

  /// fallback to GitHub API for public gists or when raw unavailable
  Future<Map<String, Map<String, dynamic>>?> _tryApi() async {
    final id = admin.gistId.trim();
    final file = admin.gistFile.trim();
    if (id.isEmpty) return null;

    try {
      final uri = Uri.parse('https://api.github.com/gists/$id');
      final resp = await http.get(uri); // minimal headers to avoid preflight
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

  /// parse overlay yaml into id -> {quantity, cabinet}
  Map<String, Map<String, dynamic>> _parseYaml(String yamlStr) {
    final trimmed = yamlStr.trim();
    if (trimmed.isEmpty) return {};
    final y = loadYaml(trimmed);
    if (y is! YamlMap) return {};

    final out = <String, Map<String, dynamic>>{};
    for (final e in y.entries) {
      final id = e.key?.toString() ?? '';
      final val = e.value;
      if (id.isEmpty || val is! YamlMap) continue;
      out[id] = {
        'quantity': (val['quantity'] as num?)?.toInt(),
        'cabinet': val['cabinet'] as String?,
      };
    }
    return out;
  }

  /// update one equipment entry in overlay gist
  /// pass only fields you want to change
  Future<void> updateEntry(
    String equipmentId, {
    int? quantity,
    String? cabinet,
    required String token, // GitHub PAT with gist scope
  }) async {
    if (quantity == null && cabinet == null) return; // nothing to change

    // read latest raw to avoid clobber
    final bust = DateTime.now().millisecondsSinceEpoch;
    final rawUri = Uri.parse('${admin.gistRawUrl}?t=$bust');
    final getResp = await http.get(rawUri);
    if (getResp.statusCode ~/ 100 != 2) {
      throw Exception('overlay read failed: ${getResp.statusCode}');
    }

    final current = _overlayYamlToMap(getResp.body);

    // merge minimal change
    final entry = Map<String, dynamic>.from(current[equipmentId] ?? const {});
    if (quantity != null) entry['quantity'] = quantity;
    if (cabinet != null) entry['cabinet'] = cabinet;
    current[equipmentId] = entry;

    // serialize back to YAML
    final updatedYaml = _overlayMapToYaml(current);

    // patch gist file
    final patchUri = Uri.parse('https://api.github.com/gists/${admin.gistId}');
    final body = jsonEncode({
      'files': {
        admin.gistFile: {'content': updatedYaml},
      },
    });

    final headers = {
      'Authorization': 'token $token', // PAT
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
  }

  /// parse overlay yaml to map id -> {quantity, cabinet}
  Map<String, Map<String, dynamic>> _overlayYamlToMap(String s) {
    final y = loadYaml(s);
    if (y is! YamlMap) return {};
    final out = <String, Map<String, dynamic>>{};
    for (final e in y.entries) {
      final id = e.key?.toString() ?? '';
      final val = e.value;
      if (id.isEmpty || val is! YamlMap) continue;
      out[id] = {
        'quantity': (val['quantity'] as num?)?.toInt(),
        'cabinet': val['cabinet'] as String?,
      };
    }
    return out;
  }

  /// write stable minimal yaml from overlay map
  String _overlayMapToYaml(Map<String, Map<String, dynamic>> m) {
    final ids = m.keys.toList()..sort();
    final b = StringBuffer();
    for (final id in ids) {
      final v = m[id] ?? const {};
      b.writeln('$id:');
      if (v['quantity'] != null) b.writeln('  quantity: ${v['quantity']}');
      if (v['cabinet'] != null) {
        b.writeln('  cabinet: ${jsonEncode(v['cabinet'])}');
      }
    }
    return b.toString();
  }
}
