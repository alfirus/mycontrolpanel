import 'package:flutter/material.dart';

import '../services/background_alerts.dart';
import '../theme/app_theme.dart';

/// Settings toggle for mobile background alerting (beta.1).
///
/// Extracted as a standalone widget so the consent contract (default OFF +
/// explicit copy) is covered by a hermetic widget test — no full
/// SettingsScreen pump needed.
///
/// [value] is the persisted `background_alerts` pref (default false).
/// [onChanged] persists + schedules/cancels (owned by the parent).
/// [lastCheckedLabel] is the stale-tolerant status line, shown only when
/// the toggle is ON; [showBatteryTip]/[showIosTip] select the platform
/// explainer.
class BackgroundAlertConsentTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? lastCheckedLabel;
  final bool showBatteryTip;
  final bool showIosTip;

  const BackgroundAlertConsentTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.lastCheckedLabel,
    this.showBatteryTip = false,
    this.showIosTip = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text(
            'Background alerts',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: const Text(
            BackgroundAlerts.consentCopy,
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          value: value,
          activeThumbColor: AppColors.accentCyan,
          onChanged: onChanged,
        ),
        if (value) ...[
          if (lastCheckedLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                lastCheckedLabel!,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontFamily: AppFonts.mono,
                ),
              ),
            ),
          if (showBatteryTip)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                BackgroundAlerts.batteryPromptBody,
                style: TextStyle(fontSize: 10, color: AppColors.textMuted),
              ),
            ),
          if (showIosTip)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                BackgroundAlerts.iosPromptBody,
                style: TextStyle(fontSize: 10, color: AppColors.textMuted),
              ),
            ),
        ],
      ],
    );
  }
}
