// PixelVault — Production shoots client (GitHub repo).
//
// Manages production shoot lists stored as a YAML file inside the
// PixelVault-Data GitHub repository. Each shoot is a named map of
// equipment IDs to their checked-off state and bring-quantity.
//
// YAML shape (data/production_shoots.yaml):
//
//     "My Shoot":
//       canon_c200:
//         c: false
//         q: 2
//       rode_ntg5:
//         c: true
//         q: 1

import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../models/admin_config_model.dart';
import 'github_repo_client.dart';

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

/// CRUD client for production shoot lists stored in a GitHub repo.
class ProductionShootsClient {
  final AdminConfigModel admin;
  final GitHubRepoClient repo;

  /// Tracks the SHA of the shoots file for write operations.
  String? _currentSha;

  ProductionShootsClient(this.admin, this.repo);

  // ── Public read API ─────────────────────────────────────────────

  /// Fetch all shoots via raw CDN (fast, can be stale).
  Future<Map<String, Map<String, ShootEquip>>?> fetch() async {
    final raw = await repo.readRaw(admin.shootsFile);
    if (raw != null) return _parseYaml(raw);
    // Fallback: API read.
    final token = admin.accessToken;
    if (token.isEmpty) return null;
    final result = await repo.readViaApi(admin.shootsFile, token);
    if (result != null) {
      _currentSha = result.sha;
      return _parseYaml(result.content);
    }
    return null;
  }

  /// Read via authenticated API (always fresh). Updates _currentSha.
  Future<Map<String, Map<String, ShootEquip>>> readViaApi(String token) async {
    final result = await repo.readViaApi(admin.shootsFile, token);
    if (result == null) return {};
    _currentSha = result.sha;
    return _parseYaml(result.content);
  }

  /// Poll via the API with ETag support. Returns null on 304.
  Future<({Map<String, Map<String, ShootEquip>> data, String etag})?>
      pollViaApi(String token, {String? etag}) async {
    final result = await repo.pollViaApi(
      admin.shootsFile,
      token,
      etag: etag,
    );
    if (result == null) return null;
    return (data: _parseYaml(result.content), etag: result.etag ?? '');
  }

  // ── Write ───────────────────────────────────────────────────────

  /// Write the entire shoots map to the repo. Returns the parsed
  /// ground-truth after the commit.
  Future<Map<String, Map<String, ShootEquip>>> writeAll(
    Map<String, Map<String, ShootEquip>> shoots, {
    required String token,
  }) async {
    // Ensure we have the current SHA.
    if (_currentSha == null) {
      final result = await repo.readViaApi(admin.shootsFile, token);
      _currentSha = result?.sha ?? '';
    }

    final yaml = _shootsToYaml(shoots);
    final newSha = await repo.writeFile(
      admin.shootsFile,
      yaml.isEmpty ? ' ' : yaml,
      sha: _currentSha!,
      token: token,
      message: 'Update production shoots via PixelVault',
    );
    _currentSha = newSha;

    // Re-read to get ground truth.
    final fresh = await repo.readViaApi(admin.shootsFile, token);
    if (fresh != null) {
      _currentSha = fresh.sha;
      return _parseYaml(fresh.content);
    }
    return shoots;
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
