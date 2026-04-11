// PixelVault — Data repository (singleton).
//
// Owns the app's in-memory cache of static YAML content (equipment,
// videography guides, scenarios) and the mutable inventory overlay
// fetched from a GitHub Gist. Exposed to the rest of the app as a
// plain singleton — `DataRepository()` always returns the same
// instance.
//
// Lifecycle:
//   1. The constructor kicks off [_init] and caches its Future.
//   2. Call-sites `await DataRepository().ensureInitialized()` before
//      reading data. `main.dart` does this at boot so the UI can
//      assume the caches are already populated.
//   3. After init, a periodic Timer polls the gist so overlay changes
//      made by another admin / session propagate automatically.
//
// Writes use an optimistic-update pattern:
//   • local state (both _overlay and _equipment) is updated first
//   • the PATCH is issued to the gist
//   • the PATCH response (ground truth) replaces local state
//   • any stale poll response that arrives while the raw CDN is
//     catching up is intercepted in [_reconcilePendingWrites] so the
//     UI never visibly flips back to the pre-write value
//
// Threading: this class is single-threaded Dart code, but the overlay
// polling loop and the optimistic-write path both touch the same
// _overlay / _equipment maps. The [_fetchingOverlay] guard prevents
// overlapping fetches, and [applyInventoryChanges] cancels the poll
// timer while it's writing so an in-flight stale response can't
// clobber the fresh local state.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:yaml/yaml.dart';

import '../models/admin_config_model.dart';
import '../models/equipment_model.dart';
import '../models/scenario_model.dart';
import '../models/videography_model.dart';
import 'overlay_client.dart';

class DataRepository {
  // ── Singleton wiring ────────────────────────────────────────────
  // Share one cache and one polling loop across the whole app.
  static final DataRepository _instance = DataRepository._internal();
  factory DataRepository() => _instance;
  DataRepository._internal() {
    _initFuture = _init(); // Kick off initialization exactly once.
  }

  // ── Lifecycle ───────────────────────────────────────────────────
  /// Cached init future. Callers await this (via [ensureInitialized])
  /// before reading any data so they never see an empty cache.
  late final Future<void> _initFuture;

  /// Await this before reading data. Safe to call repeatedly — the
  /// underlying future is created once in the constructor.
  Future<void> ensureInitialized() => _initFuture;

  // ── In-memory stores ────────────────────────────────────────────
  final Map<String, Equipment> _equipment = {}; // id -> equipment
  final Map<String, VideographyGuide> _videography = {}; // id -> guide
  final Map<String, ScenarioGuide> _scenarios = {}; // id -> scenario

  // ── Overlay + admin config ──────────────────────────────────────
  AdminConfigModel? _admin; // Parsed from /data/admin_config.yaml.
  InventoryOverlayClient? _overlayClient; // Owns all gist HTTP.
  Map<String, Map<String, dynamic>> _overlay =
      {}; // id -> {quantity, cabinet}

  // ── Polling state ───────────────────────────────────────────────
  Timer? _overlayTimer; // Periodic overlay refresher.
  bool _fetchingOverlay = false; // Reentrancy guard for fetchOverlayOnce.

  // ── Post-write stale-poll guard ─────────────────────────────────
  // After a successful write we record the expected post-write values
  // per equipment id here. On each subsequent poll, any id present in
  // this map is checked against the fetched value:
  //
  //   • match     — CDN has caught up, drop the pending entry
  //   • mismatch  — fetched data is stale (the raw-gist CDN serves
  //                 pre-write content for a while even with
  //                 cache-busting), so we overwrite the fetched entry
  //                 with the pending value before it reaches
  //                 [_applyOverlay], preventing the UI from flickering
  //                 back to the old state
  //
  // Safety: a TTL bounds each entry so a permanently-diverging value
  // (e.g. a concurrent edit by another admin) eventually wins and we
  // don't hold stale "expected" state forever.
  final Map<String, _PendingWrite> _pendingWrites = {};
  static const Duration _pendingWriteTtl = Duration(seconds: 60);

  // ── Overlay change signal ───────────────────────────────────────
  /// Increments whenever the overlay changes. UI widgets that need to
  /// rebuild on overlay updates (e.g. inventory list page) listen to
  /// this notifier instead of polling the repository directly.
  final ValueNotifier<int> overlayEpoch = ValueNotifier<int>(0);

  /// Expose the raw overlay entry for a given equipment id. Returns
  /// null when no overlay record exists for that id.
  Map<String, dynamic>? getOverlayFor(String id) => _overlay[id];

