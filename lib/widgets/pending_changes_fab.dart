// PixelVault — Pending changes floating action button + review dialog.
//
// Admin-only floating button that surfaces whenever the in-memory
// batch queue has unpushed guide/inventory changes (or we're still
// counting down the post-push cooldown). Pressing it opens a dialog
// that lists every pending op, lets the admin remove individual ops,
// and exposes a Push button that ships the whole batch as one atomic
// Git commit.
//
// Why this exists: the plain GitHub Contents API / Git Data API don't
// like rapid-fire commits to the same branch — two writes within ~1s
// reliably trip the "Update is not a fast forward" 422. Batching +
// cooldown is the ergonomic fix.
//
// Visual contract:
//   * Solid-fill NLB-blue circle (no glassmorphism — deliberately the
//     "this is the save button" visual anchor on every page).
//   * Red cooldown arc recedes around the circle as the 10-minute
//     post-push cooldown ticks down.
//   * Tiny red badge with the queue size; hidden when empty.
//
// Placement is handled by the host page (or the app's global overlay
// in main.dart); this widget just renders the button + its dialog.

import 'package:flutter/material.dart';

import '../router.dart' show rootNavigatorKey;
import '../services/batch_queue.dart';
import 'admin_auth.dart';

// ── NLB-derived brand palette. Kept file-private and solid-filled so
// the FAB reads as "not glassmorphism" against the app's frosted UI.
const Color _kNlbBlue = Color(0xFF0047BB);
const Color _kNlbRed = Color(0xFFE80029);
const Color _kNlbOrange = Color(0xFFFF8200);

/// Refuse a fresh edit/delete on [entityId] if the batch queue already
/// contains a pending op for it. Surfaces a snackbar describing what
/// the conflict is so the admin knows to push (or remove the queued
/// op) before trying again. Returns true when it's safe to proceed.
///
/// Why: layering a second mutation on top of an unpushed first one
/// either coalesces silently (and confuses the admin about what'll
/// land in the next commit) or — in the create-then-delete case — is
/// a literal contradiction. Cheaper to block at the entry point and
/// force the admin to resolve the existing op explicitly.
bool ensureNoPendingChangeFor(BuildContext context, String entityId) {
  final pending = BatchQueueService().firstOpFor(entityId);
  if (pending == null) return true;

  final String kindLabel = switch (pending.kind) {
    PendingOpKind.creation => 'creation',
    PendingOpKind.edit => 'edit',
    PendingOpKind.removal => 'removal',
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          'Cannot proceed: a pending $kindLabel for '
          '"${pending.displayName}" is already queued. Push it (or '
          'remove it from the batch) before making another change.',
        ),
        backgroundColor: _kNlbRed,
        duration: const Duration(seconds: 5),
      ),
    );
  return false;
}

/// Floating action button + cooldown ring. Show this anywhere in the
/// app; it self-hides for non-admins and when there's nothing to push
/// and no cooldown running.
class PendingChangesFab extends StatelessWidget {
  const PendingChangesFab({super.key});

  @override
  Widget build(BuildContext context) {
    final queue = BatchQueueService();

    return ValueListenableBuilder<bool>(
      valueListenable: adminNotifier,
      builder: (_, isAdmin, _) {
        if (!isAdmin) return const SizedBox.shrink();

        return ValueListenableBuilder<int>(
          valueListenable: queue.queueEpoch,
          builder: (_, _, _) {
            return ValueListenableBuilder<Duration>(
              valueListenable: queue.cooldownRemaining,
              builder: (_, cooldown, _) {
                final int opCount = queue.ops.length;

                // The FAB only ever exists when there's something
                // queued. The cooldown ring still renders during the
                // 10-minute window AFTER a push, but only if the admin
                // has already added new ops in the meantime — an empty
                // queue means nothing to push, so no button.
                if (opCount == 0) {
                  return const SizedBox.shrink();
                }

                return _FabButton(
                  opCount: opCount,
                  cooldown: cooldown,
                  onTap: () => _openDialog(context),
                );
              },
            );
          },
        );
      },
    );
  }

