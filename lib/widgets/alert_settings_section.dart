// SPDX-License-Identifier: MIT
/// Alerts section for Settings (Nurul, frontend) — spec 06 §8 IA order.
///
/// Single source of row order: `AlertSettingsOrder.rows`. Rows:
/// 1. `background_alerts` — shared consent toggle (reuses the existing
///    `BackgroundAlertConsentTile`, default OFF);
/// 2. `severity_filter` — which severities toast (toasts only, the inbox
///    always collects everything);
/// 3. `quiet_hours` — OFF default, start/end pickers, summary label;
/// 4. `per_metric_thresholds` — disk warn/crit + brute-force warn/crit
///    steppers on `AlertRules` defaults (headless reuses verbatim);
/// 5. `battery_prompt` — Android/iOS platform explainer (existing copy);
/// 6. `last_checked` — read-only staleness line.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/alert_inbox_store.dart';
import '../services/alert_rules.dart';
import '../services/background_alerts.dart';
import '../theme/alert_tokens.dart';
import '../theme/app_theme.dart';
import 'alerts_staleness_line.dart';
import 'background_consent_tile.dart';
import 'pitch_card.dart';

/// Alerts settings section. Self-contained: loads + persists its own prefs
/// so any screen can drop it in. Order follows `AlertSettingsOrder.rows`.
class AlertSettingsSection extends StatefulWidget {
  /// Show the permission-denied banner (OS refused the prompt). The parent
  /// re-checks permission on every Settings open and clears it when granted.
  final bool notificationsDenied;

  /// Opens OS notification settings (deep link where the OS allows).
  final VoidCallback? onOpenOsSettings;

  const AlertSettingsSection({
    super.key,
    this.notificationsDenied = false,
    this.onOpenOsSettings,
  });

  @override
  State<AlertSettingsSection> createState() => _AlertSettingsSectionState();
}

class _AlertSettingsSectionState extends State<AlertSettingsSection> {
  bool _loading = true;
  bool _consent = false;
  String? _lastChecked;
  String _severity = AlertSettingsPrefs.severityCriticalOnly;
  QuietHours _quiet = const QuietHours();
  AlertRules _rules = const AlertRules();

  static bool get _isAndroid {
    try {
      return !const bool.fromEnvironment('dart.library.js_util') &&
          Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  static bool get _isIOS {
    try {
      return !const bool.fromEnvironment('dart.library.js_util') &&
          Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final consent = await BackgroundAlerts.isEnabled();
    final severity = await AlertSettingsPrefs.loadSeverity();
    final rules = await AlertSettingsPrefs.loadThresholds();
    final quiet = await _loadQuiet();
    final lastChecked = await BackgroundAlerts.lastCheckedLabel();
    if (!mounted) return;
    setState(() {
      _consent = consent;
      _severity = severity;
      _rules = rules;
      _quiet = quiet;
      _lastChecked = lastChecked;
      _loading = false;
    });
  }

  Future<QuietHours> _loadQuiet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(QuietHours.prefEnabledKey) ?? false;
      final start =
          prefs.getInt(QuietHours.prefStartKey) ?? QuietHours.defaultStartMinutes;
      final end =
          prefs.getInt(QuietHours.prefEndKey) ?? QuietHours.defaultEndMinutes;
      return QuietHours(
        startHour: start ~/ 60,
        startMinute: start % 60,
        endHour: end ~/ 60,
        endMinute: end % 60,
        enabled: enabled,
      );
    } catch (_) {
      return const QuietHours();
    }
  }

  Future<void> _saveQuiet(QuietHours q) async {
    setState(() => _quiet = q);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(QuietHours.prefEnabledKey, q.enabled);
      await prefs.setInt(QuietHours.prefStartKey, q.startMinutes);
      await prefs.setInt(QuietHours.prefEndKey, q.endMinutes);
    } catch (_) {}
  }

