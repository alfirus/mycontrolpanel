// SPDX-License-Identifier: MIT
/// Alert routing to outbound channels: WhatsApp / Telegram / email.
///
/// Today alerts reach OS toasts + the in-app inbox only. This file owns the
/// *routing* half of that gap: per-severity + per-host rules that forward
/// firing/clearing alerts to WhatsApp / Telegram / email **in addition to**
/// the existing rails (never instead of them).
///
/// Policy reuse (no new payload formats, no new consent model):
/// - Every user-visible payload is built by [NotificationHook.build]
///   (`{title, body}`, max 3 + "…and N more") — the same funnel the snack
///   bar, mobile rail and desktop rail share. [buildChannelPayload] is the
///   single choke point and is asserted `== NotificationHook.build` in
///   `test/alert_routing_test.dart`.
/// - Consent gating reuses the background-alerting contract: every outbound
///   channel is a separate opt-in pref, default OFF. No consent ⇒ no send,
///   never throws.
/// - Credential material lives in the OS keychain/keystore via
///   [SecureStore] ONLY (prefs hold `secure:` markers or nothing) — the
///   routing prefs carry rule shapes, never secrets.
/// - Dedupe reuses the atomic [AlertWatch] seen-set claim from PR #168:
///   the fan-out below MUST be called with the already-claimed fresh batch
///   (the winner's list). One claim = one delivery; the toast and the
///   channel message are two *presentations* of that single delivery. A
///   rail that loses the claim gets `[]` and stays silent on every rail —
///   see `AM-X1` in `test/alerting_matrix_test.dart`.
///
/// Quiet-hours parity: the production [defaultSender] drops sends while
/// [TrayQuietHours.suppressedNow] is active (notify-layer enforcement, same
/// as `DesktopAlerts.showFresh`). The pure [fanOutClaimed] path takes an
/// explicit `quietSuppressed` flag so tests stay hermetic.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_entry.dart';
import 'alert_watch.dart';
import 'polling_alerts.dart';
import 'secure_store.dart';
import '../tray/quiet_hours.dart';

/// Outbound channel an alert can be forwarded to.
enum AlertChannel { whatsapp, telegram, email }

/// Display label per channel (Settings toggles, logs — never a payload).
extension AlertChannelLabel on AlertChannel {
  String get label => switch (this) {
        AlertChannel.whatsapp => 'WhatsApp',
        AlertChannel.telegram => 'Telegram',
        AlertChannel.email => 'Email',
      };
}

/// One routing rule: which alerts go to which channels.
///
/// - [severities]: lower-cased `critical`/`warning`/`info` entries. Empty
///   means "all severities" (the default — a fresh rule fires on everything
///   until the user narrows it).
/// - [hostPattern]: `''` or `'*'` matches every host; otherwise a
///   case-insensitive substring match against `serverName` + `serverId`
///   (covers `web-01`, hostnames, and ids without a glob dialect).
/// - [channels]: empty means "no outbound channel" (rule is inert until at
///   least one channel is ticked — never an accidental send).
class RoutingRule {
  final String id;
  final Set<String> severities;
  final String hostPattern;
  final Set<AlertChannel> channels;

  const RoutingRule({
    required this.id,
    this.severities = const {},
    this.hostPattern = '',
    this.channels = const {},
  });

