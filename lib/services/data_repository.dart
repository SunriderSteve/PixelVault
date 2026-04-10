import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:yaml/yaml.dart';

import '../models/equipment_model.dart'; // Equipment
import '../models/videography_model.dart'; // VideographyGuide
import '../models/scenario_model.dart'; // ScenarioGuide
import '../models/admin_config_model.dart'; // AdminConfigModel
import 'overlay_client.dart'; // InventoryOverlayClient

class DataRepository {
  // singleton to share one cache and one polling loop across app
  static final DataRepository _instance = DataRepository._internal();
  factory DataRepository() => _instance;
  DataRepository._internal() {
    _initFuture = _init(); // kick off initialization once
  }

  // ---- lifecycle ----
  late final Future<void> _initFuture; // await in main to ensure data ready
  Future<void> ensureInitialized() => _initFuture;

  // ---- in-memory stores ----
  final Map<String, Equipment> _equipment = {}; // id -> equipment
  final Map<String, VideographyGuide> _videography = {}; // id -> guide
  final Map<String, ScenarioGuide> _scenarios = {}; // id -> scenario

  // ---- overlay and admin config ----
  AdminConfigModel? _admin; // gist meta from /data/admin.yaml
  InventoryOverlayClient? _overlayClient; // encapsulates network and parse
  Map<String, Map<String, dynamic>> _overlay = {}; // id -> {quantity, cabinet}

  // ---- polling state ----
  Timer? _overlayTimer; // periodic overlay refresher
  bool _fetchingOverlay = false; // prevents overlap

  // ---- post-write stale-poll guard ----
  // After a successful write we record the expected post-write values per
  // equipment id here. On each subsequent poll, any id present in this map
  // is checked against the fetched value:
  //   - match   -> CDN has caught up, drop the pending entry
  //   - mismatch -> fetched data is stale (raw-gist CDN serves pre-write
  //                 content for a while even with cache-busting), so we
  //                 overwrite the fetched entry with the pending value
  //                 before it reaches _applyOverlay, preventing the UI
  //                 from flickering back to the old state
  // Safety: a TTL bounds each entry so a permanently-diverging value (e.g.
  // a concurrent edit by another admin) eventually wins.
  final Map<String, _PendingWrite> _pendingWrites = {};
  static const Duration _pendingWriteTtl = Duration(seconds: 60);

  // ---- overlay change signal ----
  final ValueNotifier<int> overlayEpoch = ValueNotifier<int>(
    0,
  ); // increments whenever overlay changes

  // expose overlay entry for a given equipment id
  Map<String, dynamic>? getOverlayFor(String id) => _overlay[id];

  // ========== init pipeline ==========
  Future<void> _init() async {
    await _loadAdminConfig(); // read /data/admin.yaml for gist config
    _overlayClient = _admin == null ? null : InventoryOverlayClient(_admin!);

    await _loadAllStaticAssets(); // parse equipment, videography, scenarios from assets
    await fetchOverlayOnce(); // apply initial overlay
    _startOverlayPolling(); // begin periodic refresh after static load
  }

  // ========== admin config ==========
  Future<void> _loadAdminConfig() async {
    try {
      final s = await rootBundle.loadString('data/admin_config.yaml');
      _admin = AdminConfigModel.fromYaml(s);
    } catch (e, st) {
      debugPrint('admin.yaml load failed: $e\n$st');
      _admin = null;
    }
  }

  // ========== static assets ==========
  Future<void> _loadAllStaticAssets() async {
    final equipPaths = await _listAssetsIn('data/equipment/');
    final videoPaths = await _listAssetsIn('data/videography/');
    final scenarioPaths = await _listAssetsIn('data/scenarios/');

    // load and parse equipment
    for (final path in equipPaths) {
      final yamlStr = await rootBundle.loadString(path);
      final y = loadYaml(yamlStr) as YamlMap;
      final eq = Equipment.fromYaml(y); // keep your existing parsing
      _equipment[eq.id] = eq;
    }

    // load and parse videography
    for (final path in videoPaths) {
      final yamlStr = await rootBundle.loadString(path);
      final y = loadYaml(yamlStr) as YamlMap;
      final v = VideographyGuide.fromYaml(y);
      _videography[v.id] = v;
    }

    // load and parse scenarios
    for (final path in scenarioPaths) {
      final yamlStr = await rootBundle.loadString(path);
      final y = loadYaml(yamlStr) as YamlMap;
      final s = ScenarioGuide.fromYaml(y);
      _scenarios[s.id] = s;
    }
  }

