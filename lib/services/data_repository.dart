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
import '../pages/guide_creator_page.dart' show GuideType;
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

  // ── YAML file write state ──────────────────────────────────────
  // Only equipment still uses per-file SHA (for applyInventoryChanges,
  // which is a single-file write). Guide create/update use the Git
  // Data API (batch commits) and don't need per-file SHAs.
  String? _equipmentSha;

  // ── Production shoots ──────────────────────────────────────────
  Map<String, Map<String, ShootEquip>> _shoots = {};
  final ValueNotifier<int> shootsEpoch = ValueNotifier<int>(0);

  // ── Equipment change signal ─────────────────────────────────────
  /// Increments whenever equipment data changes. UI widgets that need
  /// to rebuild on equipment updates listen to this notifier.
  final ValueNotifier<int> overlayEpoch = ValueNotifier<int>(0);

  /// Increments whenever videography or scenario guide data changes.
  final ValueNotifier<int> guidesEpoch = ValueNotifier<int>(0);

  // ── Polling state ───────────────────────────────────────────────
  Timer? _equipmentTimer;
  bool _fetchingEquipment = false;
  String? _equipmentEtag;
  // Monotonic counter: incremented every time an equipment write completes.
  // A poll captures this at start; if it changes before the response is
  // applied, the poll result is discarded (the in-flight response could
  // reflect pre-write state and would cause a visible revert).
  int _equipmentWriteEpoch = 0;

  // ── Shoot write debounce ─────────────────────────────────────
  Timer? _shootsDebounce;
  final List<_ShootOp> _pendingShootOps = [];
  Map<String, Map<String, ShootEquip>>? _shootsSnapshot;
  bool _flushingShootOps = false;

  // ── Shoot polling state ──────────────────────────────────────
  Timer? _shootsTimer;
  bool _pollingShoots = false;
  String? _shootsEtag;
  // Same purpose as [_equipmentWriteEpoch] — guards the shoots poll
  // against stale responses that were issued before a write completed.
  int _shootsWriteEpoch = 0;

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

  /// Poll the equipment file for changes via the authenticated Contents
  /// API (immediately consistent — unlike the raw CDN, which can serve
  /// stale content for minutes after a write and was the root cause of
  /// the inventory "permanent revert" bug). Uses ETag-based conditional
  /// requests so 304 responses are free against the rate limit.
  Future<bool> fetchEquipmentOnce() async {
    if (_fetchingEquipment) return false;
    if (_repoClient == null) return false;
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) return false;

    final int startEpoch = _equipmentWriteEpoch;
    _fetchingEquipment = true;
    try {
      final result = await _repoClient!.pollViaApi(
        _admin!.equipmentFile,
        token,
        etag: _equipmentEtag,
      );
      if (result == null) return false; // 304 — no change.

      // A write completed while this request was in flight. The response
      // may reflect the pre-write state; discarding it prevents a brief
      // revert. A subsequent poll will pick up the post-write state.
      if (_equipmentWriteEpoch != startEpoch) return false;

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

    final int startEpoch = _shootsWriteEpoch;
    _pollingShoots = true;
    try {
      final result = await _shootsClient!.pollViaApi(
        token,
        etag: _shootsEtag,
      );

      if (result == null) return; // 304.

      // A write completed while this poll was in flight — its response
      // could reflect pre-write state (causing a brief UI revert). Drop
      // it; the next poll picks up the true post-write state.
      if (_shootsWriteEpoch != startEpoch) return;

      if (_flushingShootOps || _pendingShootOps.isNotEmpty) return;

      _shootsEtag = result.etag;
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
    _shootsWriteEpoch++;

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
      // Keep the existing ETag: ground truth already matches _shoots,
      // and clearing it would force a raw re-fetch that could briefly
      // return stale content and cause a visible revert.
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

    _shootsWriteEpoch++;
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

    _shootsWriteEpoch++;
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

    _shootsWriteEpoch++;
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

    // Cancel equipment polling during the write, and bump the write epoch
    // so any in-flight poll's response is discarded (prevents revert).
    _equipmentTimer?.cancel();
    _equipmentWriteEpoch++;

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
      // Keep the existing ETag: the optimistic local update already
      // reflects the new state. Clearing it would force the next poll
      // to fetch from the raw CDN, which may still serve the pre-write
      // content for up to a few minutes and cause a visible revert.

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
  /// and the given inventory fields. When [coverImage] is supplied, the
  /// image blob and the YAML update are persisted in a single atomic
  /// commit via the Git Data API.
  Future<void> createEquipment({
    required String name,
    required String brand,
    required String category,
    required int quantity,
    String? storage,
    ({Uint8List bytes, String repoPath})? coverImage,
  }) async {
    final client = _guidesClient;
    final repoClient = _repoClient;
    if (client == null || repoClient == null) {
      throw StateError('clients not ready');
    }
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) throw StateError('missing access token');

    // Generate a slug-style ID from the name.
    final String id = generateId(name);

    if (_equipment.containsKey(id)) {
      throw StateError('Equipment with id "$id" already exists');
    }

    _equipmentTimer?.cancel();
    _equipmentWriteEpoch++;

    try {
      // Read current equipment.yaml via API for fresh SHA.
      final result = await client.readEquipmentViaApi(token);
      if (result == null) throw StateError('failed to read equipment.yaml');

      _equipmentSha = result.sha;

      // Build the new equipment YAML document.
      final coverPaths = coverImage != null ? [coverImage.repoPath] : <String>[];
      final newDoc = StringBuffer();
      newDoc.writeln('id: $id');
      newDoc.writeln('name: ${_yamlQuote(name)}');
      newDoc.writeln('category: ${_yamlQuote(category)}');
      newDoc.writeln('brand: ${_yamlQuote(brand)}');
      if (coverPaths.isEmpty) {
        newDoc.writeln('coverImages: []');
      } else {
        newDoc.writeln('coverImages:');
        for (final p in coverPaths) {
          newDoc.writeln('  - $p');
        }
      }
      newDoc.writeln('description: ""');
      newDoc.writeln('sections: []');
      newDoc.writeln('related: []');
      newDoc.writeln('quantity: $quantity');
      if (storage != null && storage.isNotEmpty) {
        newDoc.writeln('storage: ${_yamlQuote(storage)}');
      }
      newDoc.writeln('no_guide: true');

      final updatedYaml = _appendDocument(result.content, newDoc.toString());

      if (coverImage != null) {
        // Atomic commit: image blob + YAML update.
        await repoClient.commitBatch(
          [
            BatchFileChange.writeBinary(
              path: coverImage.repoPath,
              bytes: coverImage.bytes,
            ),
            BatchFileChange.write(
              path: _admin!.equipmentFile,
              content: updatedYaml,
            ),
          ],
          token: token,
          message: 'Create equipment "$name" via PixelVault',
        );
        // commitBatch rewrites the file via the Git Data API, so our
        // cached equipment.yaml SHA is now stale. Clear it so the next
        // write re-reads a fresh one.
        _equipmentSha = null;
      } else {
        final newSha = await client.writeEquipmentYaml(
          updatedYaml,
          sha: _equipmentSha!,
          token: token,
          message: 'Create equipment "$name" via PixelVault',
        );
        _equipmentSha = newSha;
      }

      // Update local state.
      final eq = Equipment(
        id: id,
        name: name,
        category: category,
        brand: brand,
        coverImages: coverPaths,
        description: '',
        sections: [],
        related: [],
        storage: storage,
        quantity: quantity,
        noGuide: true,
      );
      _equipment[id] = eq;
      overlayEpoch.value++;
    } finally {
      _startEquipmentPolling();
    }
  }

  /// Delete an equipment item entirely: removes its document from
  /// equipment.yaml AND deletes every image it referenced (cover +
  /// section images). Atomic via a single Git commit.
  Future<void> deleteEquipment(String id) async {
    final client = _guidesClient;
    final repoClient = _repoClient;
    if (client == null || repoClient == null) {
      throw StateError('clients not ready');
    }
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) throw StateError('missing access token');

    final eq = _equipment[id];
    if (eq == null) throw StateError('equipment "$id" not found');

    _equipmentTimer?.cancel();
    _equipmentWriteEpoch++;

    try {
      final result = await client.readEquipmentViaApi(token);
      if (result == null) throw StateError('failed to read equipment.yaml');

      final updatedYaml = _removeDocumentById(result.content, id);

      // Collect image paths from local model (guide images included).
      final imagePaths = <String>{
        ...eq.coverImages,
        for (final sec in eq.sections) ...sec.images,
      };

      final changes = <BatchFileChange>[
        BatchFileChange.write(
          path: _admin!.equipmentFile,
          content: updatedYaml,
        ),
        for (final p in imagePaths) BatchFileChange.delete(path: p),
      ];

      await repoClient.commitBatch(
        changes,
        token: token,
        message: 'Delete equipment "${eq.name}" via PixelVault',
      );
      _equipmentSha = null;

      _equipment.remove(id);
      overlayEpoch.value++;
    } finally {
      _startEquipmentPolling();
    }
  }

  /// Replace the cover image on an existing equipment item. Deletes any
  /// previous cover images, uploads the new one, and rewrites the YAML
  /// entry — all in a single atomic commit.
  Future<void> replaceEquipmentCoverImage(
    String id, {
    required Uint8List bytes,
    required String repoPath,
  }) async {
    final client = _guidesClient;
    final repoClient = _repoClient;
    if (client == null || repoClient == null) {
      throw StateError('clients not ready');
    }
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) throw StateError('missing access token');

    final eq = _equipment[id];
    if (eq == null) throw StateError('equipment "$id" not found');

    _equipmentTimer?.cancel();
    _equipmentWriteEpoch++;

    try {
      final result = await client.readEquipmentViaApi(token);
      if (result == null) throw StateError('failed to read equipment.yaml');

      final updatedYaml = _replaceCoverImagesInDoc(
        result.content,
        id,
        [repoPath],
      );

      final oldCovers = eq.coverImages.where((p) => p != repoPath).toList();

      final changes = <BatchFileChange>[
        for (final p in oldCovers) BatchFileChange.delete(path: p),
        BatchFileChange.writeBinary(path: repoPath, bytes: bytes),
        BatchFileChange.write(
          path: _admin!.equipmentFile,
          content: updatedYaml,
        ),
      ];

      await repoClient.commitBatch(
        changes,
        token: token,
        message: 'Update cover image for "${eq.name}" via PixelVault',
      );
      _equipmentSha = null;

      _equipment[id] = Equipment(
        id: eq.id,
        name: eq.name,
        category: eq.category,
        brand: eq.brand,
        coverImages: [repoPath],
        description: eq.description,
        sections: eq.sections,
        related: eq.related,
        storage: eq.storage,
        quantity: eq.quantity,
        noGuide: eq.noGuide,
      );
      overlayEpoch.value++;
    } finally {
      _startEquipmentPolling();
    }
  }

  // ══════════════════════════════════════════════════════════════
  // Guide CRUD (create / update for all guide types)
  // ══════════════════════════════════════════════════════════════

  /// Generate a slug-style ID from a display name.
  static String generateId(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
  }

  /// Image type subfolder for a guide type.
  static String _imageFolder(GuideType type) {
    switch (type) {
      case GuideType.equipment:
        return 'equipment';
      case GuideType.videography:
        return 'videography';
      case GuideType.scenario:
        return 'scenarios';
    }
  }

  /// Build a repo path for a cover image.
  static String coverImagePath(
          GuideType type, String id, int index, String ext) =>
      'images/${_imageFolder(type)}/${id}_cover_${index + 1}.$ext';

  /// Build a repo path for a section image.
  static String sectionImagePath(
          GuideType type, String id, int sectionIdx, int imgIdx, String ext) =>
      'images/${_imageFolder(type)}/${id}_section${sectionIdx + 1}_${imgIdx + 1}.$ext';

  /// Upload a binary image file to the repo. Returns the new SHA.
  /// If the file already exists (e.g. retry after partial failure),
  /// fetches the current SHA so the update succeeds.
  Future<String> uploadImage(Uint8List bytes, String repoPath) async {
    final repoClient = _repoClient;
    if (repoClient == null) throw StateError('repo client not ready');
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) throw StateError('missing access token');

    // Check if the file already exists (handles retries / duplicates).
    final existingSha = await repoClient.getFileSha(repoPath, token) ?? '';

    return repoClient.writeBinaryFile(
      repoPath,
      bytes,
      sha: existingSha,
      token: token,
      message: 'Upload image $repoPath via PixelVault',
    );
  }

  /// Delete an image file from the repo.
  Future<void> deleteImage(String repoPath) async {
    final repoClient = _repoClient;
    if (repoClient == null) throw StateError('repo client not ready');
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) throw StateError('missing access token');

    final sha = await repoClient.getFileSha(repoPath, token);
    if (sha == null) return; // file doesn't exist
    await repoClient.deleteFile(
      repoPath,
      sha: sha,
      token: token,
      message: 'Delete image $repoPath via PixelVault',
    );
  }

  /// Create a new guide and persist it to the repo in a single atomic
  /// commit (YAML + all images bundled together via the Git Data API).
  ///
  /// [coverImages] and [sections] carry the already-converted image
  /// bytes alongside their target repo paths. Asset-only entries
  /// (pre-existing images kept during edit) have null bytes.
  Future<void> createGuide({
    required GuideType type,
    required String id,
    required String name,
    String brand = '',
    String category = '',
    String description = '',
    required List<({Uint8List? bytes, String repoPath})> coverImages,
    required List<
            ({
              String title,
              String body,
              List<({Uint8List? bytes, String repoPath})> images,
            })>
        sections,
    List<String> related = const [],
    int? quantity,
    String? storage,
    String? existingEquipId,
  }) async {
    final client = _guidesClient;
    final repoClient = _repoClient;
    if (client == null || repoClient == null) {
      throw StateError('clients not ready');
    }
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) throw StateError('missing access token');

    // 1. Build YAML document.
    final coverPaths = coverImages.map((e) => e.repoPath).toList();
    final sectionData = sections
        .map((s) => (
              title: s.title,
              body: s.body,
              images: s.images.map((i) => i.repoPath).toList(),
            ))
        .toList();

    final yamlDoc = _buildGuideYaml(
      type: type,
      id: id,
      name: name,
      brand: brand,
      category: category,
      description: description,
      coverImages: coverPaths,
      sections: sectionData,
      related: related,
      quantity: quantity,
      storage: storage,
    );

    // 2. Gather batched changes: image uploads (deduped) + YAML update.
    final changes = <BatchFileChange>[];
    final seenPaths = <String>{};

    void addImageChange(({Uint8List? bytes, String repoPath}) img) {
      if (img.bytes == null) return;
      if (!seenPaths.add(img.repoPath)) return;
      changes.add(BatchFileChange.writeBinary(
        path: img.repoPath,
        bytes: img.bytes!,
      ));
    }

    for (final img in coverImages) {
      addImageChange(img);
    }
    for (final sec in sections) {
      for (final img in sec.images) {
        addImageChange(img);
      }
    }

    _equipmentTimer?.cancel();
    if (type == GuideType.equipment) _equipmentWriteEpoch++;

    try {
      // Read current YAML so we can append/replace the document.
      final (String yamlPath, String newContent, String commitMessage)
          = await switch (type) {
        GuideType.equipment => (() async {
            final result = await client.readEquipmentViaApi(token);
            if (result == null) {
              throw StateError('failed to read equipment.yaml');
            }
            _equipmentSha = result.sha;
            String content = result.content;
            // If replacing an existing no_guide entry, remove it first.
            if (existingEquipId != null) {
              content = _removeDocumentById(content, existingEquipId);
            }
            content = _appendDocument(content, yamlDoc);
            return (
              _admin!.equipmentFile,
              content,
              'Create equipment guide "$name" via PixelVault',
            );
          })(),
        GuideType.videography => (() async {
            final result = await client.readVideographyViaApi(token);
            if (result == null) {
              throw StateError('failed to read videography.yaml');
            }
            return (
              _admin!.videographyFile,
              _appendDocument(result.content, yamlDoc),
              'Create videography guide "$name" via PixelVault',
            );
          })(),
        GuideType.scenario => (() async {
            final result = await client.readScenarioViaApi(token);
            if (result == null) {
              throw StateError('failed to read scenarios.yaml');
            }
            return (
              _admin!.scenarioFile,
              _appendDocument(result.content, yamlDoc),
              'Create scenario guide "$name" via PixelVault',
            );
          })(),
      };

      changes.add(BatchFileChange.write(path: yamlPath, content: newContent));

      // 3. Atomic commit.
      await repoClient.commitBatch(
        changes,
        token: token,
        message: commitMessage,
      );

      // 4. Update local cache.
      switch (type) {
        case GuideType.equipment:
          _equipment[id] = Equipment(
            id: id,
            name: name,
            category: category,
            brand: brand,
            coverImages: coverPaths,
            description: description,
            sections: sectionData
                .map((s) => EquipSection(
                    title: s.title, images: s.images, body: s.body))
                .toList(),
            related: related,
            storage: storage,
            quantity: quantity,
          );
          overlayEpoch.value++;

        case GuideType.videography:
          _videography[id] = VideographyGuide(
            id: id,
            name: name,
            coverImages: coverPaths,
            sections: sectionData
                .map((s) => GuideSection(
                    title: s.title, images: s.images, body: s.body))
                .toList(),
          );
          guidesEpoch.value++;

        case GuideType.scenario:
          _scenarios[id] = ScenarioGuide(
            id: id,
            name: name,
            description: description,
            coverImages: coverPaths,
            sections: sectionData
                .map((s) => ScenarioSection(
                    title: s.title, images: s.images, body: s.body))
                .toList(),
            related: related,
          );
          guidesEpoch.value++;
      }
    } finally {
      _startEquipmentPolling();
    }
  }

  /// Update an existing guide. Handles image diffing (delete removed,
  /// upload new) and replaces the YAML document — all in a single
  /// atomic commit.
  Future<void> updateGuide({
    required GuideType type,
    required String id,
    required String name,
    String brand = '',
    String category = '',
    String description = '',
    required List<({Uint8List? bytes, String repoPath})> coverImages,
    required List<
            ({
              String title,
              String body,
              List<({Uint8List? bytes, String repoPath})> images,
            })>
        sections,
    List<String> related = const [],
    List<String> removedImagePaths = const [],
  }) async {
    final client = _guidesClient;
    final repoClient = _repoClient;
    if (client == null || repoClient == null) {
      throw StateError('clients not ready');
    }
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) throw StateError('missing access token');

    // 1. Build updated YAML document.
    final coverPaths = coverImages.map((e) => e.repoPath).toList();
    final sectionData = sections
        .map((s) => (
              title: s.title,
              body: s.body,
              images: s.images.map((i) => i.repoPath).toList(),
            ))
        .toList();

    // 2. Gather batched changes: image deletes + uploads (deduped) +
    //    the YAML rewrite.
    final changes = <BatchFileChange>[];
    final seenPaths = <String>{};

    for (final path in removedImagePaths) {
      // A path that's being re-uploaded with new bytes isn't a true
      // delete — skip here so the blob write below wins.
      changes.add(BatchFileChange.delete(path: path));
    }

    void addImageChange(({Uint8List? bytes, String repoPath}) img) {
      if (img.bytes == null) return;
      if (!seenPaths.add(img.repoPath)) return;
      changes.add(BatchFileChange.writeBinary(
        path: img.repoPath,
        bytes: img.bytes!,
      ));
    }

    for (final img in coverImages) {
      addImageChange(img);
    }
    for (final sec in sections) {
      for (final img in sec.images) {
        addImageChange(img);
      }
    }

    _equipmentTimer?.cancel();
    if (type == GuideType.equipment) _equipmentWriteEpoch++;

    try {
      final (String yamlPath, String newContent, String commitMessage)
          = await switch (type) {
        GuideType.equipment => (() async {
            final result = await client.readEquipmentViaApi(token);
            if (result == null) {
              throw StateError('failed to read equipment.yaml');
            }
            _equipmentSha = result.sha;

            // Preserve quantity/storage from the existing document.
            final existing = _equipment[id];
            final fullDoc = _buildGuideYaml(
              type: type,
              id: id,
              name: name,
              brand: brand,
              category: category,
              description: description,
              coverImages: coverPaths,
              sections: sectionData,
              related: related,
              quantity: existing?.quantity,
              storage: existing?.storage,
            );

            var content = _removeDocumentById(result.content, id);
            content = _appendDocument(content, fullDoc);
            return (
              _admin!.equipmentFile,
              content,
              'Update equipment guide "$name" via PixelVault',
            );
          })(),
        GuideType.videography => (() async {
            final result = await client.readVideographyViaApi(token);
            if (result == null) {
              throw StateError('failed to read videography.yaml');
            }

            final yamlDoc = _buildGuideYaml(
              type: type,
              id: id,
              name: name,
              brand: brand,
              category: category,
              description: description,
              coverImages: coverPaths,
              sections: sectionData,
              related: related,
            );
            var content = _removeDocumentById(result.content, id);
            content = _appendDocument(content, yamlDoc);
            return (
              _admin!.videographyFile,
              content,
              'Update videography guide "$name" via PixelVault',
            );
          })(),
        GuideType.scenario => (() async {
            final result = await client.readScenarioViaApi(token);
            if (result == null) {
              throw StateError('failed to read scenarios.yaml');
            }

            final yamlDoc = _buildGuideYaml(
              type: type,
              id: id,
              name: name,
              brand: brand,
              category: category,
              description: description,
              coverImages: coverPaths,
              sections: sectionData,
              related: related,
            );
            var content = _removeDocumentById(result.content, id);
            content = _appendDocument(content, yamlDoc);
            return (
              _admin!.scenarioFile,
              content,
              'Update scenario guide "$name" via PixelVault',
            );
          })(),
      };

      changes.add(BatchFileChange.write(path: yamlPath, content: newContent));

      // 3. Atomic commit.
      await repoClient.commitBatch(
        changes,
        token: token,
        message: commitMessage,
      );

      // 4. Update local cache.
      switch (type) {
        case GuideType.equipment:
          final existing = _equipment[id];
          _equipment[id] = Equipment(
            id: id,
            name: name,
            category: category,
            brand: brand,
            coverImages: coverPaths,
            description: description,
            sections: sectionData
                .map((s) => EquipSection(
                    title: s.title, images: s.images, body: s.body))
                .toList(),
            related: related,
            storage: existing?.storage,
            quantity: existing?.quantity,
          );
          overlayEpoch.value++;

        case GuideType.videography:
          _videography[id] = VideographyGuide(
            id: id,
            name: name,
            coverImages: coverPaths,
            sections: sectionData
                .map((s) => GuideSection(
                    title: s.title, images: s.images, body: s.body))
                .toList(),
          );
          guidesEpoch.value++;

        case GuideType.scenario:
          _scenarios[id] = ScenarioGuide(
            id: id,
            name: name,
            description: description,
            coverImages: coverPaths,
            sections: sectionData
                .map((s) => ScenarioSection(
                    title: s.title, images: s.images, body: s.body))
                .toList(),
            related: related,
          );
          guidesEpoch.value++;
      }
    } finally {
      _startEquipmentPolling();
    }
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

  /// Remove a document with the given id from a multi-document YAML.
  String _removeDocumentById(String yamlContent, String id) {
    final docs = yamlContent.split(RegExp(r'^---\s*$', multiLine: true));
    final result = StringBuffer();
    bool first = true;

    for (final doc in docs) {
      final trimmed = doc.trim();
      if (trimmed.isEmpty) continue;

      final parsed = loadYaml(trimmed);
      if (parsed is YamlMap && parsed['id'] == id) continue; // skip

      if (!first) result.write('---\n');
      result.writeln(trimmed);
      first = false;
    }
    return result.toString();
  }

  /// Replace the `coverImages:` block inside a specific document (by id)
  /// within a multi-document YAML string. Preserves every other field.
  String _replaceCoverImagesInDoc(
    String yamlContent,
    String equipmentId,
    List<String> newPaths,
  ) {
    final docs = yamlContent.split(RegExp(r'^---\s*$', multiLine: true));
    final result = StringBuffer();
    bool first = true;

    for (final doc in docs) {
      final trimmed = doc.trim();
      if (trimmed.isEmpty) continue;

      final parsed = loadYaml(trimmed);
      if (parsed is YamlMap && parsed['id'] == equipmentId) {
        // Rewrite the coverImages block line-by-line so unrelated fields
        // stay untouched (block scalars, indentation, etc.).
        final lines = trimmed.split('\n');
        final out = <String>[];
        int i = 0;
        while (i < lines.length) {
          final line = lines[i];
          if (RegExp(r'^coverImages:').hasMatch(line)) {
            if (newPaths.isEmpty) {
              out.add('coverImages: []');
            } else {
              out.add('coverImages:');
              for (final p in newPaths) {
                out.add('  - $p');
              }
            }
            i++;
            // Skip any existing indented list items from the old block.
            while (i < lines.length && RegExp(r'^\s+-').hasMatch(lines[i])) {
              i++;
            }
            continue;
          }
          out.add(line);
          i++;
        }
        if (!first) result.write('---\n');
        result.writeln(out.join('\n'));
      } else {
        if (!first) result.write('---\n');
        result.writeln(trimmed);
      }
      first = false;
    }
    return result.toString();
  }

  /// Append a new YAML document to a multi-document YAML string.
  String _appendDocument(String yamlContent, String newDocument) {
    final trimmed = yamlContent.trimRight();
    if (trimmed.isEmpty) return newDocument;
    return '$trimmed\n---\n$newDocument';
  }

  /// Serialize guide data into a YAML document string.
  String _buildGuideYaml({
    required GuideType type,
    required String id,
    required String name,
    String brand = '',
    String category = '',
    String description = '',
    required List<String> coverImages,
    required List<({String title, String body, List<String> images})> sections,
    List<String> related = const [],
    int? quantity,
    String? storage,
  }) {
    final buf = StringBuffer();
    buf.writeln('id: $id');
    buf.writeln('name: ${_yamlQuote(name)}');

    if (type == GuideType.equipment) {
      buf.writeln('brand: ${_yamlQuote(brand)}');
      buf.writeln('category: ${_yamlQuote(category)}');
    }

    // Cover images.
    if (coverImages.isEmpty) {
      buf.writeln('coverImages: []');
    } else {
      buf.writeln('coverImages:');
      for (final img in coverImages) {
        buf.writeln('  - $img');
      }
    }

    // Description (equipment & scenario only).
    if (type == GuideType.equipment || type == GuideType.scenario) {
      if (description.isNotEmpty) {
        buf.writeln('description: |');
        for (final line in description.split('\n')) {
          buf.writeln('  $line');
        }
      } else {
        buf.writeln('description: ""');
      }
    }

    // Sections.
    if (sections.isEmpty) {
      buf.writeln('sections: []');
    } else {
      buf.writeln('sections:');
      for (final sec in sections) {
        buf.writeln('  - title: ${_yamlQuote(sec.title)}');

        if (sec.images.isEmpty) {
          buf.writeln('    images: []');
        } else {
          buf.writeln('    images:');
          for (final img in sec.images) {
            buf.writeln('      - $img');
          }
        }

        if (sec.body.isEmpty) {
          buf.writeln('    body: ""');
        } else {
          buf.writeln('    body: |');
          for (final line in sec.body.split('\n')) {
            buf.writeln('      $line');
          }
        }
      }
    }

    // Related (equipment & scenario only).
    if (type == GuideType.equipment || type == GuideType.scenario) {
      if (related.isEmpty) {
        buf.writeln('related: []');
      } else {
        buf.writeln('related:');
        for (final r in related) {
          buf.writeln('  - $r');
        }
      }
    }

    // Inventory fields (equipment only).
    if (type == GuideType.equipment) {
      if (quantity != null) buf.writeln('quantity: $quantity');
      if (storage != null && storage.isNotEmpty) {
        buf.writeln('storage: ${_yamlQuote(storage)}');
      }
    }

    return buf.toString();
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