  // ══════════════════════════════════════════════════════════════
  // Init pipeline
  // ══════════════════════════════════════════════════════════════
  Future<void> _init() async {
    // Admin config first so the overlay client has gist coordinates
    // before we try to touch the network.
    await _loadAdminConfig();
    _overlayClient = _admin == null ? null : InventoryOverlayClient(_admin!);

    await _loadAllStaticAssets(); // Parse bundled YAMLs into memory.
    await fetchOverlayOnce(); // Apply the initial overlay.
    _startOverlayPolling(); // Begin periodic refresh.
  }

  // ══════════════════════════════════════════════════════════════
  // Admin config
  // ══════════════════════════════════════════════════════════════

  /// Load and parse `data/admin_config.yaml`. A missing / malformed
  /// file is non-fatal — the app still runs, it just operates in
  /// read-only mode with no overlay and no write path.
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
  // Static assets
  // ══════════════════════════════════════════════════════════════

  /// Walk the asset manifest for each content directory and parse
  /// every `.yaml` file into its corresponding in-memory map.
  Future<void> _loadAllStaticAssets() async {
    final equipPaths = await _listAssetsIn('data/equipment/');
    final videoPaths = await _listAssetsIn('data/videography/');
    final scenarioPaths = await _listAssetsIn('data/scenarios/');

    // Equipment.
    for (final path in equipPaths) {
      final yamlStr = await rootBundle.loadString(path);
      final y = loadYaml(yamlStr) as YamlMap;
      final eq = Equipment.fromYaml(y);
      _equipment[eq.id] = eq;
    }

    // Videography guides.
    for (final path in videoPaths) {
      final yamlStr = await rootBundle.loadString(path);
      final y = loadYaml(yamlStr) as YamlMap;
      final v = VideographyGuide.fromYaml(y);
      _videography[v.id] = v;
    }

    // Production scenarios.
    for (final path in scenarioPaths) {
      final yamlStr = await rootBundle.loadString(path);
      final y = loadYaml(yamlStr) as YamlMap;
      final s = ScenarioGuide.fromYaml(y);
      _scenarios[s.id] = s;
    }
  }

