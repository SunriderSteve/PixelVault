import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

import '../models/equipment_model.dart'; // Equipment
import '../models/learn_videography_model.dart'; // VideographyGuide
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
    // read asset manifest once, then filter by directory prefix
    final manifest = await _loadAssetManifest();

    final equipPaths = _filterYaml(manifest, 'data/equipment/');
    final videoPaths = _filterYaml(manifest, 'data/learn_videography/');
    final scenarioPaths = _filterYaml(manifest, 'data/scenarios/');

    // load equipment yaml files
    for (final path in equipPaths) {
      try {
        final ystr = await rootBundle.loadString(path);
        final ymap = loadYaml(ystr) as YamlMap;
        final e = Equipment.fromYaml(
          ymap,
        ); // cabinet/quantity intentionally null here
        _equipment[e.id] = e;
      } catch (e, st) {
        debugPrint('equipment parse failed $path: $e\n$st');
      }
    }

    // load videography yaml files
    for (final path in videoPaths) {
      try {
        final ystr = await rootBundle.loadString(path);
        final ymap = loadYaml(ystr) as YamlMap;
        final g = VideographyGuide.fromYaml(ymap);
        _videography[g.id] = g;
      } catch (e, st) {
        debugPrint('videography parse failed $path: $e\n$st');
      }
    }

    // load scenario yaml files
    for (final path in scenarioPaths) {
      try {
        final ystr = await rootBundle.loadString(path);
        final ymap = loadYaml(ystr) as YamlMap;
        final s = ScenarioGuide.fromYaml(ymap);
        _scenarios[s.id] = s;
      } catch (e, st) {
        debugPrint('scenario parse failed $path: $e\n$st');
      }
    }
  }

  Future<Map<String, dynamic>> _loadAssetManifest() async {
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final parsed = json.decode(manifestJson);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (e, st) {
      debugPrint('AssetManifest read failed: $e\n$st');
    }
    return {};
  }

  List<String> _filterYaml(Map<String, dynamic> manifest, String prefix) {
    final out = <String>[];
    for (final entry in manifest.entries) {
      final path = entry.key;
      if (path.startsWith(prefix) && path.endsWith('.yaml')) {
        out.add(path);
      }
    }
    out.sort();
    return out;
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
    final secs = _admin?.pollSeconds ?? 5;
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
