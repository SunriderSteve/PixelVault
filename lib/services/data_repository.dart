// PixelVault — Data repository (singleton).
//
// Owns the app's in-memory cache of YAML content (equipment,
// videography guides, scenarios) and production shoots, all fetched
// from the PixelVault-Data GitHub repository.
//
// Lifecycle:
//   1. The constructor kicks off [_init] and caches its Future.
//   2. Call-sites `await DataRepository().ensureInitialized()` before
//      reading data. `main.dart` does this at boot so the UI can
//      assume the caches are already populated.
//   3. After init, periodic Timers poll the repo so changes made by
//      another admin / session propagate automatically.
//
// Writes use an optimistic-update pattern:
//   • local state is updated first
//   • the PUT is issued to the repo (with SHA for concurrency)
//   • the response (ground truth) replaces local state
//
// Threading: this class is single-threaded Dart code, but the
// polling loop and the optimistic-write path both touch the same
// maps. Guards prevent overlapping fetches, and writes cancel the
// poll timer while in-flight so a stale response can't clobber
// the fresh local state.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

import '../models/admin_config_model.dart';
import '../models/equipment_model.dart';
import '../models/scenario_model.dart';
import '../models/videography_model.dart';
import 'github_repo_client.dart';
import 'guides_client.dart';
import 'production_shoots_client.dart';

class DataRepository {
  // ── Singleton wiring ────────────────────────────────────────────
  static final DataRepository _instance = DataRepository._internal();
  factory DataRepository() => _instance;
  DataRepository._internal() {
    _initFuture = _init();
  }

  // ── Lifecycle ───────────────────────────────────────────────────
  late final Future<void> _initFuture;

  /// Await this before reading data. Safe to call repeatedly.
  Future<void> ensureInitialized() => _initFuture;

  // ── In-memory stores ────────────────────────────────────────────
  final Map<String, Equipment> _equipment = {};
  final Map<String, VideographyGuide> _videography = {};
  final Map<String, ScenarioGuide> _scenarios = {};

  // ── Config + clients ────────────────────────────────────────────
  AdminConfigModel? _admin;
  GitHubRepoClient? _repoClient;
  GuidesClient? _guidesClient;
  ProductionShootsClient? _shootsClient;

  // ── Equipment write state ──────────────────────────────────────
  /// Tracks the SHA of the equipment file for write operations.
  String? _equipmentSha;

  // ── Production shoots ──────────────────────────────────────────
  Map<String, Map<String, ShootEquip>> _shoots = {};
  final ValueNotifier<int> shootsEpoch = ValueNotifier<int>(0);

  // ── Equipment change signal ─────────────────────────────────────
  /// Increments whenever equipment data changes. UI widgets that need
  /// to rebuild on equipment updates listen to this notifier.
  final ValueNotifier<int> overlayEpoch = ValueNotifier<int>(0);

  // ── Polling state ───────────────────────────────────────────────
  Timer? _equipmentTimer;
  bool _fetchingEquipment = false;
  String? _equipmentEtag;

  // ── Shoot write debounce ─────────────────────────────────────
  Timer? _shootsDebounce;
  final List<_ShootOp> _pendingShootOps = [];
  Map<String, Map<String, ShootEquip>>? _shootsSnapshot;
  bool _flushingShootOps = false;

  // ── Shoot polling state ──────────────────────────────────────
  Timer? _shootsTimer;
  bool _pollingShoots = false;
  String? _shootsEtag;

  // ══════════════════════════════════════════════════════════════
  // Init pipeline
  // ══════════════════════════════════════════════════════════════
  Future<void> _init() async {
    await _loadAdminConfig();

    if (_admin != null) {
      _repoClient = GitHubRepoClient(_admin!);
      _guidesClient = GuidesClient(_admin!, _repoClient!);
      _shootsClient = ProductionShootsClient(_admin!, _repoClient!);
    }

    await _loadGuidesFromRepo();
    await fetchShootsOnce();
    _startEquipmentPolling();
    _startShootsPolling();
  }

  // ══════════════════════════════════════════════════════════════
  // Admin config
  // ══════════════════════════════════════════════════════════════