  void _openDialog(BuildContext context) {
    // The FAB is hosted in `MaterialApp.builder`, which sits ABOVE the
    // Navigator — so `Navigator.of(context)` from this widget's own
    // context can't find a Navigator and `showDialog` is silently
    // dropped. Route through the router's root navigator instead.
    final navContext = rootNavigatorKey.currentContext ?? context;
    showDialog<void>(
      context: navContext,
      barrierDismissible: true,
      builder: (_) => const _PendingChangesDialog(),
    );
  }
}

/// The button + its cooldown arc. Extracted into its own widget to
/// keep the outer `ValueListenableBuilder` nesting readable.
class _FabButton extends StatelessWidget {
  final int opCount;
  final Duration cooldown;
  final VoidCallback onTap;

  const _FabButton({
    required this.opCount,
    required this.cooldown,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double cooldownFraction = cooldown > Duration.zero
        ? cooldown.inMilliseconds /
              BatchQueueService.cooldownDuration.inMilliseconds
        : 0;

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Cooldown arc — only rendered while the cooldown is active.
          // The arc starts full and recedes clockwise toward empty as
          // time runs out.
          if (cooldownFraction > 0)
            SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(
                value: cooldownFraction,
                strokeWidth: 3,
                valueColor: const AlwaysStoppedAnimation<Color>(_kNlbRed),
                backgroundColor: Colors.white.withValues(alpha: 0.15),
              ),
            ),
          // Solid NLB-blue button.
          SizedBox(
            width: 56,
            height: 56,
            child: Material(
              color: _kNlbBlue,
              shape: const CircleBorder(),
              elevation: 4,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: const Center(
                  child: Icon(
                    Icons.cloud_upload,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
          // Count badge — hidden when queue is empty (happens briefly
          // during cooldown right after a successful push).
          if (opCount > 0)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _kNlbRed,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                constraints: const BoxConstraints(minWidth: 20),
                child: Text(
                  '$opCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// Review dialog
// ══════════════════════════════════════════════════════════════════

class _PendingChangesDialog extends StatefulWidget {
  const _PendingChangesDialog();

  @override
  State<_PendingChangesDialog> createState() => _PendingChangesDialogState();
}

class _PendingChangesDialogState extends State<_PendingChangesDialog> {
  final BatchQueueService _queue = BatchQueueService();

  @override
  Widget build(BuildContext context) {
    // Listen to all three notifiers the dialog cares about so any
    // change (queue mutated, cooldown tick, auto-flush tick,
    // flush-in-flight) refreshes the body without us having to
    // manually call setState from outside.
    return ValueListenableBuilder<int>(
      valueListenable: _queue.queueEpoch,
      builder: (_, _, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: _queue.cooldownRemaining,
          builder: (_, cooldown, _) {
            return ValueListenableBuilder<Duration>(
              valueListenable: _queue.autoFlushRemaining,
              builder: (_, autoFlush, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _queue.isFlushing,
                  builder: (_, isFlushing, _) {
                    return _buildDialog(cooldown, autoFlush, isFlushing);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDialog(Duration cooldown, Duration autoFlush, bool isFlushing) {
    final ops = _queue.ops;
    final creations = ops
        .where((o) => o.kind == PendingOpKind.creation)
        .toList();
    final edits = ops.where((o) => o.kind == PendingOpKind.edit).toList();
    final removals = ops.where((o) => o.kind == PendingOpKind.removal).toList();

    return Dialog(
      backgroundColor: Colors.grey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildDescription(),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (creations.isNotEmpty) ...[
                        _buildSectionHeader('Creations', creations.length),
                        const SizedBox(height: 6),
                        for (final op in creations) _buildOpRow(op),
                        const SizedBox(height: 16),
                      ],
                      if (edits.isNotEmpty) ...[
                        _buildSectionHeader('Edits', edits.length),
                        const SizedBox(height: 6),
                        for (final op in edits) _buildOpRow(op),
                        const SizedBox(height: 16),
                      ],
                      if (removals.isNotEmpty) ...[
                        _buildSectionHeader('Removals', removals.length),
                        const SizedBox(height: 6),
                        for (final op in removals) _buildOpRow(op),
                        const SizedBox(height: 16),
                      ],
                      if (ops.isEmpty) _buildEmptyState(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildTimers(cooldown, autoFlush),
              const SizedBox(height: 16),
              _buildActions(cooldown, isFlushing),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header + description ──────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      children: [
        const Icon(Icons.cloud_upload, color: _kNlbBlue, size: 26),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Pending Changes',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white54),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close',
        ),
      ],
    );
  }

  Widget _buildDescription() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kNlbBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kNlbBlue.withValues(alpha: 0.35)),
      ),
      child: const Text(
        'PixelVault pools guides & inventory edits into one Git push to '
        'avoid GitHub\'s rapid-commit rate limits. \n\nReview the list below, '
        'remove anything you didn\'t mean to stage, then press Push. '
        '\n\nAfter a push you must wait 10 minutes before pushing again; if '
        'you leave changes pending they\'ll auto-push in 30 minutes. '
        '\n\nNote: pending changes live only in this browser session — '
        'meaning changes will be lost if you reload the browser before pushing.',
        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
      ),
    );
  }

  // ── Op list ───────────────────────────────────────────────────

  Widget _buildSectionHeader(String label, int count) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOpRow(PendingOp op) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              op.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 18),
            onPressed: () => _confirmRemove(op),
            tooltip: 'Remove from batch',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text(
        'No pending changes.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  // ── Timers row ────────────────────────────────────────────────

  Widget _buildTimers(Duration cooldown, Duration autoFlush) {
    final List<Widget> rows = [];

    if (cooldown > Duration.zero) {
      rows.add(
        _timerRow(
          icon: Icons.lock_clock,
          color: _kNlbRed,
          label: 'Cooldown',
          remaining: cooldown,
        ),
      );
    }
    if (autoFlush > Duration.zero) {
      rows.add(
        _timerRow(
          icon: Icons.schedule,
          color: _kNlbOrange,
          label: 'Auto-push in',
          remaining: autoFlush,
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          Padding(padding: const EdgeInsets.only(bottom: 4), child: row),
      ],
    );
  }

  Widget _timerRow({
    required IconData icon,
    required Color color,
    required String label,
    required Duration remaining,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        Text(
          _formatMmSs(remaining),
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  static String _formatMmSs(Duration d) {
    final int mm = d.inMinutes;
    final int ss = d.inSeconds.remainder(60);
    return '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }

  // ── Action row ────────────────────────────────────────────────

  Widget _buildActions(Duration cooldown, bool isFlushing) {
    final bool cooling = cooldown > Duration.zero;
    final bool queueEmpty = _queue.ops.isEmpty;
    final bool pushDisabled = cooling || queueEmpty || isFlushing;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close', style: TextStyle(color: Colors.white54)),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: pushDisabled ? null : _onPush,
          icon: isFlushing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.cloud_upload),
          label: Text(isFlushing ? 'Pushing…' : 'Push'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _kNlbBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.white.withValues(alpha: 0.15),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.4),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  // ── Op mutations ─────────────────────────────────────────────

  Future<void> _confirmRemove(PendingOp op) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Remove from batch?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Drop the pending change to "${op.displayName}"? The local '
          'state will revert so the UI matches what will actually be '
          'pushed.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kNlbRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _queue.remove(op.id);
    }
  }

  Future<void> _onPush() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _queue.flush();
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Changes pushed successfully.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Push failed: $e'), backgroundColor: _kNlbRed),
      );
    }
  }
}