  /// True when [entry] rides this rule.
  bool matches(AlertEntry entry) {
    if (channels.isEmpty) return false;
    if (severities.isNotEmpty &&
        !severities.contains(entry.severity.toLowerCase())) {
      return false;
    }
    return AlertRouting.matchesHost(
      hostPattern: hostPattern,
      serverName: entry.serverName,
      serverId: entry.serverId,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'severities': severities.toList()..sort(),
        'host': hostPattern,
        'channels': [for (final c in channels) c.name]..sort(),
      };

  static RoutingRule fromJson(Map<String, Object?> json) {
    final rawSev = json['severities'];
    final sev = <String>{};
    if (rawSev is List) {
      for (final s in rawSev) {
        final v = s.toString().trim().toLowerCase();
        if (v == 'critical' || v == 'warning' || v == 'info') sev.add(v);
      }
    }
    final rawCh = json['channels'];
    final ch = <AlertChannel>{};
    if (rawCh is List) {
      for (final c in rawCh) {
        for (final known in AlertChannel.values) {
          if (known.name == c.toString().trim().toLowerCase()) ch.add(known);
        }
      }
    }
    return RoutingRule(
      id: (json['id'] ?? '').toString(),
      severities: sev,
      hostPattern: (json['host'] ?? '').toString(),
      channels: ch,
    );
  }
}

/// Routing table + consent prefs + channel fan-out.
abstract class AlertRouting {
  /// Persisted routing rules (JSON list). Shape only — never secrets.
  static const rulesKey = 'alert_routing_rules_v1';

  /// Per-channel consent prefs (each default OFF — explicit opt-in, same
  /// contract as `BackgroundAlerts.prefEnabledKey`).
  static const whatsappEnabledKey = 'alert_routing_whatsapp_enabled';
  static const telegramEnabledKey = 'alert_routing_telegram_enabled';
  static const emailEnabledKey = 'alert_routing_email_enabled';

  /// Consent copy (binding wording, shown under the Settings toggles).
  static const consentCopy =
      'Forward firing and clearing alerts to WhatsApp, Telegram, or email. '
      'Each channel is off until you turn it on.';

  /// SecureStore secret keys (keychain/keystore ONLY — never prefs).
  ///
  /// WhatsApp and email go through a user-provided webhook relay URL
  /// (Twilio / Cloud API proxy / mail relay — BYO relay, the app never
  /// ships a shared sender identity). Telegram uses a bot token + chat id
  /// pair posted straight at `api.telegram.org`.
  static const whatsappWebhookSecretKey = 'alert_routing_whatsapp_webhook';
  static const telegramBotTokenSecretKey = 'alert_routing_telegram_bot_token';
  static const telegramChatIdSecretKey = 'alert_routing_telegram_chat_id';
  static const emailWebhookSecretKey = 'alert_routing_email_webhook';

  static String consentKeyFor(AlertChannel channel) => switch (channel) {
        AlertChannel.whatsapp => whatsappEnabledKey,
        AlertChannel.telegram => telegramEnabledKey,
        AlertChannel.email => emailEnabledKey,
      };

  /// Pure: host-pattern match. `''`/`'*'` matches all; otherwise
  /// case-insensitive substring over `serverName` + `serverId`.
  static bool matchesHost({
    required String hostPattern,
    required String serverName,
    required String serverId,
  }) {
    final p = hostPattern.trim().toLowerCase();
    if (p.isEmpty || p == '*') return true;
    final hay = '${serverName.toLowerCase()} ${serverId.toLowerCase()}';
    return hay.contains(p);
  }

  /// Pure: channels an [entry] routes to under [rules] (consent NOT
  /// consulted here — the fan-out intersects with consent below).
  static Set<AlertChannel> matchChannels(
    List<RoutingRule> rules,
    AlertEntry entry,
  ) {
    final out = <AlertChannel>{};
    for (final rule in rules) {
      if (rule.matches(entry)) out.addAll(rule.channels);
    }
    return out;
  }

  /// Pure: group [entries] by outbound channel.
  static Map<AlertChannel, List<AlertEntry>> matchEntries(
    List<RoutingRule> rules,
    List<AlertEntry> entries,
  ) {
    final out = <AlertChannel, List<AlertEntry>>{};
    for (final entry in entries) {
      for (final channel in matchChannels(rules, entry)) {
        (out[channel] ??= []).add(entry);
      }
    }
    return out;
  }

  /// Pure: keep the candidate entries whose shared seen-set key is fresh.
  ///
  /// Rails call [AlertWatch.claimFreshTitles] first (the atomic exactly-once
  /// claim), then narrow the harvested entries to the winning keys with
  /// this helper before fanning out — so a toast + a channel message for
  /// the same firing is one delivery, two presentations.
  static List<AlertEntry> freshEntries(
    List<AlertEntry> candidates,
    Set<String> freshKeys,
  ) {
    return [
      for (final e in candidates)
        if (freshKeys.contains(
            AlertWatch.keyFor('alert', e.title, e.serverName)))
          e,
    ];
  }