  Future<void> _loadAdminConfig() async {
    try {
      final s = await rootBundle.loadString('data/admin_config.yaml');
      _admin = AdminConfigModel.fromYaml(s);
    } catch (e, st) {
      debugPrint('admin.yaml load failed: $e\n$st');
      _admin = null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // Guide content (fetched from repo)
  // ══════════════════════════════════════════════════════════════

  Future<void> _loadGuidesFromRepo() async {
    final client = _guidesClient;
    if (client == null) return;

    final results = await Future.wait([
      client.fetchEquipmentYaml(),
      client.fetchVideographyYaml(),
      client.fetchScenarioYaml(),
    ]);

    // Equipment.
    final equipYaml = results[0];
    if (equipYaml != null) {
      for (final doc in loadYamlStream(equipYaml)) {
        if (doc is! YamlMap) continue;
        final eq = Equipment.fromYaml(doc);
        _equipment[eq.id] = eq;
      }
    }

    // Videography guides.
    final videoYaml = results[1];
    if (videoYaml != null) {
      for (final doc in loadYamlStream(videoYaml)) {
        if (doc is! YamlMap) continue;
        final v = VideographyGuide.fromYaml(doc);
        _videography[v.id] = v;
      }
    }

    // Production scenarios.
    final scenarioYaml = results[2];
    if (scenarioYaml != null) {
      for (final doc in loadYamlStream(scenarioYaml)) {
        if (doc is! YamlMap) continue;
        final s = ScenarioGuide.fromYaml(doc);
        _scenarios[s.id] = s;
      }
    }
  }

  // ══════════════════════════════════════════════════════════════
  // Equipment polling
  // ══════════════════════════════════════════════════════════════

  /// Poll the equipment file for changes. Uses ETag-based conditional
  /// requests so 304 responses are free against the rate limit.
  Future<bool> fetchEquipmentOnce() async {
    if (_fetchingEquipment) return false;
    if (_repoClient == null) return false;

    _fetchingEquipment = true;
    try {
      final result = await _repoClient!.pollRaw(
        _admin!.equipmentFile,
        etag: _equipmentEtag,
      );
      if (result == null) return false; // 304 — no change.

      _equipmentEtag = result.etag;

      // Re-parse equipment from the fresh YAML.
      _equipment.clear();
      for (final doc in loadYamlStream(result.content)) {
        if (doc is! YamlMap) continue;
        final eq = Equipment.fromYaml(doc);
        _equipment[eq.id] = eq;
      }
      overlayEpoch.value++;
      return true;
    } catch (e, st) {
      debugPrint('equipment poll error: $e\n$st');
      return false;
    } finally {
      _fetchingEquipment = false;
    }
  }

  void _startEquipmentPolling() {
    _equipmentTimer?.cancel();
    final int secs = _admin?.pollSeconds ?? 5;
    if (secs <= 0 || _repoClient == null) return;

    _equipmentTimer = Timer.periodic(Duration(seconds: secs), (_) {
      fetchEquipmentOnce();
    });
  }

  // ══════════════════════════════════════════════════════════════
  // Production shoots: fetch + mutate
  // ══════════════════════════════════════════════════════════════

  Future<bool> fetchShootsOnce() async {
    if (_shootsClient == null) return false;
    try {
      final map = await _shootsClient!.fetch();
      if (map == null) return false;
      _shoots = map;
      shootsEpoch.value++;
      return true;
    } catch (e) {
      debugPrint('shoots fetch error: $e');
      return false;
    }
  }

  void _startShootsPolling() {
    _shootsTimer?.cancel();
    if (_shootsClient == null) return;

    _shootsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _pollShootsOnce();
    });
  }

  Future<void> _pollShootsOnce() async {
    if (_pollingShoots) return;
    if (_shootsClient == null) return;
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) return;

