// SPDX-License-Identifier: MIT
/// Outbound channel routing section for Settings (Farah — ML).
///
/// Lives in the Alerts section right after quiet-hours
/// (`AlertSettingsOrder.rows` → `channel_routing`):
/// per-channel opt-in toggles (each default OFF, [AlertRouting.consentCopy]
/// verbatim), credential fields backed by [SecureStore] ONLY (values are
/// never displayed back — SET/HIDDEN like the Sentry DSN row), and the
/// per-severity + per-host routing-rule editor on [RoutingRule] shapes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../services/alert_routing.dart';
import '../services/secure_store.dart';
import '../theme/app_theme.dart';

/// Channel → secret fields (keychain/keystore ONLY, never prefs).
const Map<AlertChannel, List<(String, String)>> _channelSecrets = {
  AlertChannel.whatsapp: [
    (AlertRouting.whatsappWebhookSecretKey, 'Webhook relay URL'),
  ],
  AlertChannel.telegram: [
    (AlertRouting.telegramBotTokenSecretKey, 'Bot token'),
    (AlertRouting.telegramChatIdSecretKey, 'Chat ID'),
  ],
  AlertChannel.email: [
    (AlertRouting.emailWebhookSecretKey, 'Relay webhook URL'),
  ],
};

class AlertRoutingSection extends StatefulWidget {
  const AlertRoutingSection({super.key});

  @override
  State<AlertRoutingSection> createState() => _AlertRoutingSectionState();
}

