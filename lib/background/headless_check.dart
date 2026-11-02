// SPDX-License-Identifier: MIT
/// Single shared headless check pipeline (TM-1, Lina owns).
///
/// This is THE check every rail runs: the shipped app binary with
/// `--poll-headless`, the CI harness (`dart run headless_check`), and —
/// by contract — any future scheduler wrapper. One pipeline, one verdict
/// table, no drift between the headless tick and the in-app rail.
///
/// Reused verbatim (never reimplemented):
/// - Gate + exit codes: [HeadlessSecurity] / `headlessExitOk|Error|Skipped`
///   (ADR-003: consent first, vault second; argv self-scan).
/// - Poll/backoff: [PollPolicy] (base 5 min → cap 1 h). The failure streak
///   persists in [HeadlessState.consecutiveFailures] so backoff survives
///   process restarts; an active backoff skips with exit 2 (no hot retry).
/// - Payload: [NotificationHook.build] (`{title, body}`, max 3 +
///   "…and N more") with the same `'MyControlPanel alert'` title string the
///   mobile rail uses in `BackgroundAlerts.buildLocalPayload`.
/// - Dedup identity: [HeadlessKeys.keyFor] (parity with `AlertWatch`).
///
/// Transition-only notify: only keys absent from the persisted seen-set —
/// and outside the resend cooldown — notify. The seen-set is REPLACED with
/// the current firing set (parity with `AlertWatch.markSeen`), so a
/// resolve→re-fire cycle notifies again while a steady firing state stays
/// silent.
///
/// Transport is injected ([fetchAll]) so this file stays pure-Dart
/// (`dart:async`/`dart:convert` + pure lib modules only): the Flutter
/// adapter (`lib/headless.dart`) passes real SSH/agent fetches, tests and
/// the CI harness pass fakes. This file never touches the network, the
/// vault, prefs, or plugins.
///
/// Stdout is machine-readable JSON ([HeadlessTickResult.toJson]); it carries
/// titles + counts only — never credentials, never markers (pinned by
/// `test/headless_check_test.dart`).
library;

import 'dart:async';
import 'dart:convert';

import '../models/alert_entry.dart';
import '../services/alert_rules.dart';
import '../services/headless_security.dart';
import '../services/polling_alerts.dart';
import 'headless_state.dart';

/// Aggregate transport: all signals across hosts in one call.
/// Throws only when *no* leg answered (mirrors `pollHostAlerts`).
typedef HeadlessFetchAll = Future<List<HeadlessSignal>> Function();

/// Delivery sink: (title, body) of the built [NotificationHook] payload.
/// Best-effort — a throwing sink never fails the tick.
typedef HeadlessNotify = Future<void> Function(String title, String body);

/// Outcome of one headless pipeline run.
class HeadlessTickResult {
  const HeadlessTickResult({
    required this.exitCode,
    required this.status,
    required this.checkedAtMs,
    this.freshTitles = const [],
    this.notification,
    this.reason,
    this.notified = false,
  });

  /// One of `headlessExitOk|Error|Skipped`.
  final int exitCode;

  /// 'ok' | 'notified' | 'skipped' | 'error'.
  final String status;
  final int checkedAtMs;
  final List<String> freshTitles;
  final Map<String, String>? notification;
  final String? reason;
  final bool notified;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'status': status,
        'exitCode': exitCode,
        'checkedAtMs': checkedAtMs,
        'freshTitles': freshTitles,
        'notification': notification,
        if (reason != null) 'reason': reason,
      };

  String toJsonString() => jsonEncode(toJson());
}

/// The shared headless check. Pure orchestration over injected I/O.
abstract class HeadlessCheck {
  /// Default resend cooldown (parity with `AlertPollJob.notifyCooldown`).
  static const resendCooldown = Duration(hours: 6);

  /// Notification title (parity with `BackgroundAlerts.showFresh`).
  static const notificationTitle = 'MyControlPanel alert';

