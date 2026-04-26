// PixelVault — Batch queue service.
//
// Pools guide and inventory writes into a single atomic GitHub commit
// instead of one API call per user action. The old direct-commit flow
// was hitting the "Update is not a fast forward" 422 whenever two
// writes landed within a few seconds of each other — the ref replicas
// simply couldn't settle fast enough. Batching sidesteps that entirely
// because we only push once, and at a human cadence.
//
// Lifecycle of a change:
//   1. Page calls a DataRepository write (create / edit / delete).
//   2. DataRepository applies the change to the in-memory cache
//      (optimistic) and builds a [PendingOp] with a pure
//      `applyToYaml` mutation, any image writes/deletes, and a
//      revert callback.
//   3. BatchQueueService stores the op and ticks [queueEpoch]; the
//      floating action button in the UI shows up.
//   4. Admin presses Push OR the 30-minute auto-flush timer fires.
//   5. `flush()` hands the op list to DataRepository, which reads the
//      affected YAMLs fresh, replays every mutation in order, and
//      issues a single `commitBatch`.
//   6. On success the queue clears and a 10-minute cooldown starts so
//      subsequent pushes can't storm the ref replicas.
//
// If the push itself fails (network, auth, replication lag), the queue
// stays intact, no cooldown starts, and the auto-flush timer restarts
// so the user can retry without losing work.

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Which tab a [PendingOp] appears under in the review dialog.
///   * [creation] — adding a new entity (equipment, guide, scenario).
///   * [edit]     — modifying an existing entity in place.
///   * [removal]  — deleting an existing entity (or stripping its
///     guide content) entirely.
enum PendingOpKind { creation, edit, removal }

/// A single queued operation. Immutable once constructed — the queue
/// stores a list of these and replays them in order during flush.
class PendingOp {
  /// Stable id, used for removal lookup. Monotonic so list order is
  /// preserved naturally by insertion order.
  final String id;

  /// Stable id of the entity (equipment / guide) this op targets, or
  /// null for ops that aren't tied to a single domain object. Used by
  /// [BatchQueueService.hasPendingFor] so callers can refuse to start
  /// a second edit on something that's already queued.
  final String? entityId;

  /// Human-readable name shown in the review dialog. Typically the
  /// guide or equipment name.
  final String displayName;

  /// Which tab this op appears under.
  final PendingOpKind kind;

  /// Repo path of the YAML file this op mutates (e.g. `data/equipment.yaml`).
  final String yamlFile;

  /// Pure mutation applied to the current YAML content during flush.
  /// Must not depend on anything outside the closure — the queue may
  /// hold ops across many seconds and other ops mutate shared state
  /// between calls.
  final String Function(String content) applyToYaml;

  /// Image blobs to upload as part of this op. Keyed by repo path so
  /// later ops overwrite earlier writes to the same path cleanly.
  final Map<String, Uint8List> imageWrites;

  /// Image repo paths to remove as part of this op. Paths that also
  /// appear in any op's [imageWrites] are skipped at flush time.
  final Set<String> imageDeletes;

  /// Undoes the optimistic local-state change. Called if the admin
  /// removes the op from the queue.
  final VoidCallback revertLocal;

  /// Short summary of the op used when building the batch commit
  /// message — we concatenate all of these.
  final String commitSummary;

  PendingOp({
    required this.displayName,
    required this.kind,
    required this.yamlFile,
    required this.applyToYaml,
    required this.revertLocal,
    required this.commitSummary,
    this.entityId,
    Map<String, Uint8List>? imageWrites,
    Set<String>? imageDeletes,
  })  : id = 'op_${DateTime.now().microsecondsSinceEpoch}_${_counter++}',
        imageWrites = imageWrites ?? <String, Uint8List>{},
        imageDeletes = imageDeletes ?? <String>{};

  static int _counter = 0;
}

/// Callback signature used by [BatchQueueService.flush] to hand off the
/// pooled ops to whichever service actually knows how to commit them
/// (in practice [DataRepository]).
typedef BatchFlushCallback = Future<void> Function(List<PendingOp> ops);

/// Singleton queue that pools guide + inventory writes before pushing.
class BatchQueueService {
  static final BatchQueueService _instance = BatchQueueService._internal();
  factory BatchQueueService() => _instance;
  BatchQueueService._internal();

  // ── Timer durations ────────────────────────────────────────────
  /// How long the user must wait after a successful push before the
  /// next one is allowed. Prevents storming the GitHub ref replicas.
  static const Duration cooldownDuration = Duration(minutes: 10);

  /// How long the system waits before auto-pushing queued ops when
  /// the user hasn't pressed Push themselves.
  static const Duration autoFlushDuration = Duration(minutes: 30);

  // ── State ──────────────────────────────────────────────────────
  final List<PendingOp> _ops = [];

  /// Ticks whenever the op list changes. UI widgets (the FAB + dialog)
  /// listen so they can rebuild.
  final ValueNotifier<int> queueEpoch = ValueNotifier<int>(0);

  /// Remaining time on the post-push cooldown. [Duration.zero] means
  /// the user is free to push.
  final ValueNotifier<Duration> cooldownRemaining =
      ValueNotifier<Duration>(Duration.zero);