  /// list asset paths using the new AssetManifest API
  Future<List<String>> _listAssetsIn(
    String prefix, {
    String ext = '.yaml',
  }) async {
    // Loads AssetManifest.bin (or the appropriate format) via the bundle
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    // listAssets() returns all logical asset keys in the bundle
    final all = manifest.listAssets(); // Iterable<String>
    return all
        .where((p) => p.startsWith(prefix) && p.endsWith(ext))
        .toList(growable: false);
  }

  // ========== overlay: fetch + apply ==========
  Future<bool> fetchOverlayOnce() async {
    if (_fetchingOverlay) return false;
    if (_overlayClient == null) return false;

    _fetchingOverlay = true;
    try {
      final map = await _overlayClient!
          .fetch(); // may return null if unavailable
      if (map == null) return false;

      // Reject stale entries for ids we recently wrote to — the raw-gist
      // CDN can keep serving pre-write content for a while. This mutates
      // `map` in place so _applyOverlay sees only values we trust.
      if (_pendingWrites.isNotEmpty) {
        _reconcilePendingWrites(map);
      }

      _applyOverlay(map);

      // 🔔 notify UI that overlay changed (InventoryListPage listens to this)
      overlayEpoch.value++;

      return true;
    } catch (e, st) {
      debugPrint('overlay fetch error: $e\n$st');
      return false;
    } finally {
      _fetchingOverlay = false;
    }
  }

  /// merge pending post-write expectations into an incoming poll result.
  ///
  /// for each pending id we:
  ///   - drop it if the TTL has elapsed (safety net for a permanently
  ///     diverging value, e.g. another admin edited the same id)
  ///   - drop it if the fetched value matches the expected value (the CDN
  ///     has caught up, the write is confirmed)
  ///   - otherwise overwrite the fetched entry with the expected value so
  ///     _applyOverlay doesn't revert the UI to stale data
  void _reconcilePendingWrites(Map<String, Map<String, dynamic>> fetched) {
    final now = DateTime.now();
    final toDrop = <String>[];
    _pendingWrites.forEach((id, pending) {
      if (now.difference(pending.writtenAt) > _pendingWriteTtl) {
        toDrop.add(id);
        return;
      }
      final fetchedEntry = fetched[id];
      if (fetchedEntry != null &&
          _overlayEntriesEqual(fetchedEntry, pending.expected)) {
        toDrop.add(id);
      } else {
        fetched[id] = Map<String, dynamic>.from(pending.expected);
      }
    });
    for (final id in toDrop) {
      _pendingWrites.remove(id);
    }
  }

  bool _overlayEntriesEqual(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    return a['quantity'] == b['quantity'] && a['cabinet'] == b['cabinet'];
  }

  void _startOverlayPolling() {
    _overlayTimer?.cancel();
    final secs = _admin?.pollSeconds ?? 2;
    if (secs <= 0 || _overlayClient == null) return;

    _overlayTimer = Timer.periodic(Duration(seconds: secs), (_) {
      fetchOverlayOnce(); // fire and forget
    });
  }

  /// overlay mutable fields onto in-memory equipment by id
  void _applyOverlay(Map<String, Map<String, dynamic>> ov) {
    _overlay = ov;
    ov.forEach((id, v) {
      final eq = _equipment[id];
      if (eq == null) return;
      _equipment[id] = eq.copyWith(
        quantity: (v['quantity'] as num?)?.toInt(),
        cabinet: v['cabinet'] as String?,
      );
    });
  }