    _pollingShoots = true;
    try {
      final result = await _shootsClient!.pollViaApi(
        token,
        etag: _shootsEtag,
      );

      if (result == null) return; // 304.

      _shootsEtag = result.etag;

      if (_flushingShootOps || _pendingShootOps.isNotEmpty) return;

      _shoots = result.data;
      shootsEpoch.value++;
    } catch (e) {
      debugPrint('shoots poll error: $e');
    } finally {
      _pollingShoots = false;
    }
  }

  // ── Shoot debounce helpers ────────────────────────────────────

  void _scheduleShootFlush(_ShootOp op) {
    _shootsSnapshot ??= _deepCopyShoots(_shoots);
    _pendingShootOps.add(op);
    _shootsDebounce?.cancel();
    _shootsDebounce = Timer(
      const Duration(milliseconds: 1000),
      () => _executeShootFlush(),
    );
  }

  Future<void> _executeShootFlush() async {
    if (_flushingShootOps) return;
    _flushingShootOps = true;

    final ops = List<_ShootOp>.from(_pendingShootOps);
    final snapshot = _shootsSnapshot;
    _pendingShootOps.clear();
    _shootsSnapshot = null;

    final client = _shootsClient!;
    final String token = _admin?.accessToken ?? '';

    try {
      final fresh = await client.readViaApi(token);
      for (final op in ops) {
        op.apply(fresh);
      }
      final ground = await client.writeAll(fresh, token: token);
      _shoots = ground;
      _shootsEtag = null;
      if (_pendingShootOps.isNotEmpty) {
        _shootsSnapshot = _deepCopyShoots(_shoots);
        for (final pendingOp in _pendingShootOps) {
          pendingOp.apply(_shoots);
        }
      }
      shootsEpoch.value++;
    } catch (e) {
      if (snapshot != null) {
        _shoots = snapshot;
        for (final pendingOp in _pendingShootOps) {
          pendingOp.apply(_shoots);
        }
      }
      shootsEpoch.value++;
      debugPrint('shoots debounced flush error: $e');
    } finally {
      _flushingShootOps = false;
      if (_pendingShootOps.isNotEmpty) {
        _shootsDebounce?.cancel();
        _shootsDebounce = Timer(
          const Duration(milliseconds: 1000),
          () => _executeShootFlush(),
        );
      }
    }
  }

  Future<void> _flushPendingShootOps() async {
    _shootsDebounce?.cancel();
    if (_pendingShootOps.isEmpty) return;
    await _executeShootFlush();
  }

  static Map<String, Map<String, ShootEquip>> _deepCopyShoots(
    Map<String, Map<String, ShootEquip>> src,
  ) {
    return {
      for (final e in src.entries)
        e.key: {
          for (final ie in e.value.entries)
            ie.key: ShootEquip(
              checked: ie.value.checked,
              qty: ie.value.qty,
              name: ie.value.name,
            ),
        },
    };
  }

  Map<String, Map<String, ShootEquip>> getAllShoots() =>
      Map.unmodifiable(_shoots);

  Map<String, ShootEquip>? getShoot(String name) => _shoots[name];

  Future<void> createShoot(String name) async {
    final client = _shootsClient;
    if (client == null) throw StateError('shoots client not ready');
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) throw StateError('missing access token');

    await _flushPendingShootOps();

    _shoots[name] = {};
    shootsEpoch.value++;

    try {
      final fresh = await client.readViaApi(token);
      fresh[name] = {};
      final ground = await client.writeAll(fresh, token: token);
      _shoots = ground;
      shootsEpoch.value++;
    } catch (e) {
      _shoots.remove(name);
      shootsEpoch.value++;
      rethrow;
    }
  }

  Future<void> renameShoot(String oldName, String newName) async {
    final client = _shootsClient;
    if (client == null) throw StateError('shoots client not ready');
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) throw StateError('missing access token');

    await _flushPendingShootOps();

    final items = _shoots.remove(oldName);
    if (items == null) throw StateError('shoot "$oldName" not found');
    _shoots[newName] = items;
    shootsEpoch.value++;

    try {
      final fresh = await client.readViaApi(token);
      final freshItems = fresh.remove(oldName) ?? {};
      fresh[newName] = freshItems;
      final ground = await client.writeAll(fresh, token: token);
      _shoots = ground;
      shootsEpoch.value++;
    } catch (e) {
      _shoots.remove(newName);
      _shoots[oldName] = items;
      shootsEpoch.value++;
      rethrow;
    }
  }

  Future<void> deleteShoot(String name) async {
    final client = _shootsClient;
    if (client == null) throw StateError('shoots client not ready');
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) throw StateError('missing access token');

    await _flushPendingShootOps();

    final prev = _shoots.remove(name);
    shootsEpoch.value++;

    try {
      final fresh = await client.readViaApi(token);
      fresh.remove(name);
      final ground = await client.writeAll(fresh, token: token);
      _shoots = ground;
      shootsEpoch.value++;
    } catch (e) {
      if (prev != null) _shoots[name] = prev;
      shootsEpoch.value++;
      rethrow;
    }
  }

  Future<void> addEquipmentToShoot(
    String shootName,
    Map<String, int> equipQtys,
  ) async {
    if (_shootsClient == null) throw StateError('shoots client not ready');
    if ((_admin?.accessToken ?? '').isEmpty) {
      throw StateError('missing access token');
    }

    final items = _shoots[shootName] ?? {};
    for (final e in equipQtys.entries) {
      items[e.key] = ShootEquip(qty: e.value);
    }
    _shoots[shootName] = items;
    shootsEpoch.value++;

    _scheduleShootFlush(_AddEquipOp(shootName, Map.from(equipQtys)));
  }

  Future<void> toggleShootEquipCheck(
    String shootName,
    String equipId,
    bool checked,
  ) async {
    if (_shootsClient == null) throw StateError('shoots client not ready');
    if ((_admin?.accessToken ?? '').isEmpty) {
      throw StateError('missing access token');
    }

    final items = _shoots[shootName];
    if (items == null) return;
    final entry = items[equipId];
    if (entry == null) return;
    entry.checked = checked;
    shootsEpoch.value++;

    _scheduleShootFlush(_ToggleCheckOp(shootName, equipId, checked));
  }

  Future<void> updateShootEquipQty(
    String shootName,
    String equipId,
    int newQty,
  ) async {
    if (_shootsClient == null) throw StateError('shoots client not ready');
    if ((_admin?.accessToken ?? '').isEmpty) {
      throw StateError('missing access token');
    }

    final items = _shoots[shootName];
    if (items == null) return;
    final entry = items[equipId];
    if (entry == null) return;
    entry.qty = newQty;
    shootsEpoch.value++;

    _scheduleShootFlush(_UpdateQtyOp(shootName, equipId, newQty));
  }

  Future<String> addCustomEquipmentToShoot(
    String shootName,
    String customName,
    int qty,
  ) async {
    if (_shootsClient == null) throw StateError('shoots client not ready');
    if ((_admin?.accessToken ?? '').isEmpty) {
      throw StateError('missing access token');
    }

    final String id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final items = _shoots[shootName] ?? {};
    items[id] = ShootEquip(qty: qty, name: customName);
    _shoots[shootName] = items;
    shootsEpoch.value++;

    _scheduleShootFlush(_AddCustomEquipOp(shootName, id, customName, qty));
    return id;
  }

  Future<void> removeEquipmentFromShoot(
    String shootName,
    String equipId,
  ) async {
    if (_shootsClient == null) throw StateError('shoots client not ready');
    if ((_admin?.accessToken ?? '').isEmpty) {
      throw StateError('missing access token');
    }

    final items = _shoots[shootName];
    if (items == null) return;
    items.remove(equipId);
    shootsEpoch.value++;

    _scheduleShootFlush(_RemoveEquipOp(shootName, equipId));
  }

  // ══════════════════════════════════════════════════════════════
  // Public queries
  // ══════════════════════════════════════════════════════════════

  List<Equipment> getAllEquipment() => _equipment.values.toList();

  /// Inventory view: equipment that has a quantity defined.
  List<Equipment> getInventoryItems() {
    return _equipment.values.where((e) => e.quantity != null).toList();
  }

  Equipment? getEquipmentById(String id) => _equipment[id];

  List<VideographyGuide> getAllVideographyGuides() =>
      _videography.values.toList();
  VideographyGuide? getVideographyGuide(String id) => _videography[id];

  List<ScenarioGuide> getAllScenarios() => _scenarios.values.toList();
  ScenarioGuide? getScenario(String id) => _scenarios[id];

  String imageUrl(String path) => _admin?.rawUrl(path) ?? path;

  // ══════════════════════════════════════════════════════════════
  // Inventory changes (write to equipment.yaml via repo API)
  // ══════════════════════════════════════════════════════════════

  /// Write inventory changes for a single equipment id. Reads the
  /// current equipment.yaml via API (for fresh SHA), modifies the
  /// target document, and writes back.
  Future<void> applyInventoryChanges(
    String equipmentId, {
    int? quantity,
    String? storage,
  }) async {
    final client = _guidesClient;
    final repoClient = _repoClient;
    if (client == null || repoClient == null) {
      throw StateError('clients not ready');
    }
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) throw StateError('missing access token');

    // Snapshot for revert on failure.
    final prevEquipment = _equipment[equipmentId];

    // Optimistic local update.
    if (prevEquipment != null) {
      _equipment[equipmentId] = prevEquipment.copyWith(
        quantity: quantity,
        storage: storage,
      );
      overlayEpoch.value++;
    }

    // Cancel equipment polling during the write.
    _equipmentTimer?.cancel();

    try {
      // Read fresh equipment.yaml via API (gets content + SHA).
      final result = await client.readEquipmentViaApi(token);
      if (result == null) throw StateError('failed to read equipment.yaml');

      _equipmentSha = result.sha;
      final yamlContent = result.content;

      // Modify the target document in the multi-document YAML.
      final updatedYaml = _updateEquipmentDocument(
        yamlContent,
        equipmentId,
        quantity: quantity,
        storage: storage,
      );

      // Write back to repo.
      final newSha = await client.writeEquipmentYaml(
        updatedYaml,
        sha: _equipmentSha!,
        token: token,
        message: 'Update inventory for $equipmentId via PixelVault',
      );
      _equipmentSha = newSha;
      _equipmentEtag = null; // Invalidate so next poll fetches fresh.

      overlayEpoch.value++;
    } catch (e) {
      // Revert optimistic update on failure.
      if (prevEquipment != null) {
        _equipment[equipmentId] = prevEquipment;
      }
      overlayEpoch.value++;
      _startEquipmentPolling();
      rethrow;
    }

    _startEquipmentPolling();
  }

  // ══════════════════════════════════════════════════════════════
  // Equipment creation
  // ══════════════════════════════════════════════════════════════

  /// Create a new equipment entry in equipment.yaml with `no_guide: true`
  /// and the given inventory fields.
  Future<void> createEquipment({
    required String name,
    required String brand,
    required String category,
    required int quantity,
    String? storage,
  }) async {
    final client = _guidesClient;
    if (client == null) throw StateError('clients not ready');
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) throw StateError('missing access token');

    // Generate a slug-style ID from the name.
    final String id = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');

    if (_equipment.containsKey(id)) {
      throw StateError('Equipment with id "$id" already exists');
    }

    // Read current equipment.yaml via API for fresh SHA.
    final result = await client.readEquipmentViaApi(token);
    if (result == null) throw StateError('failed to read equipment.yaml');

    _equipmentSha = result.sha;

    // Build the new equipment YAML document.
    final newDoc = StringBuffer();
    newDoc.writeln('---');
    newDoc.writeln('id: $id');
    newDoc.writeln('name: ${_yamlQuote(name)}');
    newDoc.writeln('category: ${_yamlQuote(category)}');
    newDoc.writeln('brand: ${_yamlQuote(brand)}');
    newDoc.writeln('coverImages: []');
    newDoc.writeln('description: ""');
    newDoc.writeln('sections: []');
    newDoc.writeln('related: []');
    newDoc.writeln('quantity: $quantity');
    if (storage != null && storage.isNotEmpty) {
      newDoc.writeln('storage: ${_yamlQuote(storage)}');
    }
    newDoc.writeln('no_guide: true');

    final updatedYaml = result.content.trimRight().isEmpty
        ? newDoc.toString()
        : '${result.content.trimRight()}\n${newDoc.toString()}';

    // Write back.
    final newSha = await client.writeEquipmentYaml(
      updatedYaml,
      sha: _equipmentSha!,
      token: token,
      message: 'Create equipment "$name" via PixelVault',
    );
    _equipmentSha = newSha;
    _equipmentEtag = null;

    // Update local state.
    final eq = Equipment(
      id: id,
      name: name,
      category: category,
      brand: brand,
      coverImages: [],
      description: '',
      sections: [],
      related: [],
      storage: storage,
      quantity: quantity,
      noGuide: true,
    );
    _equipment[id] = eq;
    overlayEpoch.value++;
  }

  // ══════════════════════════════════════════════════════════════
  // YAML helpers
  // ══════════════════════════════════════════════════════════════

  /// Update a specific equipment document within the multi-document
  /// YAML string. Finds the document with the matching id and updates
  /// the quantity and/or storage fields.
  String _updateEquipmentDocument(
    String yamlContent,
    String equipmentId, {
    int? quantity,
    String? storage,
  }) {
    // Split on document separator, preserving the structure.
    final docs = yamlContent.split(RegExp(r'^---\s*$', multiLine: true));
    final result = StringBuffer();
    bool first = true;

    for (final doc in docs) {
      final trimmed = doc.trim();
      if (trimmed.isEmpty) continue;

      // Check if this document matches the target id.
      final parsed = loadYaml(trimmed);
      if (parsed is YamlMap && parsed['id'] == equipmentId) {
        // Rebuild the document with updated fields.
        var updated = trimmed;

        if (quantity != null) {
          if (RegExp(r'^quantity:.*$', multiLine: true).hasMatch(updated)) {
            updated = updated.replaceFirst(
              RegExp(r'^quantity:.*$', multiLine: true),
              'quantity: $quantity',
            );
          } else {
            updated = '$updated\nquantity: $quantity';
          }
        }

        if (storage != null) {
          if (RegExp(r'^storage:.*$', multiLine: true).hasMatch(updated)) {
            updated = updated.replaceFirst(
              RegExp(r'^storage:.*$', multiLine: true),
              'storage: ${_yamlQuote(storage)}',
            );
          } else {
            updated = '$updated\nstorage: ${_yamlQuote(storage)}';
          }
        }

        if (!first) result.write('---\n');
        result.writeln(updated);
      } else {
        if (!first) result.write('---\n');
        result.writeln(trimmed);
      }
      first = false;
    }

    return result.toString();
  }

  /// Quote a string value for YAML output.
  static String _yamlQuote(String v) {
    if (v.contains(RegExp(r'[:#\[\]{}&*!|>%@`]')) ||
        v.startsWith("'") ||
        v.startsWith('"') ||
        v.contains('\n')) {
      return '"${v.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
    }
    return v;
  }

  /// Manual equipment refresh.
  Future<void> forceRefreshOverlay() async => fetchEquipmentOnce();

  // ══════════════════════════════════════════════════════════════
  // Cleanup
  // ══════════════════════════════════════════════════════════════

  void dispose() {
    _equipmentTimer?.cancel();
    _equipmentTimer = null;
    _shootsTimer?.cancel();
    _shootsTimer = null;
    _shootsDebounce?.cancel();
    _shootsDebounce = null;
  }
}