  /// List every asset path under [prefix] that ends with [ext], using
  /// the generated [AssetManifest]. This lets us drop new YAML files
  /// into `data/...` without touching code — they're picked up the
  /// next time the bundle is rebuilt.
  Future<List<String>> _listAssetsIn(
    String prefix, {
    String ext = '.yaml',
  }) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final all = manifest.listAssets();
    return all
        .where((p) => p.startsWith(prefix) && p.endsWith(ext))
        .toList(growable: false);
  }

  // ══════════════════════════════════════════════════════════════
  // Overlay: fetch + apply
  // ══════════════════════════════════════════════════════════════

  /// Fetch the overlay once, reconcile against any pending writes,
  /// and apply it to the in-memory caches. Returns true on success,
  /// false when the fetch failed or was skipped (already in flight /
  /// no overlay client configured).
  Future<bool> fetchOverlayOnce() async {
    if (_fetchingOverlay) return false;
    if (_overlayClient == null) return false;

    _fetchingOverlay = true;
    try {
      final map = await _overlayClient!.fetch();
      if (map == null) return false;

      // Reject stale entries for ids we recently wrote to — the raw
      // gist CDN can keep serving pre-write content for a while. This
      // mutates `map` in place so [_applyOverlay] sees only values we
      // trust.
      if (_pendingWrites.isNotEmpty) {
        _reconcilePendingWrites(map);
      }

      _applyOverlay(map);

      // Notify any ValueNotifier listeners that the overlay changed.
      overlayEpoch.value++;

      return true;
    } catch (e, st) {
      debugPrint('overlay fetch error: $e\n$st');
      return false;
    } finally {
      _fetchingOverlay = false;
    }
  }

  /// Merge pending post-write expectations into an incoming poll
  /// result. For each pending id we either:
  ///
  ///   • drop it if the TTL has elapsed (safety net for a permanently
  ///     diverging value, e.g. another admin editing the same id);
  ///   • drop it if the fetched value matches the expected value (the
  ///     CDN has caught up, the write is confirmed); or
  ///   • overwrite the fetched entry with the expected value so
  ///     [_applyOverlay] doesn't revert the UI to stale data.
  void _reconcilePendingWrites(Map<String, Map<String, dynamic>> fetched) {
    final now = DateTime.now();
    final List<String> toDrop = [];
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

  /// Shallow field-by-field comparison over the two mutable inventory
  /// fields. Sufficient because those are the only fields that ever
  /// make it into the overlay map in the first place.
  bool _overlayEntriesEqual(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    return a['quantity'] == b['quantity'] && a['cabinet'] == b['cabinet'];
  }

  /// (Re)start the periodic overlay refresher. Safe to call multiple
  /// times — the previous timer is cancelled before a new one is
  /// started. A polling interval of <= 0 seconds disables polling.
  void _startOverlayPolling() {
    _overlayTimer?.cancel();
    final int secs = _admin?.pollSeconds ?? 2;
    if (secs <= 0 || _overlayClient == null) return;

    _overlayTimer = Timer.periodic(Duration(seconds: secs), (_) {
      fetchOverlayOnce(); // Fire and forget — errors are logged inside.
    });
  }

  /// Overlay the mutable fields onto the in-memory equipment cache by
  /// id. Equipment ids present in the overlay but absent from
  /// [_equipment] are silently ignored so orphan gist entries don't
  /// crash the app.
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

  /// Write inventory changes for a single equipment id through an
  /// optimistic-update pipeline. Throws if no overlay client is
  /// configured or the admin token is missing; otherwise returns once
  /// the gist PATCH has been accepted and local state has been
  /// reconciled with the authoritative response.
  Future<void> applyInventoryChanges(
    String equipmentId, {
    int? quantity,
    String? cabinet,
  }) async {
    final client = _overlayClient;
    if (client == null) throw StateError('overlay client not ready');

    final String token = _admin?.accessToken ?? '';
    if (token.isEmpty) {
      throw StateError('missing access token in admin_config.yaml');
    }

    // Snapshot for revert on failure — capture BOTH the overlay map
    // entry and the equipment cache entry. The UI reads from
    // [_equipment], so both have to stay in sync or the optimistic
    // update is invisible.
    final prevOverlayEntry = _overlay[equipmentId] == null
        ? null
        : Map<String, dynamic>.from(_overlay[equipmentId]!);
    final prevEquipment = _equipment[equipmentId];

    // Cancel the poll timer so an in-flight stale response can't
    // clobber the fresh state we're about to write. Polling is
    // restarted below, in both the success and failure branches.
    _overlayTimer?.cancel();

    // Optimistic local update: write both the overlay map AND the
    // equipment cache. Previously only [_overlay] was touched, but
    // InventoryListPage rebuilds from [getAllEquipment] (which reads
    // [_equipment]), so the user saw stale values until the next
    // poll landed.
    final nextOverlay = Map<String, dynamic>.from(
      prevOverlayEntry ?? const {},
    );
    if (quantity != null) nextOverlay['quantity'] = quantity;
    if (cabinet != null) nextOverlay['cabinet'] = cabinet;
    _overlay[equipmentId] = nextOverlay;

    if (prevEquipment != null) {
      _equipment[equipmentId] = prevEquipment.copyWith(
        quantity: quantity,
        cabinet: cabinet,
      );
    }
    overlayEpoch.value++; // InventoryListPage re-renders.

    try {
      // Issue the write. The PATCH response is the authoritative
      // post-write gist, so we apply it directly instead of trusting
      // the (still CDN-cached) raw endpoint.
      final fresh = await client.updateEntry(
        equipmentId,
        quantity: quantity,
        cabinet: cabinet,
        token: token,
      );

      _applyOverlay(fresh);
      overlayEpoch.value++;

      // Record the post-write state as pending so any stale poll that
      // arrives before the raw CDN has caught up gets reconciled
      // against this expected value in [_reconcilePendingWrites].
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
      // Revert the optimistic local change on failure so the UI
      // matches reality again.
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

  // ══════════════════════════════════════════════════════════════
  // Public queries
  // ══════════════════════════════════════════════════════════════

  /// Every equipment record in the catalogue, in insertion order
  /// (which mirrors the filesystem load order from [_listAssetsIn]).
  List<Equipment> getAllEquipment() => _equipment.values.toList();

  /// Inventory view: equipment that has an overlay-defined quantity.
  /// Items without a quantity entry are considered "not tracked" and
  /// are excluded from the inventory list even if they exist in the
  /// static catalogue.
  List<Equipment> getInventoryItems() {
    final Set<String> idsWithQty = _overlay.entries
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

  /// Manual overlay refresh — call from a UI pull-to-refresh, etc.
  /// The returned Future resolves once the fetch completes (whether
  /// or not it succeeded).
  Future<void> forceRefreshOverlay() async => fetchOverlayOnce();

  // ══════════════════════════════════════════════════════════════
  // Cleanup
  // ══════════════════════════════════════════════════════════════

  /// Stop the polling loop. The singleton itself lives for the whole
  /// app lifetime, so this is mostly useful in tests.
  void dispose() {
    _overlayTimer?.cancel();
    _overlayTimer = null;
  }
}

/// Expected post-write overlay entry + when it was written, used to
/// guard against stale poll responses clobbering a just-confirmed
/// value. See `DataRepository._reconcilePendingWrites` for the full
/// flow.
class _PendingWrite {
  final Map<String, dynamic> expected;
  final DateTime writtenAt;
  _PendingWrite({required this.expected, required this.writtenAt});
}