  /// Run one tick. Never throws — every failure path is a result.
  /// [state] is mutated in place AND should be saved by the caller.
  static Future<HeadlessTickResult> run({
    required bool consentEnabled,
    required bool vaultUnlocked,
    required HeadlessState state,
    required HeadlessFetchAll fetchAll,
    required DateTime now,
    HeadlessNotify? onNotify,
    List<String> argv = const [],
    Duration notifyCooldown = resendCooldown,
    PollPolicy policy = const PollPolicy(),
  }) async {
    final atMs = now.millisecondsSinceEpoch;

    // Normalize working collections: default-constructed states carry
    // unmodifiable const collections; the pipeline mutates in place.
    state.seenKeys = Set<String>.of(state.seenKeys);
    state.lastSentMs = Map<String, int>.of(state.lastSentMs);

    // 0. Self-guard: a tampered scheduler artifact that smuggles secret
    // material in argv must fail loudly (exit 1), never poll.
    final argViolations = HeadlessSecurity.findSecretMaterialInArgs(argv);
    if (argViolations.isNotEmpty) {
      return HeadlessTickResult(
        exitCode: headlessExitError,
        status: 'error',
        checkedAtMs: atMs,
        reason: 'scheduler argv carries forbidden material '
            '(${argViolations.length} violation(s))',
      );
    }

    // 1. Consent/vault gate (ADR-003). Skips stamp nothing and notify
    // nothing — but the skipped *reason* is still machine-readable.
    final gate = HeadlessSecurity.evaluateHeadlessTick(
      consentEnabled: consentEnabled,
      vaultUnlocked: vaultUnlocked,
    );
    if (!gate.proceed) {
      return HeadlessTickResult(
        exitCode: gate.exitCode,
        status: 'skipped',
        checkedAtMs: atMs,
        reason: gate.reason,
      );
    }

    // 2. Backoff: a stored failure streak suppresses fetching until the
    // policy delay has elapsed since the last check (exit 2, T6).
    if (state.consecutiveFailures > 0 && state.lastCheckMs > 0) {
      final next = policy.nextDelay(state.consecutiveFailures);
      if (atMs - state.lastCheckMs < next.inMilliseconds) {
        return HeadlessTickResult(
          exitCode: headlessExitSkipped,
          status: 'skipped',
          checkedAtMs: atMs,
          reason: 'backoff active (${state.consecutiveFailures} '
              'consecutive failure(s))',
        );
      }
    }

    // 3. Fetch. Per-host sickness is the transport's business (it swallows
    // per-host errors); only a total failure throws here.
    late final List<HeadlessSignal> signals;
    try {
      signals = await fetchAll();
    } catch (_) {
      state.consecutiveFailures++;
      return HeadlessTickResult(
        exitCode: headlessExitError,
        status: 'error',
        checkedAtMs: atMs,
        reason: 'alert poll failed (agent + SSH both down)',
      );
    }

    // 4. Transition diff against the persisted seen-set.
    final currentKeys = <String>{};
    final keyToSignal = <String, HeadlessSignal>{};
    for (final s in signals) {
      try {
        currentKeys.add(s.key);
        keyToSignal.putIfAbsent(s.key, () => s);
      } catch (_) {
        // Hostile entries are skipped, never fatal (parity: unionAlerts).
      }
    }
    final freshKeys = currentKeys.difference(state.seenKeys);
    final cooledTitles = <String>[];
    for (final key in freshKeys) {
      final last = state.lastSentMs[key];
      if (last != null && atMs - last < notifyCooldown.inMilliseconds) {
        continue;
      }
      final signal = keyToSignal[key];
      if (signal == null) continue;
      final title = signal.displayTitle.trim();
      if (title.isEmpty) continue;
      state.lastSentMs[key] = atMs;
      cooledTitles.add(title);
    }

    // 5. Bookkeeping: replace the seen-set (parity: AlertWatch.markSeen),
    // reset the streak, stamp the check (T3: every tick stamps).
    state.seenKeys = currentKeys;
    state.consecutiveFailures = 0;
    state.lastCheckMs = atMs;

    if (cooledTitles.isEmpty) {
      return HeadlessTickResult(
        exitCode: headlessExitOk,
        status: 'ok',
        checkedAtMs: atMs,
      );
    }

    final payload =
        NotificationHook.build(notificationTitle, cooledTitles);
    if ((payload['body'] ?? '').isNotEmpty && onNotify != null) {
      try {
        await onNotify(payload['title']!, payload['body']!);
      } catch (_) {
        // Notification hooks are best-effort; the tick still counts.
      }
    }
    return HeadlessTickResult(
      exitCode: headlessExitOk,
      status: 'notified',
      checkedAtMs: atMs,
      freshTitles: cooledTitles,
      notification: payload,
      notified: true,
    );
  }

  /// Map firing [AlertEntry]s to signals (adapter helper — keeps the
  /// alert→signal mapping in exactly one place).
  static List<HeadlessSignal> signalsFromAlerts(List<AlertEntry> alerts) {
    final out = <HeadlessSignal>[];
    for (final a in alerts) {
      try {
        if (a.status != 'firing') continue;
        if (a.title.trim().isEmpty) continue;
        out.add(HeadlessSignal(
            kind: 'alert', title: a.title, owner: a.serverName));
      } catch (_) {}
    }
    return out;
  }

  /// Default production thresholds (single frozen table every rail shares).
  static const rules = AlertRules();
  static const thresholds = Thresholds();
  static const pollPolicy = PollPolicy();
}