  /// Single funnel for every outbound-channel payload: blank titles are
  /// dropped, then [NotificationHook.build] caps at 3 + "…and N more".
  /// Reuses policy/threshold types verbatim — no new payload formats.
  static Map<String, String> buildChannelPayload(
    String title,
    List<String> freshTitles,
  ) {
    final titles =
        freshTitles.where((t) => t.trim().isNotEmpty).toList();
    return NotificationHook.build(title, titles);
  }

  /// Display titles for [entries]: firing alerts verbatim, cleared ones
  /// prefixed so `…back to normal` reads honestly on a phone lock screen.
  static List<String> titlesFor(List<AlertEntry> entries) => [
        for (final e in entries)
          if (e.status == 'resolved')
            'Cleared: ${e.title} (${e.serverName})'
          else
            '${e.title} (${e.serverName})',
      ];

  /// Whether the user opted into [channel] (default OFF).
  static Future<bool> isChannelEnabled(AlertChannel channel) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(consentKeyFor(channel)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Persist one channel's opt-in. Safe anywhere (never throws).
  static Future<void> setChannelEnabled(
      AlertChannel channel, bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(consentKeyFor(channel), enabled);
    } catch (_) {}
  }

  /// True when at least one outbound channel is opted in.
  static Future<bool> areAnyChannelsEnabled() async {
    for (final channel in AlertChannel.values) {
      if (await isChannelEnabled(channel)) return true;
    }
    return false;
  }

  /// Load persisted rules (corrupt rows are skipped, never fatal).
  static Future<List<RoutingRule>> loadRules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(rulesKey);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final out = <RoutingRule>[];
      for (final item in list) {
        if (item is Map<String, Object?>) {
          final rule = RoutingRule.fromJson(item);
          if (rule.id.isNotEmpty) out.add(rule);
        } else if (item is Map) {
          final rule = RoutingRule.fromJson(
              item.map((k, v) => MapEntry(k.toString(), v)));
          if (rule.id.isNotEmpty) out.add(rule);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Persist rules (shape only — callers must never put secrets here).
  static Future<void> saveRules(List<RoutingRule> rules) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          rulesKey, jsonEncode([for (final r in rules) r.toJson()]));
    } catch (_) {}
  }
}

/// Injectable channel sender (tests pin this; production passes
/// [AlertRoutingFanout.defaultSender]).
///
/// [payload] is the verbatim `NotificationHook.build` map; [entries] are
/// the matched firing/clearing alerts behind it. Returns true when the
/// channel accepted the message.
typedef ChannelSender = Future<bool> Function(
  AlertChannel channel,
  Map<String, String> payload,
  List<AlertEntry> entries,
);

/// Fan-out over already-claimed fresh alerts.
abstract class AlertRoutingFanout {
  /// Forward the winner's [fresh] entries (already narrowed via
  /// [AlertRouting.freshEntries]) to every matched + consented channel.
  ///
  /// - [rules]: routing table (prefs-loaded by callers via
  ///   [AlertRouting.loadRules]).
  /// - [enabled]: consented channels (subset of [AlertChannel.values]).
  /// - [sender]: transport (production: [defaultSender]).
  /// - [quietSuppressed]: notify-layer suppression (production reads
  ///   `TrayQuietHours.suppressedNow()`; tests pass an explicit bool).
  ///
  /// Returns the per-channel payloads that were accepted. Never throws —
  /// one sick channel never sinks its siblings.
  static Future<Map<AlertChannel, Map<String, String>>> fanOutClaimed({
    required List<AlertEntry> fresh,
    required List<RoutingRule> rules,
    required Set<AlertChannel> enabled,
    required ChannelSender sender,
    bool quietSuppressed = false,
  }) async {
    final sent = <AlertChannel, Map<String, String>>{};
    if (fresh.isEmpty || enabled.isEmpty || quietSuppressed) return sent;
    final byChannel = AlertRouting.matchEntries(rules, fresh);
    for (final entry in byChannel.entries) {
      final channel = entry.key;
      if (!enabled.contains(channel)) continue;
      final payload = AlertRouting.buildChannelPayload(
        'MyControlPanel alert',
        AlertRouting.titlesFor(entry.value),
      );
      if ((payload['body'] ?? '').isEmpty) continue;
      try {
        if (await sender(channel, payload, entry.value)) {
          sent[channel] = payload;
        }
      } catch (_) {
        // One sick channel never sinks its siblings.
      }
    }
    return sent;
  }

