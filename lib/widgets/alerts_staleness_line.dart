import 'package:flutter/material.dart';

import '../services/background_alerts.dart';
import '../theme/app_theme.dart';

/// "last checked Xm ago" stale-state line for the alerts surface.
///
/// The alerts card shows live foreground data, but the background rail (mobile
/// WorkManager / iOS BGTask, ≥15 min OS minimum) may be far older — this line
/// keeps that staleness honest, never silent (spec:
/// `docs/design/05-background-alerting.md` §4).
///
/// The [label] copy comes from [BackgroundAlerts.lastCheckedLabel] (pure
/// [BackgroundAlerts.formatLastChecked] underneath, unit-tested); this widget
/// only owns the presentation so it stays hermetic under widget tests —
/// no SharedPreferences, no full-screen pump.
class AlertsStalenessLine extends StatelessWidget {
  /// Pre-formatted line, e.g. `last checked 16 min ago`.
  final String label;

  const AlertsStalenessLine({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Background check status: $label',
      child: Row(
        children: [
          const Icon(
            Icons.schedule,
            size: 12,
            color: AppColors.textMuted,
            semanticLabel: 'Background check status',
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textMuted,
                fontFamily: AppFonts.mono,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