  Future<void> _setConsent(bool v) async {
    setState(() => _consent = v);
    await BackgroundAlerts.setEnabled(v);
    if (!mounted) return;
    if (!v) {
      // Opt-out confirmatory copy (spec §7.5) — no guilt, no re-prompt.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AlertCopy.optOutBody),
          duration: Duration(seconds: 4),
        ),
      );
    }
    if (v && _isAndroid) {
      // One-shot Android battery-exemption explainer (moved here with the
      // consent toggle from SettingsScreen; store-review red-flag avoidance
      // stays: the app never exempts itself, the user does it manually).
      final prefs = await SharedPreferences.getInstance();
      final prompted =
          prefs.getBool(BackgroundAlerts.prefBatteryPromptKey) ?? false;
      if (!prompted) {
        await prefs.setBool(BackgroundAlerts.prefBatteryPromptKey, true);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.surface1,
            title: const Text(
              BackgroundAlerts.batteryPromptTitle,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: const Text(
              BackgroundAlerts.batteryPromptBody,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentCyan,
                ),
                child: const Text(
                  'GOT IT',
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ],
          ),
        );
      }
    }
    final label = await BackgroundAlerts.lastCheckedLabel();
    if (!mounted) return;
    setState(() => _lastChecked = label);
  }

  Future<void> _setSeverity(String v) async {
    setState(() => _severity = v);
    await AlertSettingsPrefs.saveSeverity(v);
  }

  Future<void> _setRules(AlertRules r) async {
    setState(() => _rules = r);
    await AlertSettingsPrefs.saveThresholds(r);
  }

  Future<void> _pickQuietBound({required bool isStart}) async {
    final initial = isStart
        ? TimeOfDay(hour: _quiet.startHour, minute: _quiet.startMinute)
        : TimeOfDay(hour: _quiet.endHour, minute: _quiet.endMinute);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    await _saveQuiet(
      isStart
          ? QuietHours(
              startHour: picked.hour,
              startMinute: picked.minute,
              endHour: _quiet.endHour,
              endMinute: _quiet.endMinute,
              enabled: _quiet.enabled,
            )
          : QuietHours(
              startHour: _quiet.startHour,
              startMinute: _quiet.startMinute,
              endHour: picked.hour,
              endMinute: picked.minute,
              enabled: _quiet.enabled,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Assert the IA contract: this section renders every ordered row.
    assert(AlertSettingsOrder.rows.length == 6);
    if (_loading) {
      return const PitchCard(
        title: 'ALERTS',
        subtitle: 'Loading alert preferences…',
        child: SizedBox.shrink(),
      );
    }
    return PitchCard(
      title: 'ALERTS',
      subtitle: 'Toast + background-check preferences',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.notificationsDenied) _deniedBanner(),
          // 1. shared consent toggle (existing tile, verbatim copy)
          BackgroundAlertConsentTile(
            value: _consent,
            onChanged: _setConsent,
            lastCheckedLabel: _lastChecked,
            showBatteryTip: _isAndroid,
            showIosTip: _isIOS,
          ),
          const SizedBox(height: 4),
          // 2. severity filter (toasts only)
          _rowHeader('Toast severities', 'Inbox always collects everything.'),
          const SizedBox(height: 6),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: AlertSettingsPrefs.severityCriticalOnly,
                    label: Text('CRITICAL ONLY'),
                  ),
                  ButtonSegment(
                    value: AlertSettingsPrefs.severityAll,
                    label: Text('ALL'),
                  ),
                ],
                selected: {_severity},
                onSelectionChanged: (s) => _setSeverity(s.first),
                style: SegmentedButton.styleFrom(
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 3. quiet hours
          _rowHeader(
            'Quiet hours',
            _quiet.enabled
                ? 'Silent ${_quiet.label()} local — inbox still collects.'
                : 'Off — toasts fire on every fresh alert.',
          ),
          SwitchListTile(
            title: const Text(
              'Quiet hours',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              _quiet.label(),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            value: _quiet.enabled,
            activeThumbColor: AppColors.accentCyan,
            onChanged: (v) => _saveQuiet(
              QuietHours(
                startHour: _quiet.startHour,
                startMinute: _quiet.startMinute,
                endHour: _quiet.endHour,
                endMinute: _quiet.endMinute,
                enabled: v,
              ),
            ),
          ),
          if (_quiet.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _timeButton(
                      label: _two(_quiet.startHour, _quiet.startMinute),
                      semantic: 'Quiet hours start time',
                      onTap: () => _pickQuietBound(isStart: true),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '–',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  Expanded(
                    child: _timeButton(
                      label: _two(_quiet.endHour, _quiet.endMinute),
                      semantic: 'Quiet hours end time',
                      onTap: () => _pickQuietBound(isStart: false),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          // 4. per-metric thresholds (AlertRules defaults, headless verbatim)
          _rowHeader(
            'Thresholds',
            'Warn / critical lines for toast + inbox severity.',
          ),
          const SizedBox(height: 2),
          _stepper(
            label: 'Disk warn',
            value: '${(_rules.diskWarnAt * 100).round()}%',
            semantic: 'Disk warning threshold',
            onDown: _rules.diskWarnAt - 0.05 < 0.05
                ? null
                : () => _setRules(AlertRules(
                      diskWarnAt: _rules.diskWarnAt - 0.05,
                      diskCritAt: _rules.diskCritAt,
                      bruteWarnAt: _rules.bruteWarnAt,
                      bruteCritAt: _rules.bruteCritAt,
                    )),
            onUp: _rules.diskWarnAt + 0.05 >= _rules.diskCritAt
                ? null
                : () => _setRules(AlertRules(
                      diskWarnAt: _rules.diskWarnAt + 0.05,
                      diskCritAt: _rules.diskCritAt,
                      bruteWarnAt: _rules.bruteWarnAt,
                      bruteCritAt: _rules.bruteCritAt,
                    )),
          ),
          _stepper(
            label: 'Disk critical',
            value: '${(_rules.diskCritAt * 100).round()}%',
            semantic: 'Disk critical threshold',
            onDown: _rules.diskCritAt - 0.05 <= _rules.diskWarnAt
                ? null
                : () => _setRules(AlertRules(
                      diskWarnAt: _rules.diskWarnAt,
                      diskCritAt: _rules.diskCritAt - 0.05,
                      bruteWarnAt: _rules.bruteWarnAt,
                      bruteCritAt: _rules.bruteCritAt,
                    )),
            onUp: _rules.diskCritAt + 0.05 > 0.99
                ? null
                : () => _setRules(AlertRules(
                      diskWarnAt: _rules.diskWarnAt,
                      diskCritAt: _rules.diskCritAt + 0.05,
                      bruteWarnAt: _rules.bruteWarnAt,
                      bruteCritAt: _rules.bruteCritAt,
                    )),
          ),
          _stepper(
            label: 'SSH brute-force warn / 24h',
            value: '${_rules.bruteWarnAt}',
            semantic: 'Brute force warning count',
            onDown: _rules.bruteWarnAt - 1 < 1
                ? null
                : () => _setRules(AlertRules(
                      diskWarnAt: _rules.diskWarnAt,
                      diskCritAt: _rules.diskCritAt,
                      bruteWarnAt: _rules.bruteWarnAt - 1,
                      bruteCritAt: _rules.bruteCritAt,
                    )),
            onUp: _rules.bruteWarnAt + 1 >= _rules.bruteCritAt
                ? null
                : () => _setRules(AlertRules(
                      diskWarnAt: _rules.diskWarnAt,
                      diskCritAt: _rules.diskCritAt,
                      bruteWarnAt: _rules.bruteWarnAt + 1,
                      bruteCritAt: _rules.bruteCritAt,
                    )),
          ),
          _stepper(
            label: 'SSH brute-force critical / 24h',
            value: '${_rules.bruteCritAt}',
            semantic: 'Brute force critical count',
            onDown: _rules.bruteCritAt - 1 <= _rules.bruteWarnAt
                ? null
                : () => _setRules(AlertRules(
                      diskWarnAt: _rules.diskWarnAt,
                      diskCritAt: _rules.diskCritAt,
                      bruteWarnAt: _rules.bruteWarnAt,
                      bruteCritAt: _rules.bruteCritAt - 1,
                    )),
            onUp: _rules.bruteCritAt + 1 > 9999
                ? null
                : () => _setRules(AlertRules(
                      diskWarnAt: _rules.diskWarnAt,
                      diskCritAt: _rules.diskCritAt,
                      bruteWarnAt: _rules.bruteWarnAt,
                      bruteCritAt: _rules.bruteCritAt + 1,
                    )),
          ),
          // 5. platform explainer (existing verbatim copy)
          if (_isAndroid)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                BackgroundAlerts.batteryPromptBody,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          if (_isIOS)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                BackgroundAlerts.iosPromptBody,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          // 6. last-checked staleness line (read-only)
          if (_lastChecked != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: AlertsStalenessLine(label: _lastChecked!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deniedBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            AlertCopy.permissionDeniedHeadline,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            AlertCopy.permissionDeniedBody,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: widget.onOpenOsSettings,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentCyan,
              foregroundColor: Colors.black,
              minimumSize: const Size(48, 48),
            ),
            child: const Text(
              AlertCopy.permissionDeniedAction,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
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

  String _two(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  Widget _timeButton({
    required String label,
    required String semantic,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semantic,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontFamily: AppFonts.mono,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepper({
    required String label,
    required String value,
    required String semantic,
    required VoidCallback? onDown,
    required VoidCallback? onUp,
  }) {
    return Semantics(
      label: '$semantic: $value',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: IconButton(
                onPressed: onDown,
                icon: const Icon(Icons.remove, size: 16),
                color: AppColors.textSecondary,
                tooltip: 'Decrease $label',
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFamily: AppFonts.mono,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              child: IconButton(
                onPressed: onUp,
                icon: const Icon(Icons.add, size: 16),
                color: AppColors.textSecondary,
                tooltip: 'Increase $label',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