class _AlertRoutingSectionState extends State<AlertRoutingSection> {
  bool _loading = true;
  final Map<AlertChannel, bool> _enabled = {
    for (final c in AlertChannel.values) c: false,
  };
  final Map<String, bool> _secretSet = {};
  final Map<String, TextEditingController> _secretCtrls = {};
  List<RoutingRule> _rules = [];
  final Map<String, TextEditingController> _hostCtrls = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _secretCtrls.values) {
      c.dispose();
    }
    for (final c in _hostCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final enabled = <AlertChannel, bool>{};
    for (final c in AlertChannel.values) {
      enabled[c] = await AlertRouting.isChannelEnabled(c);
    }
    final secretSet = <String, bool>{};
    for (final fields in _channelSecrets.values) {
      for (final (key, _) in fields) {
        final v = await SecureStore.readSecret(key);
        secretSet[key] = v != null && v.isNotEmpty;
      }
    }
    final rules = await AlertRouting.loadRules();
    if (!mounted) return;
    setState(() {
      _enabled.addAll(enabled);
      _secretSet.addAll(secretSet);
      _rules = rules;
      for (final r in _rules) {
        _hostCtrls[r.id] ??= TextEditingController(text: r.hostPattern);
      }
      _loading = false;
    });
  }

  Future<void> _setEnabled(AlertChannel channel, bool v) async {
    setState(() => _enabled[channel] = v);
    await AlertRouting.setChannelEnabled(channel, v);
  }

  Future<void> _saveSecret(String key) async {
    final ctrl = _secretCtrls[key];
    final v = (ctrl?.text ?? '').trim();
    if (v.isEmpty) return;
    await SecureStore.writeSecret(key, v);
    ctrl?.clear();
    if (!mounted) return;
    setState(() => _secretSet[key] = true);
  }

  Future<void> _clearSecret(String key) async {
    await SecureStore.deleteSecret(key);
    if (!mounted) return;
    setState(() => _secretSet[key] = false);
  }

  Future<void> _persistRules() async {
    await AlertRouting.saveRules(_rules);
  }

  void _addRule() {
    final id = const Uuid().v4();
    setState(() {
      _rules = [
        ..._rules,
        RoutingRule(id: id, channels: const {AlertChannel.telegram}),
      ];
      _hostCtrls[id] = TextEditingController();
    });
    unawaited(_persistRules());
  }

  void _updateRule(RoutingRule next) {
    setState(() {
      _rules = [for (final r in _rules) if (r.id == next.id) next else r];
    });
    unawaited(_persistRules());
  }

  void _deleteRule(String id) {
    setState(() {
      _rules = [for (final r in _rules) if (r.id != id) r];
      _hostCtrls.remove(id)?.dispose();
    });
    unawaited(_persistRules());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rowHeader(
          'Channel routing',
          'Forward firing + clearing alerts to WhatsApp / Telegram / email — '
          'in addition to toasts, never instead of them.',
        ),
        for (final channel in AlertChannel.values) ...[
          SwitchListTile(
            title: Text(
              channel.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              _enabled[channel]!
                  ? 'On — rules below decide what forwards.'
                  : 'Off — nothing leaves the device on this channel.',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            value: _enabled[channel]!,
            activeThumbColor: AppColors.accentCyan,
            onChanged: (v) => _setEnabled(channel, v),
          ),
          for (final (key, label) in _channelSecrets[channel]!)
            _secretRow(key: key, label: label, channel: channel.label),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            AlertRouting.consentCopy,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 6),
        _rowHeader(
          'Routing rules',
          'Empty severity = all severities. Empty host = all hosts.',
        ),
        for (var i = 0; i < _rules.length; i++) _ruleCard(_rules[i], i),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: OutlinedButton.icon(
            onPressed: _addRule,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add rule'),
          ),
        ),
      ],
    );
  }

  Widget _secretRow({
    required String key,
    required String label,
    required String channel,
  }) {
    final ctrl = _secretCtrls[key] ??= TextEditingController();
    final isSet = _secretSet[key] ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText:
                    '$channel $label${isSet ? ' (SET — enter a new value to replace)' : ''}',
                labelStyle: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints:
                const BoxConstraints(minWidth: 48, minHeight: 48),
            child: IconButton(
              onPressed: () => _saveSecret(key),
              icon: const Icon(Icons.save, size: 16),
              color: AppColors.textSecondary,
              tooltip: 'Save $channel $label to the keychain',
            ),
          ),
          ConstrainedBox(
            constraints:
                const BoxConstraints(minWidth: 48, minHeight: 48),
            child: IconButton(
              onPressed: isSet ? () => _clearSecret(key) : null,
              icon: const Icon(Icons.delete_outline, size: 16),
              color: AppColors.textSecondary,
              tooltip: 'Remove $channel $label from the keychain',
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleCard(RoutingRule rule, int index) {
    final hostCtrl = _hostCtrls[rule.id] ??= TextEditingController(
      text: rule.hostPattern,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Rule ${index + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              ConstrainedBox(
                constraints:
                    const BoxConstraints(minWidth: 48, minHeight: 48),
                child: IconButton(
                  onPressed: () => _deleteRule(rule.id),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  color: AppColors.textSecondary,
                  tooltip: 'Delete rule ${index + 1}',
                ),
              ),
            ],
          ),
          const Text(
            'Severities (none selected = all)',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final s in ['critical', 'warning', 'info'])
                FilterChip(
                  label: Text(s.toUpperCase(),
                      style: const TextStyle(fontSize: 11)),
                  selected: rule.severities.contains(s),
                  onSelected: (sel) {
                    final next = Set<String>.of(rule.severities);
                    if (sel) {
                      next.add(s);
                    } else {
                      next.remove(s);
                    }
                    _updateRule(RoutingRule(
                      id: rule.id,
                      severities: next,
                      hostPattern: hostCtrl.text,
                      channels: rule.channels,
                    ));
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: hostCtrl,
            onChanged: (v) => _updateRule(RoutingRule(
              id: rule.id,
              severities: rule.severities,
              hostPattern: v,
              channels: rule.channels,
            )),
            style: const TextStyle(
                fontSize: 12, color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Host contains (empty = all hosts)',
              labelStyle:
                  TextStyle(fontSize: 11, color: AppColors.textSecondary),
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Channels (none selected = rule sends nowhere)',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final c in AlertChannel.values)
                FilterChip(
                  label:
                      Text(c.label, style: const TextStyle(fontSize: 11)),
                  selected: rule.channels.contains(c),
                  onSelected: (sel) {
                    final next = Set<AlertChannel>.of(rule.channels);
                    if (sel) {
                      next.add(c);
                    } else {
                      next.remove(c);
                    }
                    _updateRule(RoutingRule(
                      id: rule.id,
                      severities: rule.severities,
                      hostPattern: hostCtrl.text,
                      channels: next,
                    ));
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rowHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
