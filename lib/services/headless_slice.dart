// SPDX-License-Identifier: MIT
/// Closed-app vertical slice helpers (Elizabeth, TM slice integration).
///
/// This file is the slice-owned half of the verdict-parity invariant:
/// **headless verdicts == in-app verdicts** (alerts + failed CI runs,
/// stale + no-data). It owns exactly one mapping — failed CI runs into
/// [HeadlessSignal]s — and documents the parity table. Everything else
/// is reuse, never reimplementation:
///
/// - Alert keys/titles: [AlertWatch.keyFor] / [AlertWatch.freshTitles]
///   (in-app rail) and [HeadlessKeys.keyFor] / [HeadlessSignal.displayTitle]
///   (headless rail) share one formula (`kind::owner::title`,
///   `'CI failed: …'` for CI). The formulas live in their home files;
///   the proof that they agree lives in `test/headless_slice_test.dart`.
/// - Evaluation: [AlertRules] (disk 80/90), [Thresholds] (0.85/0.95),
///   [PollPolicy] (5 min → 1 h), [NotificationHook.build] verbatim.
/// - Seen-set: replaced each tick on both rails (parity with
///   `AlertWatch.markSeen`), 6 h resend cooldown.
///
/// Frozen-surface rules for this file (TM-1 freeze, Lina):
/// - Never change the CI key/title formula here without changing
///   `AlertWatch` in the same PR (docus: §4.1 of Kira's
///   `docs/design/06-alert-tray-ux.md`, "Identity").
/// - Never print secrets: titles only (pinned by tests).
library;

import '../background/headless_state.dart';
import '../models/mock_data.dart' show DeployItem;

/// Slice-owned CI mapping: failed runs → headless signals.
///
/// Mirrors [AlertWatch.currentKeys]/[AlertWatch.freshTitles] for the
/// `kind == 'ci'` rows verbatim: key `ci::<env>::<app> <version>`,
/// display line `CI failed: <app> <version>`. Non-failed runs contribute
/// nothing; blank titles are dropped; hostile entries are skipped, never
/// fatal (parity with `unionAlerts`).
///
/// Key/title agreement with the in-app rail is proven (not asserted) by
/// `test/headless_slice_test.dart`, which diffs both rails over shared
/// fixtures — see `docs/specs/headless-slice-parity.md` for the table.
abstract class HeadlessSlice {
  /// Map failed CI [runs] to headless signals (newest first is the
  /// caller's order — callers pass [DeploymentsService.timeline] output;
  /// this mapping preserves input order and never re-sorts).
  static List<HeadlessSignal> signalsFromCiRuns(List<DeployItem> runs) {
    final out = <HeadlessSignal>[];
    for (final r in runs) {
      try {
        if (r.status != 'failed') continue;
        final title = '${r.app} ${r.version}'.trim();
        if (title.isEmpty) continue;
        final owner = r.env.trim();
        if (owner.isEmpty) continue;
        out.add(HeadlessSignal(kind: 'ci', title: title, owner: owner));
      } catch (_) {
        // Hostile entries are skipped, never fatal.
      }
    }
    return out;
  }
}
