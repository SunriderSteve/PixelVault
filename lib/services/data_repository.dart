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

  // ---- overlay change signal ----
  final ValueNotifier<int> overlayEpoch = ValueNotifier<int>(
    0,
  ); // increments whenever overlay changes

  // expose overlay entry for a given equipment id
  Map<String, dynamic>? getOverlayFor(String id) => _overlay[id];

  // restart periodic overlay polling from now (uses admin.pollSeconds)
  void _resetOverlayPollingTimer() {
    _overlayTimer?.cancel();
    final seconds = (_admin?.pollSeconds ?? 5);
    _overlayTimer = Timer.periodic(Duration(seconds: seconds), (_) {
      // safe to call async without await in a timer
      fetchOverlayOnce();
    });
  }

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

    // snapshot for revert on failure
    final prev = Map<String, dynamic>.from(_overlay[equipmentId] ?? const {});

    // cancel timer to avoid race where a poll grabs stale values mid-write
    _overlayTimer?.cancel();

    // optimistic local update immediately (cosmetic until next poll)
    final next = Map<String, dynamic>.from(prev);
    if (quantity != null) next['quantity'] = quantity;
    if (cabinet != null) next['cabinet'] = cabinet;
    _overlay[equipmentId] = next;
    overlayEpoch.value++; // notify listeners (inventory page will re-render)

    // write to gist
    try {
      await client.updateEntry(
        equipmentId,
        quantity: quantity,
        cabinet: cabinet,
        token: token,
      );
    } catch (e) {
      // revert local optimistic change on failure
      if (prev.isEmpty) {
        _overlay.remove(equipmentId);
      } else {
        _overlay[equipmentId] = prev;
      }
      overlayEpoch.value++; // notify revert
      // restart polling even on failure
      _resetOverlayPollingTimer();
      rethrow;
    }

    // success: do NOT fetch immediately; let polling pull the ground truth later
    _resetOverlayPollingTimer();
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