// ══════════════════════════════════════════════════════════════════
// Shoot operations — replayed on fresh API data during flush
// ══════════════════════════════════════════════════════════════════

abstract class _ShootOp {
  void apply(Map<String, Map<String, ShootEquip>> shoots);
}

class _ToggleCheckOp extends _ShootOp {
  final String shootName;
  final String equipId;
  final bool checked;
  _ToggleCheckOp(this.shootName, this.equipId, this.checked);

  @override
  void apply(Map<String, Map<String, ShootEquip>> shoots) {
    shoots[shootName]?[equipId]?.checked = checked;
  }
}

class _UpdateQtyOp extends _ShootOp {
  final String shootName;
  final String equipId;
  final int qty;
  _UpdateQtyOp(this.shootName, this.equipId, this.qty);

  @override
  void apply(Map<String, Map<String, ShootEquip>> shoots) {
    shoots[shootName]?[equipId]?.qty = qty;
  }
}

class _AddEquipOp extends _ShootOp {
  final String shootName;
  final Map<String, int> equipQtys;
  _AddEquipOp(this.shootName, this.equipQtys);

  @override
  void apply(Map<String, Map<String, ShootEquip>> shoots) {
    final items = shoots[shootName] ?? {};
    for (final e in equipQtys.entries) {
      items[e.key] = ShootEquip(qty: e.value);
    }
    shoots[shootName] = items;
  }
}

class _AddCustomEquipOp extends _ShootOp {
  final String shootName;
  final String customId;
  final String customName;
  final int qty;
  _AddCustomEquipOp(this.shootName, this.customId, this.customName, this.qty);

  @override
  void apply(Map<String, Map<String, ShootEquip>> shoots) {
    final items = shoots[shootName] ?? {};
    items[customId] = ShootEquip(qty: qty, name: customName);
    shoots[shootName] = items;
  }
}

class _RemoveEquipOp extends _ShootOp {
  final String shootName;
  final String equipId;
  _RemoveEquipOp(this.shootName, this.equipId);

  @override
  void apply(Map<String, Map<String, ShootEquip>> shoots) {
    shoots[shootName]?.remove(equipId);
  }
}
