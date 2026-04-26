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
import 'batch_queue.dart';
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

  // Same pattern for videography + scenario guides: per-file timer,
  // in-flight guard, ETag for 304 short-circuiting, and a write epoch
  // so polls that started before a write can't clobber post-write
  // local state.
  Timer? _videographyTimer;
  bool _fetchingVideography = false;
  String? _videographyEtag;
  int _videographyWriteEpoch = 0;

  Timer? _scenariosTimer;
  bool _fetchingScenarios = false;
  String? _scenariosEtag;
  int _scenariosWriteEpoch = 0;

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

    // Wire the batch queue so its auto-flush + manual-push paths hand
    // control back here to build the single atomic commit.
    BatchQueueService().registerFlush(_flushBatch);

    await _loadGuidesFromRepo();
    await fetchShootsOnce();
    _startEquipmentPolling();
    _startVideographyPolling();
    _startScenariosPolling();
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
  // Videography polling
  // ══════════════════════════════════════════════════════════════

  /// Poll videography.yaml via the authenticated Contents API. Mirrors
  /// [fetchEquipmentOnce] — same ETag + write-epoch guards, same poll
  /// interval from admin config.
  Future<bool> fetchVideographyOnce() async {
    if (_fetchingVideography) return false;
    if (_repoClient == null) return false;
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) return false;

    final int startEpoch = _videographyWriteEpoch;
    _fetchingVideography = true;
    try {
      final result = await _repoClient!.pollViaApi(
        _admin!.videographyFile,
        token,
        etag: _videographyEtag,
      );
      if (result == null) return false; // 304

      if (_videographyWriteEpoch != startEpoch) return false;
      _videographyEtag = result.etag;

      _videography.clear();
      for (final doc in loadYamlStream(result.content)) {
        if (doc is! YamlMap) continue;
        final v = VideographyGuide.fromYaml(doc);
        _videography[v.id] = v;
      }
      guidesEpoch.value++;
      return true;
    } catch (e, st) {
      debugPrint('videography poll error: $e\n$st');
      return false;
    } finally {
      _fetchingVideography = false;
    }
  }

  void _startVideographyPolling() {
    _videographyTimer?.cancel();
    final int secs = _admin?.pollSeconds ?? 5;
    if (secs <= 0 || _repoClient == null) return;

    _videographyTimer = Timer.periodic(Duration(seconds: secs), (_) {
      fetchVideographyOnce();
    });
  }

  // ══════════════════════════════════════════════════════════════
  // Scenario polling
  // ══════════════════════════════════════════════════════════════

  /// Poll scenarios.yaml via the authenticated Contents API.
  Future<bool> fetchScenariosOnce() async {
    if (_fetchingScenarios) return false;
    if (_repoClient == null) return false;
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) return false;

    final int startEpoch = _scenariosWriteEpoch;
    _fetchingScenarios = true;
    try {
      final result = await _repoClient!.pollViaApi(
        _admin!.scenarioFile,
        token,
        etag: _scenariosEtag,
      );
      if (result == null) return false; // 304

      if (_scenariosWriteEpoch != startEpoch) return false;
      _scenariosEtag = result.etag;

      _scenarios.clear();
      for (final doc in loadYamlStream(result.content)) {
        if (doc is! YamlMap) continue;
        final s = ScenarioGuide.fromYaml(doc);
        _scenarios[s.id] = s;
      }
      guidesEpoch.value++;
      return true;
    } catch (e, st) {
      debugPrint('scenarios poll error: $e\n$st');
      return false;
    } finally {
      _fetchingScenarios = false;
    }
  }

  void _startScenariosPolling() {
    _scenariosTimer?.cancel();
    final int secs = _admin?.pollSeconds ?? 5;
    if (secs <= 0 || _repoClient == null) return;

    _scenariosTimer = Timer.periodic(Duration(seconds: secs), (_) {
      fetchScenariosOnce();
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

  /// Queue an inventory edit for [equipmentId]. The local cache is NOT
  /// updated until the batch pushes — the admin sees the old values
  /// in the list while the change sits in the queue. Same reason as
  /// creations: optimistic edits that touch images render broken
  /// thumbnails before the blobs are uploaded, and applying the same
  /// rule to plain quantity/storage tweaks keeps the rule simple
  /// ("nothing changes until you push").
  Future<void> applyInventoryChanges(
    String equipmentId, {
    int? quantity,
    String? storage,
  }) async {
    if (_admin == null) throw StateError('clients not ready');
    if (_admin!.accessToken.isEmpty) throw StateError('missing access token');

    final prevEquipment = _equipment[equipmentId];
    if (prevEquipment == null) {
      throw StateError('equipment "$equipmentId" not found');
    }

    BatchQueueService().add(PendingOp(
      displayName: prevEquipment.name,
      kind: PendingOpKind.edit,
      entityId: equipmentId,
      yamlFile: _admin!.equipmentFile,
      applyToYaml: (content) => _updateEquipmentDocument(
        content,
        equipmentId,
        quantity: quantity,
        storage: storage,
      ),
      commitSummary: 'Edit inventory for ${prevEquipment.name}',
      // Nothing to revert — the local cache was never touched.
      revertLocal: () {},
    ));
  }

  // ══════════════════════════════════════════════════════════════
  // Equipment creation
  // ══════════════════════════════════════════════════════════════

  /// Queue a new equipment entry (inventory-only, no guide) for
  /// equipment.yaml.
  ///
  /// The local cache is NOT touched at enqueue time — the new item
  /// only enters the in-memory map after the batch pushes and the
  /// next poll picks it up from the repo. Optimistic adds caused
  /// missing-image errors because the cover blob hasn't been uploaded
  /// yet at enqueue time, so the inventory list would render a tile
  /// pointing at a 404 until push.
  Future<void> createEquipment({
    required String name,
    required String brand,
    required String category,
    required int quantity,
    String? storage,
    ({Uint8List bytes, String repoPath})? coverImage,
  }) async {
    if (_admin == null) throw StateError('clients not ready');
    if (_admin!.accessToken.isEmpty) throw StateError('missing access token');

    // Generate a slug-style ID from the name.
    final String id = generateId(name);
    if (_equipment.containsKey(id)) {
      throw StateError('Equipment with id "$id" already exists');
    }
    if (BatchQueueService().hasPendingFor(id)) {
      throw StateError('A pending change for "$id" is already queued');
    }

    // Build the YAML document once; the closure captures it verbatim.
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
    final String yamlDoc = newDoc.toString();

    final imageWrites = <String, Uint8List>{};
    if (coverImage != null) {
      imageWrites[coverImage.repoPath] = coverImage.bytes;
    }

    BatchQueueService().add(PendingOp(
      displayName: name,
      kind: PendingOpKind.creation,
      entityId: id,
      yamlFile: _admin!.equipmentFile,
      // Strip-then-append so a re-enqueue after a failed flush doesn't
      // land a duplicate doc in the YAML.
      applyToYaml: (content) =>
          _appendDocument(_removeDocumentById(content, id), yamlDoc),
      imageWrites: imageWrites,
      commitSummary: 'Add $name',
      // Nothing to revert — the local cache was never touched.
      revertLocal: () {},
    ));
  }

  /// Queue deletion of an equipment item. Drops the YAML document and
  /// every image it referenced. Local state is updated immediately;
  /// the push is batched with any other pending ops.
  Future<void> deleteEquipment(String id) async {
    if (_admin == null) throw StateError('clients not ready');
    if (_admin!.accessToken.isEmpty) throw StateError('missing access token');

    final eq = _equipment[id];
    if (eq == null) throw StateError('equipment "$id" not found');

    final imageDeletes = <String>{
      ...eq.coverImages,
      for (final sec in eq.sections) ...sec.images,
    };

    // Optimistic local state.
    _equipment.remove(id);
    overlayEpoch.value++;

    BatchQueueService().add(PendingOp(
      displayName: eq.name,
      kind: PendingOpKind.removal,
      entityId: id,
      yamlFile: _admin!.equipmentFile,
      applyToYaml: (content) => _removeDocumentById(content, id),
      imageDeletes: imageDeletes,
      commitSummary: 'Delete ${eq.name}',
      revertLocal: () {
        _equipment[id] = eq;
        overlayEpoch.value++;
      },
    ));
  }

  /// Queue a cover image replacement for an equipment item. The new
  /// image bytes are pooled into the next batch push along with a
  /// delete for the previous covers and a rewrite of the YAML entry.
  ///
  /// Local cache is left alone until push: rewriting `coverImages` to
  /// the new path before the blob is uploaded would render the tile
  /// with a 404 placeholder.
  Future<void> replaceEquipmentCoverImage(
    String id, {
    required Uint8List bytes,
    required String repoPath,
  }) async {
    if (_admin == null) throw StateError('clients not ready');
    if (_admin!.accessToken.isEmpty) throw StateError('missing access token');

    final eq = _equipment[id];
    if (eq == null) throw StateError('equipment "$id" not found');

    final oldCovers = eq.coverImages.where((p) => p != repoPath).toList();

    BatchQueueService().add(PendingOp(
      displayName: eq.name,
      kind: PendingOpKind.edit,
      entityId: id,
      yamlFile: _admin!.equipmentFile,
      applyToYaml: (content) =>
          _replaceCoverImagesInDoc(content, id, [repoPath]),
      imageWrites: {repoPath: bytes},
      imageDeletes: oldCovers.toSet(),
      commitSummary: 'Replace cover image for ${eq.name}',
      revertLocal: () {},
    ));
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

  /// Queue a new guide for the given [type]. All images are pooled as
  /// part of the pending op; when the batch flushes the YAML + every
  /// image blob are pushed in one atomic Git commit.
  ///
  /// [coverImages] and [sections] carry the already-converted image
  /// bytes alongside their target repo paths. Asset-only entries
  /// (pre-existing images kept during edit) have null bytes.
  ///
  /// Local cache is left alone until push: optimistic inserts would
  /// add a tile to the guide list pointing at image paths whose blobs
  /// haven't been uploaded yet, rendering as 404s until the push
  /// completes.
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
    if (_admin == null) throw StateError('clients not ready');
    if (_admin!.accessToken.isEmpty) throw StateError('missing access token');

    if (BatchQueueService().hasPendingFor(id)) {
      throw StateError('A pending change for "$id" is already queued');
    }

    // 1. Build YAML document + collect image bytes keyed by path.
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

    final imageWrites = <String, Uint8List>{};
    for (final img in coverImages) {
      if (img.bytes != null) imageWrites[img.repoPath] = img.bytes!;
    }
    for (final sec in sections) {
      for (final img in sec.images) {
        if (img.bytes != null) imageWrites[img.repoPath] = img.bytes!;
      }
    }

    // 2. Build the yaml mutation + enqueue. No optimistic cache write.
    final String yamlFile = switch (type) {
      GuideType.equipment => _admin!.equipmentFile,
      GuideType.videography => _admin!.videographyFile,
      GuideType.scenario => _admin!.scenarioFile,
    };
    final String kindLabel = switch (type) {
      GuideType.equipment => 'equipment',
      GuideType.videography => 'videography',
      GuideType.scenario => 'scenario',
    };

    BatchQueueService().add(PendingOp(
      displayName: name,
      kind: PendingOpKind.creation,
      entityId: id,
      yamlFile: yamlFile,
      applyToYaml: (content) {
        var c = content;
        if (type == GuideType.equipment && existingEquipId != null) {
          c = _removeDocumentById(c, existingEquipId);
        }
        // If we're re-enqueuing this op after a failure, the doc may
        // already be present — strip it first so we never double-write.
        c = _removeDocumentById(c, id);
        return _appendDocument(c, yamlDoc);
      },
      imageWrites: imageWrites,
      commitSummary: 'Add $kindLabel guide $name',
      // Nothing to revert — the local cache was never touched.
      revertLocal: () {},
    ));
  }

  /// Queue an update to an existing guide. The new image bytes go in
  /// with the op; any paths in [removedImagePaths] are scheduled for
  /// deletion when the batch flushes.
  ///
  /// Local cache is left alone until push: writing the new YAML view
  /// (which references new image paths) before the blobs are uploaded
  /// would point detail pages at 404s.
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
    if (_admin == null) throw StateError('clients not ready');
    if (_admin!.accessToken.isEmpty) throw StateError('missing access token');

    // 1. Build updated YAML document.
    final coverPaths = coverImages.map((e) => e.repoPath).toList();
    final sectionData = sections
        .map((s) => (
              title: s.title,
              body: s.body,
              images: s.images.map((i) => i.repoPath).toList(),
            ))
        .toList();

    // Equipment carries inventory fields that aren't part of the
    // editor form; preserve them from the existing cache entry.
    final existingEq =
        type == GuideType.equipment ? _equipment[id] : null;
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
      quantity: existingEq?.quantity,
      storage: existingEq?.storage,
    );

    // 2. Gather image writes + deletes.
    final imageWrites = <String, Uint8List>{};
    for (final img in coverImages) {
      if (img.bytes != null) imageWrites[img.repoPath] = img.bytes!;
    }
    for (final sec in sections) {
      for (final img in sec.images) {
        if (img.bytes != null) imageWrites[img.repoPath] = img.bytes!;
      }
    }
    final imageDeletes = removedImagePaths.toSet();

    final String yamlFile = switch (type) {
      GuideType.equipment => _admin!.equipmentFile,
      GuideType.videography => _admin!.videographyFile,
      GuideType.scenario => _admin!.scenarioFile,
    };
    final String kindLabel = switch (type) {
      GuideType.equipment => 'equipment',
      GuideType.videography => 'videography',
      GuideType.scenario => 'scenario',
    };

    BatchQueueService().add(PendingOp(
      displayName: name,
      kind: PendingOpKind.edit,
      entityId: id,
      yamlFile: yamlFile,
      applyToYaml: (content) {
        var c = _removeDocumentById(content, id);
        return _appendDocument(c, yamlDoc);
      },
      imageWrites: imageWrites,
      imageDeletes: imageDeletes,
      commitSummary: 'Edit $kindLabel guide $name',
      // Nothing to revert — the local cache was never touched.
      revertLocal: () {},
    ));
  }

  /// Queue deletion of a guide. Dispatches by [type]:
  ///
  ///  * equipment + [removeFromInventory] true  → delegates to
  ///    [deleteEquipment] so the doc + every image drops in the same
  ///    batch.
  ///  * equipment + [removeFromInventory] false → replaces the doc
  ///    with a minimal `no_guide: true` entry (name / brand / category /
  ///    quantity / storage / first cover image) so the item still shows
  ///    in the inventory list, and schedules the section images + any
  ///    extra covers for deletion.
  ///  * videography / scenario → drops the doc and every image.
  Future<void> deleteGuide({
    required GuideType type,
    required String id,
    bool removeFromInventory = false,
  }) async {
    if (type == GuideType.equipment && removeFromInventory) {
      await deleteEquipment(id);
      return;
    }

    if (_admin == null) throw StateError('clients not ready');
    if (_admin!.accessToken.isEmpty) throw StateError('missing access token');

    if (type == GuideType.equipment) {
      // Strip the guide but keep the inventory entry.
      final eq = _equipment[id];
      if (eq == null) throw StateError('equipment "$id" not found');

      final keptCovers = eq.coverImages.isEmpty
          ? <String>[]
          : [eq.coverImages.first];
      final discardedCovers = eq.coverImages.length > 1
          ? eq.coverImages.sublist(1)
          : <String>[];

      final noGuideDoc = _buildNoGuideEquipmentYaml(
        id: id,
        name: eq.name,
        brand: eq.brand,
        category: eq.category,
        coverImages: keptCovers,
        quantity: eq.quantity,
        storage: eq.storage,
      );

      final imageDeletes = <String>{
        ...discardedCovers,
        for (final sec in eq.sections) ...sec.images,
      };

      // Optimistic local state.
      _equipment[id] = Equipment(
        id: eq.id,
        name: eq.name,
        category: eq.category,
        brand: eq.brand,
        coverImages: keptCovers,
        description: '',
        sections: [],
        related: [],
        storage: eq.storage,
        quantity: eq.quantity,
        noGuide: true,
      );
      overlayEpoch.value++;

      BatchQueueService().add(PendingOp(
        displayName: eq.name,
        kind: PendingOpKind.removal,
        entityId: id,
        yamlFile: _admin!.equipmentFile,
        applyToYaml: (content) {
          var c = _removeDocumentById(content, id);
          return _appendDocument(c, noGuideDoc);
        },
        imageDeletes: imageDeletes,
        commitSummary: 'Strip guide for ${eq.name}',
        revertLocal: () {
          _equipment[id] = eq;
          overlayEpoch.value++;
        },
      ));
      return;
    }

    // Videography / scenario — drop the doc + every image.
    final String yamlFile = type == GuideType.videography
        ? _admin!.videographyFile
        : _admin!.scenarioFile;
    final String displayName;
    final Set<String> imageDeletes;
    final VoidCallback revert;

    if (type == GuideType.videography) {
      final guide = _videography[id];
      if (guide == null) throw StateError('videography guide "$id" not found');
      displayName = guide.name;
      imageDeletes = <String>{
        ...guide.coverImages,
        for (final sec in guide.sections) ...sec.images,
      };
      _videography.remove(id);
      guidesEpoch.value++;
      revert = () {
        _videography[id] = guide;
        guidesEpoch.value++;
      };
    } else {
      final guide = _scenarios[id];
      if (guide == null) throw StateError('scenario guide "$id" not found');
      displayName = guide.name;
      imageDeletes = <String>{
        ...guide.coverImages,
        for (final sec in guide.sections) ...sec.images,
      };
      _scenarios.remove(id);
      guidesEpoch.value++;
      revert = () {
        _scenarios[id] = guide;
        guidesEpoch.value++;
      };
    }

    BatchQueueService().add(PendingOp(
      displayName: displayName,
      kind: PendingOpKind.removal,
      entityId: id,
      yamlFile: yamlFile,
      applyToYaml: (content) => _removeDocumentById(content, id),
      imageDeletes: imageDeletes,
      commitSummary:
          'Delete ${type == GuideType.videography ? 'videography' : 'scenario'} guide $displayName',
      revertLocal: revert,
    ));
  }

  /// Build a minimal equipment YAML document that keeps the inventory
  /// fields but strips the guide content (description / sections / related).
  /// The `no_guide: true` marker is what the inventory list uses to
  /// decide an item is inventory-only.
  String _buildNoGuideEquipmentYaml({
    required String id,
    required String name,
    required String brand,
    required String category,
    required List<String> coverImages,
    int? quantity,
    String? storage,
  }) {
    final buf = StringBuffer();
    buf.writeln('id: $id');
    buf.writeln('name: ${_yamlQuote(name)}');
    buf.writeln('category: ${_yamlQuote(category)}');
    buf.writeln('brand: ${_yamlQuote(brand)}');
    if (coverImages.isEmpty) {
      buf.writeln('coverImages: []');
    } else {
      buf.writeln('coverImages:');
      for (final p in coverImages) {
        buf.writeln('  - $p');
      }
    }
    buf.writeln('description: ""');
    buf.writeln('sections: []');
    buf.writeln('related: []');
    if (quantity != null) buf.writeln('quantity: $quantity');
    if (storage != null && storage.isNotEmpty) {
      buf.writeln('storage: ${_yamlQuote(storage)}');
    }
    buf.writeln('no_guide: true');
    return buf.toString();
  }

  // ══════════════════════════════════════════════════════════════
  // Batch flush — invoked by [BatchQueueService] when the admin presses
  // Push or the auto-flush timer fires.
  // ══════════════════════════════════════════════════════════════

  /// Collapse every op in the queue into a single atomic GitHub commit.
  ///
  /// Reads each unique YAML file once, replays every op's
  /// [PendingOp.applyToYaml] in insertion order to build the final
  /// content, then unions the ops' image writes + deletes. Image deletes
  /// are pre-filtered to paths that actually exist in the repo — the
  /// tree API rejects the whole commit with `GitRPC::BadObjectState`
  /// otherwise. One `commitBatch` call ships the whole thing.
  Future<void> _flushBatch(List<PendingOp> ops) async {
    if (ops.isEmpty) return;
    final client = _guidesClient;
    final repoClient = _repoClient;
    if (client == null || repoClient == null) {
      throw StateError('clients not ready');
    }
    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) throw StateError('missing access token');

    // Cancel all polls + bump write epochs so any in-flight poll
    // response is discarded (would otherwise race with the commit and
    // cause a visible revert).
    _equipmentTimer?.cancel();
    _videographyTimer?.cancel();
    _scenariosTimer?.cancel();
    _equipmentWriteEpoch++;
    _videographyWriteEpoch++;
    _scenariosWriteEpoch++;

    try {
      // 1. Read each unique YAML file once.
      final uniqueFiles = ops.map((o) => o.yamlFile).toSet();
      final yamlContents = <String, String>{};
      for (final file in uniqueFiles) {
        final result = await repoClient.readViaApi(file, token);
        if (result == null) throw StateError('failed to read $file');
        yamlContents[file] = result.content;
      }

      // 2. Replay mutations in order. Also union the image writes
      //    and deletes, with later ops overriding earlier ones: a
      //    write supersedes any pending delete for the same path and
      //    vice-versa, so we never end up asking the tree API to
      //    both add and remove the same blob in the same commit.
      final imageWrites = <String, Uint8List>{};
      final imageDeletes = <String>{};
      for (final op in ops) {
        yamlContents[op.yamlFile] =
            op.applyToYaml(yamlContents[op.yamlFile]!);
        for (final entry in op.imageWrites.entries) {
          imageDeletes.remove(entry.key);
          imageWrites[entry.key] = entry.value;
        }
        for (final path in op.imageDeletes) {
          imageWrites.remove(path);
          imageDeletes.add(path);
        }
      }

      // 3. Pre-filter deletes to only paths that actually exist in the
      //    repo. A previous op in *this* batch may have already declared
      //    the write for some of these paths, so skip those too.
      final existence = await Future.wait(
        imageDeletes.map((p) async => (
              path: p,
              exists: (await repoClient.getFileSha(p, token)) != null,
            )),
      );
      final realDeletes = <String>{
        for (final r in existence)
          if (r.exists) r.path,
      };

      // 4. Build the single commit.
      final changes = <BatchFileChange>[
        for (final e in yamlContents.entries)
          BatchFileChange.write(path: e.key, content: e.value),
        for (final e in imageWrites.entries)
          BatchFileChange.writeBinary(path: e.key, bytes: e.value),
        for (final p in realDeletes) BatchFileChange.delete(path: p),
      ];

      // Commit message: one line per op, truncated if silly-long.
      final summaries = ops.map((o) => o.commitSummary).toList();
      final String message = summaries.length == 1
          ? '${summaries.first} via PixelVault'
          : 'Batch update via PixelVault (${ops.length} changes)\n\n'
              '${summaries.map((s) => '- $s').join('\n')}';

      await repoClient.commitBatch(
        changes,
        token: token,
        message: message,
      );
    } finally {
      _startEquipmentPolling();
      _startVideographyPolling();
      _startScenariosPolling();
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
