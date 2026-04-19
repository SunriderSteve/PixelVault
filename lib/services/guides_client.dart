// PixelVault — Static guide YAML client.
//
// Fetches the bundled equipment, videography, and scenario guides from a
// GitHub Gist. Each category is stored as a multi-document YAML file
// (documents separated by `---`). This keeps guide content editable in
// the Gist without touching the app bundle.
//
// Read path mirrors the other Gist clients: raw CDN first, API fallback.
// There is no write path — guides are read-only from the app's perspective.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/admin_config_model.dart';

/// Fetches static guide YAML files from a GitHub Gist.
/// One instance is owned by [DataRepository].
class GuidesClient {
  final AdminConfigModel admin;

  const GuidesClient(this.admin);

  // ── Public API ──────────────────────────────────────────────────

  /// Fetch the raw YAML string for the equipment guides file.
  Future<String?> fetchEquipmentYaml() =>
      _fetchFile(admin.equipmentGuidesRawUrl, admin.equipmentGuidesFile);

  /// Fetch the raw YAML string for the videography guides file.
  Future<String?> fetchVideographyYaml() =>
      _fetchFile(admin.videographyGuidesRawUrl, admin.videographyGuidesFile);

  /// Fetch the raw YAML string for the scenario guides file.
  Future<String?> fetchScenarioYaml() =>
      _fetchFile(admin.scenarioGuidesRawUrl, admin.scenarioGuidesFile);

  // ── Internal: dual-path fetch ───────────────────────────────────

  /// Try the raw CDN first, fall back to the GitHub API.
  Future<String?> _fetchFile(String rawUrl, String fileName) async {
    final raw = await _tryRaw(rawUrl);
    if (raw != null) return raw;

    final api = await _tryApi(fileName);
    if (api != null) return api;

    return null;
  }

  /// Attempt a raw gist fetch without custom headers (avoids CORS
  /// preflight). Returns null on failure so the caller can fall back
  /// to the API path.
  Future<String?> _tryRaw(String rawUrl) async {
    final String url = rawUrl.trim();
    if (url.isEmpty || !url.contains('gist.githubusercontent.com')) {
      return null;
    }

    try {
      final base = Uri.parse(url);
      final uri = base.replace(
        queryParameters: {
          ...base.queryParameters,
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );

      final resp = await http.get(uri);
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        return resp.body;
      }
      debugPrint('guides raw non-OK ${resp.statusCode}: ${resp.reasonPhrase}');
      return null;
    } catch (e) {
      debugPrint('guides raw exception $e');
      return null;
    }
  }

  /// Fallback read via the GitHub API. Extracts the named file's
  /// content from the gist JSON response.
  Future<String?> _tryApi(String fileName) async {
    final String id = admin.gistId.trim();
    if (id.isEmpty || fileName.isEmpty) return null;

    try {
      final uri = Uri.parse('https://api.github.com/gists/$id');
      final resp = await http.get(uri);
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final files = body['files'] as Map<String, dynamic>?;
        final f = files?[fileName] as Map<String, dynamic>?;
        final content = f?['content'] as String?;
        if (content != null) return content;

        debugPrint('guides api file missing $fileName');
        return null;
      }
      debugPrint('guides api non-OK ${resp.statusCode}: ${resp.reasonPhrase}');
      return null;
    } catch (e) {
      debugPrint('guides api exception $e');
      return null;
    }
  }
}