  /// apply inventory changes for one equipment id
  Future<void> applyInventoryChanges(
    String equipmentId, {
    int? quantity,
    String? cabinet,
  }) async {
    final client = _overlayClient;
    if (client == null) throw StateError('overlay client not ready');

    final token = _admin?.accessToken ?? '';

    if (token.isEmpty) {
      throw StateError('missing access token in admin_config.yaml');
    }

    // snapshot for revert on failure — capture BOTH the overlay map entry
    // and the equipment cache entry. The UI reads from _equipment, so both
    // have to be kept in sync or the optimistic update is invisible.
    final prevOverlayEntry = _overlay[equipmentId] == null
        ? null
        : Map<String, dynamic>.from(_overlay[equipmentId]!);
    final prevEquipment = _equipment[equipmentId];

    // cancel timer so an in-flight stale poll response can't clobber the
    // fresh state we're about to write
    _overlayTimer?.cancel();

    // optimistic local update: write both the overlay map AND the equipment
    // cache. Previously only _overlay was touched, but InventoryListPage
    // rebuilds from getAllEquipment() (which reads _equipment), so the user
    // kept seeing stale values until the next poll landed.
    final nextOverlay = Map<String, dynamic>.from(prevOverlayEntry ?? const {});
    if (quantity != null) nextOverlay['quantity'] = quantity;
    if (cabinet != null) nextOverlay['cabinet'] = cabinet;
    _overlay[equipmentId] = nextOverlay;

    if (prevEquipment != null) {
      _equipment[equipmentId] = prevEquipment.copyWith(
        quantity: quantity,
        cabinet: cabinet,
      );
    }
    overlayEpoch.value++; // notify listeners (inventory page re-renders)

    // write to gist
    try {
      final fresh = await client.updateEntry(
        equipmentId,
        quantity: quantity,
        cabinet: cabinet,
        token: token,
      );

      // PATCH response echoes the authoritative post-write gist, so apply it
      // directly — this bypasses the raw-gist CDN that otherwise serves stale
      // content for some time after a write.
      _applyOverlay(fresh);
      overlayEpoch.value++;

      // Record the post-write state as pending. Subsequent polls that come
      // back with stale CDN data will be reconciled against this value in
      // _reconcilePendingWrites, preventing a revert-then-recover flicker.
      final confirmed = fresh[equipmentId];
      if (confirmed != null) {
        _pendingWrites[equipmentId] = _PendingWrite(
          expected: Map<String, dynamic>.from(confirmed),
          writtenAt: DateTime.now(),
        );
      } else {
        _pendingWrites.remove(equipmentId);
      }
    } catch (e) {
      // revert local optimistic change on failure
      if (prevOverlayEntry == null) {
        _overlay.remove(equipmentId);
      } else {
        _overlay[equipmentId] = prevOverlayEntry;
      }
      if (prevEquipment != null) {
        _equipment[equipmentId] = prevEquipment;
      }
      overlayEpoch.value++;
      _startOverlayPolling();
      rethrow;
    }

    _startOverlayPolling();
  }

  // ========== public queries ==========
  List<Equipment> getAllEquipment() => _equipment.values.toList();

  /// inventory shows items that have overlay quantity defined
  List<Equipment> getInventoryItems() {
    final idsWithQty = _overlay.entries
        .where((e) => e.value['quantity'] != null)
        .map((e) => e.key)
        .toSet();
    return _equipment.values.where((e) => idsWithQty.contains(e.id)).toList();
  }

  Equipment? getEquipmentById(String id) => _equipment[id];

  List<VideographyGuide> getAllVideographyGuides() =>
      _videography.values.toList();
  VideographyGuide? getVideographyGuide(String id) => _videography[id];

  List<ScenarioGuide> getAllScenarios() => _scenarios.values.toList();
  ScenarioGuide? getScenario(String id) => _scenarios[id];

  /// manual overlay refresh trigger you can call from UI if needed
  Future<void> forceRefreshOverlay() async => fetchOverlayOnce();

  // ========== cleanup ==========
  void dispose() {
    _overlayTimer?.cancel();
    _overlayTimer = null;
  }
}

/// expected post-write overlay entry + when it was written, used to guard
/// against stale poll responses clobbering a just-confirmed value
class _PendingWrite {
  final Map<String, dynamic> expected;
  final DateTime writtenAt;
  _PendingWrite({required this.expected, required this.writtenAt});
}