  /// Prefs + consent + quiet-hours loading wrapper around [fanOutClaimed]
  /// for production rails. Best-effort, never throws.
  static Future<Map<AlertChannel, Map<String, String>>> fanOut({
    required List<AlertEntry> fresh,
    ChannelSender sender = defaultSender,
  }) async {
    try {
      if (fresh.isEmpty) return const {};
      final rules = await AlertRouting.loadRules();
      if (rules.isEmpty) return const {};
      final enabled = <AlertChannel>{};
      for (final channel in AlertChannel.values) {
        if (await AlertRouting.isChannelEnabled(channel)) {
          enabled.add(channel);
        }
      }
      if (enabled.isEmpty) return const {};
      bool quiet = false;
      try {
        quiet = await TrayQuietHours.suppressedNow();
      } catch (_) {
        quiet = false;
      }
      return await fanOutClaimed(
        fresh: fresh,
        rules: rules,
        enabled: enabled,
        sender: sender,
        quietSuppressed: quiet,
      );
    } catch (_) {
      return const {};
    }
  }

  /// Production transport: reads per-channel secrets from [SecureStore]
  /// (keychain/keystore ONLY), POSTs the verbatim payload, returns false
  /// when consent is off, the secret is missing, or the POST fails.
  /// Never throws.
  static Future<bool> defaultSender(
    AlertChannel channel,
    Map<String, String> payload,
    List<AlertEntry> entries,
  ) async {
    try {
      if (!await AlertRouting.isChannelEnabled(channel)) return false;
      final title = payload['title'] ?? '';
      final body = payload['body'] ?? '';
      if (body.trim().isEmpty) return false;
      switch (channel) {
        case AlertChannel.telegram:
          final token = await SecureStore.readSecret(
              AlertRouting.telegramBotTokenSecretKey);
          final chatId = await SecureStore.readSecret(
              AlertRouting.telegramChatIdSecretKey);
          if (token == null ||
              token.isEmpty ||
              chatId == null ||
              chatId.isEmpty) {
            return false;
          }
          return await _postJson(
            Uri.parse(
                'https://api.telegram.org/bot$token/sendMessage'),
            {'chat_id': chatId, 'text': '$title\n$body'},
          );
        case AlertChannel.whatsapp:
          final webhook = await SecureStore.readSecret(
              AlertRouting.whatsappWebhookSecretKey);
          if (webhook == null || webhook.isEmpty) return false;
          return await _postJson(
            Uri.parse(webhook),
            {'title': title, 'body': body},
          );
        case AlertChannel.email:
          final webhook = await SecureStore.readSecret(
              AlertRouting.emailWebhookSecretKey);
          if (webhook == null || webhook.isEmpty) return false;
          return await _postJson(
            Uri.parse(webhook),
            {'subject': title, 'body': body},
          );
      }
    } catch (_) {
      return false;
    }
  }

  /// Best-effort JSON POST (15 s cap). False on any failure.
  static Future<bool> _postJson(
      Uri uri, Map<String, String> fields) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final req = await client.postUrl(uri).timeout(
            const Duration(seconds: 15),
          );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(fields));
      final resp = await req.close().timeout(
            const Duration(seconds: 15),
          );
      await resp.drain<void>();
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      try {
        client?.close(force: true);
      } catch (_) {}
    }
  }
}