  /// Remaining time until the auto-flush fires. [Duration.zero] means
  /// auto-flush isn't currently scheduled (queue empty or cooling down).
  final ValueNotifier<Duration> autoFlushRemaining =
      ValueNotifier<Duration>(Duration.zero);

  /// True while [flush] is in flight.
  final ValueNotifier<bool> isFlushing = ValueNotifier<bool>(false);

  Timer? _cooldownTicker;
  DateTime? _cooldownEnd;
  Timer? _autoFlushTicker;
  DateTime? _autoFlushEnd;

  BatchFlushCallback? _flushCallback;

  // ── Public accessors ──────────────────────────────────────────
  List<PendingOp> get ops => List.unmodifiable(_ops);
  bool get isEmpty => _ops.isEmpty;
  bool get isCoolingDown =>
      _cooldownEnd != null && DateTime.now().isBefore(_cooldownEnd!);

  /// True if any queued op targets [entityId]. Callers use this to
  /// short-circuit a fresh edit/delete and tell the admin to push (or
  /// remove the existing op from the batch) before trying again —
  /// otherwise two edits to the same entity in one batch get fragile,
  /// and a delete-after-create is a literal paradox.
  bool hasPendingFor(String entityId) {
    return _ops.any((o) => o.entityId == entityId);
  }

  /// Returns the first queued op targeting [entityId], if any. Useful
  /// for surfacing what the conflict actually is in error messages.
  PendingOp? firstOpFor(String entityId) {
    for (final op in _ops) {
      if (op.entityId == entityId) return op;
    }
    return null;
  }

  /// Register the flush implementation. Called once from DataRepository
  /// during init.
  void registerFlush(BatchFlushCallback cb) => _flushCallback = cb;

  // ── Queue mutations ───────────────────────────────────────────

  /// Enqueue a new operation. Resets the auto-flush countdown.
  void add(PendingOp op) {
    _ops.add(op);
    queueEpoch.value++;
    _resetAutoFlush();
  }

  /// Remove the op with [id] from the queue and invoke its
  /// `revertLocal` callback so the UI state matches. No-op if the id
  /// isn't found (e.g. raced with a flush).
  void remove(String id) {
    final idx = _ops.indexWhere((o) => o.id == id);
    if (idx < 0) return;
    final op = _ops.removeAt(idx);
    try {
      op.revertLocal();
    } catch (e, st) {
      debugPrint('revertLocal failed for ${op.id}: $e\n$st');
    }
    queueEpoch.value++;
    if (_ops.isEmpty) {
      _stopAutoFlush();
    }
  }

  /// Push every queued op as a single batch. Starts the cooldown on
  /// success; leaves the queue + state untouched on failure.
  Future<void> flush() async {
    if (isCoolingDown) {
      throw StateError('Push is on cooldown.');
    }
    if (isFlushing.value) return;
    if (_ops.isEmpty) return;
    final cb = _flushCallback;
    if (cb == null) {
      throw StateError('Batch flush callback not registered.');
    }

    _stopAutoFlush();
    isFlushing.value = true;
    try {
      final snapshot = List<PendingOp>.from(_ops);
      await cb(snapshot);
      // Success — drop the batch and start the cooldown.
      _ops.clear();
      queueEpoch.value++;
      _startCooldown();
    } catch (_) {
      // Failure leaves the queue intact. Kick the auto-flush back on
      // so the user doesn't have to manually retry if they walk away.
      _resetAutoFlush();
      rethrow;
    } finally {
      isFlushing.value = false;
    }
  }

  // ── Timer helpers ─────────────────────────────────────────────

  void _resetAutoFlush() {
    _stopAutoFlush();
    if (_ops.isEmpty || isCoolingDown) return;
    _autoFlushEnd = DateTime.now().add(autoFlushDuration);
    autoFlushRemaining.value = autoFlushDuration;
    _autoFlushTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final end = _autoFlushEnd;
      if (end == null) return;
      final remaining = end.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _stopAutoFlush();
        // Fire and forget — errors are surfaced via the flush's own
        // rethrow path which will update isFlushing + restart auto.
        flush().catchError((e) {
          debugPrint('auto-flush failed: $e');
        });
      } else {
        autoFlushRemaining.value = remaining;
      }
    });
  }

  void _stopAutoFlush() {
    _autoFlushTicker?.cancel();
    _autoFlushTicker = null;
    _autoFlushEnd = null;
    autoFlushRemaining.value = Duration.zero;
  }

  void _startCooldown() {
    _cooldownEnd = DateTime.now().add(cooldownDuration);
    cooldownRemaining.value = cooldownDuration;
    _cooldownTicker?.cancel();
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final end = _cooldownEnd;
      if (end == null) return;
      final remaining = end.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        _cooldownTicker?.cancel();
        _cooldownTicker = null;
        _cooldownEnd = null;
        cooldownRemaining.value = Duration.zero;
        // If ops accumulated during the cooldown, reschedule the
        // auto-flush now that pushes are unblocked again.
        if (_ops.isNotEmpty) _resetAutoFlush();
      } else {
        cooldownRemaining.value = remaining;
      }
    });
  }
}
