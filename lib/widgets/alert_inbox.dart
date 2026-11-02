// SPDX-License-Identifier: MIT
/// Alerts Inbox UI (Nurul, frontend) — build-ready half of
/// `docs/design/06-alert-tray-ux.md` §4/§6/§9.
///
/// Filterable history (All/Unread/Critical), swipe ack/snooze, Alert Detail
/// sheet (metric snapshot + stale badge + open-host), notification-tap
/// landing (highlight key). All copy/tokens come from `alert_tokens.dart`
/// verbatim; grouping/order/staleness from `alert_inbox_store.dart`.
library;

import 'package:flutter/material.dart';

import '../services/alert_inbox_store.dart';
import '../theme/alert_tokens.dart';
import '../theme/app_theme.dart';
import 'alerts_staleness_line.dart';
import 'state_view.dart';

/// Severity → Material icon (name-stable strings in `AppAlertTokens.icon`).
IconData severityIcon(TrayAlertSeverity severity) => switch (severity) {
      TrayAlertSeverity.critical => Icons.error_outline,
      TrayAlertSeverity.warning => Icons.warning_amber,
      TrayAlertSeverity.info => Icons.info_outline,
    };

/// Severity pill: colored dot + uppercase label + semantic name.
/// Color is never the only cue (spec §9.1).
class AlertSeverityPill extends StatelessWidget {
  final TrayAlertSeverity severity;
  final bool compact;

  const AlertSeverityPill({
    super.key,
    required this.severity,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppAlertTokens.color[severity]!;
    final label = AppAlertTokens.pill[severity]!;
    return Semantics(
      label: AppAlertTokens.semanticLabel[severity],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: compact ? 9 : 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Filter chips (All / Unread / Critical). 48px targets, live count badges,
/// semantic names — never filter-state by color alone (spec §9).
class AlertInboxFilterBar extends StatelessWidget {
  final InboxFilter value;
  final ValueChanged<InboxFilter> onChanged;
  final int unread;
  final int critical;

  const AlertInboxFilterBar({
    super.key,
    required this.value,
    required this.onChanged,
    this.unread = 0,
    this.critical = 0,
  });

  int _badgeFor(InboxFilter f) => switch (f) {
        InboxFilter.unread => unread,
        InboxFilter.critical => critical,
        InboxFilter.all => 0,
      };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Filter alerts',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in InboxFilter.values)
            _chip(context, f, _badgeFor(f)),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, InboxFilter f, int badge) {
    final selected = f == value;
    final accent = f == InboxFilter.critical
        ? AppAlertTokens.color[TrayAlertSeverity.critical]!
        : AppColors.accentCyan;
    return Semantics(
      label: f.semanticLabel,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () => onChanged(f),
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.14)
                  : AppColors.surface1,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? accent : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.check, size: 14, color: accent),
                  ),
                Text(
                  f.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: selected ? accent : AppColors.textSecondary,
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One inbox row: swipe right → ack, swipe left → snooze 1h (spec §6).
/// Tap → detail sheet. Stale rows carry a STALE badge and sink (spec §4.4).
class AlertInboxRow extends StatelessWidget {
  final InboxItem item;
  final Future<void> Function()? onAck;
  final Future<void> Function()? onSnooze;
  final void Function()? onOpen;
  final bool highlighted;

  const AlertInboxRow({
    super.key,
    required this.item,
    this.onAck,
    this.onSnooze,
    this.onOpen,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppAlertTokens.color[item.traySeverity]!;
    final semantic =
        '${AppAlertTokens.semanticLabel[item.traySeverity]}: ${item.entry.title} on ${item.entry.serverName}'
        '${item.stale ? ', stale' : ''}${item.seen ? '' : ', unread'}';
    final row = Semantics(
      label: semantic,
      button: true,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: highlighted
                ? AppColors.accentCyan.withValues(alpha: 0.08)
                : AppColors.surface1,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: highlighted
                  ? AppColors.accentCyan.withValues(alpha: 0.5)
                  : item.traySeverity == TrayAlertSeverity.critical
                      ? color.withValues(alpha: 0.3)
                      : AppColors.borderLight,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!item.seen)
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  severityIcon(item.traySeverity),
                  size: 15,
                  color: color,
                  semanticLabel:
                      AppAlertTokens.semanticLabel[item.traySeverity],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.entry.title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${item.entry.source} • ${item.entry.serverName}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AlertSeverityPill(
                          severity: item.traySeverity,
                          compact: true,
                        ),
                        if (item.stale)
                          Semantics(
                            label: 'Stale: not re-fired recently',
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warning
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.warning
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                              child: const Text(
                                'STALE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                  color: AppColors.warning,
                                ),
                              ),
                            ),
                          ),
                        if (item.snoozedUntilMs != null)
                          const Text(
                            'SNOOZED 1H',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey('inbox-${item.key}'),
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 16),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, size: 18, color: AppColors.success),
              SizedBox(width: 6),
              Text(
                'ACK',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'SNOOZE 1H',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.warning,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.snooze, size: 18, color: AppColors.warning),
            ],
          ),
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await onAck?.call();
          } else {
            await onSnooze?.call();
          }
          return false; // row stays — ack/snooze never delete the row
        },
        child: row,
      ),
    );
  }
}

/// Full inbox surface: filters + staleness + list + StateView frames.
/// Responsive: single scrolling list, content capped at 720px on wide
/// layouts so rows never stretch edge-to-edge on desktop (spec §9.7).
class AlertsInboxView extends StatelessWidget {
  final List<InboxItem> items;
  final InboxFilter filter;
  final ValueChanged<InboxFilter> onFilterChanged;
  final bool loading;
  final String? error;
  final String? staleLabel;
  final String? highlightedKey;
  final Future<void> Function(InboxItem item)? onAck;
  final Future<void> Function(InboxItem item)? onSnooze;
  final void Function(InboxItem item)? onOpen;
  final Future<void> Function()? onRetry;

  const AlertsInboxView({
    super.key,
    required this.items,
    required this.filter,
    required this.onFilterChanged,
    this.loading = false,
    this.error,
    this.staleLabel,
    this.highlightedKey,
    this.onAck,
    this.onSnooze,
    this.onOpen,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final visible = filterInbox(items, filter);
    final critical =
        items.where((i) => i.traySeverity == TrayAlertSeverity.critical).length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 700;
        final body = ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: wide ? 720 : constraints.maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AlertInboxFilterBar(
                value: filter,
                onChanged: onFilterChanged,
                unread: unreadCount(items),
                critical: critical,
              ),
              if (staleLabel != null) ...[
                const SizedBox(height: 8),
                AlertsStalenessLine(label: staleLabel!),
              ],
              const SizedBox(height: 8),
              if (loading && items.isEmpty)
                StateView(
                  state: PanelState.loading,
                  loadingLabel: AlertA11y.loadingAnnouncement,
                )
              else if (error != null && items.isEmpty)
                StateView(
                  state: PanelState.error,
                  headline: 'SYNC FAILED',
                  body: AlertA11y.errorAnnouncement,
                  actionLabel: 'RETRY',
                  onAction: onRetry == null
                      ? null
                      : () {
                          onRetry!.call();
                        },
                )
              else if (visible.isEmpty)
                const StateView(
                  state: PanelState.empty,
                  headline: AlertCopy.inboxClearHeadline,
                  body: AlertCopy.inboxClearBody,
                  semanticLabel: 'No alerts. All clear.',
                )
              else
                Semantics(
                  label: '${visible.length} alerts shown',
                  child: Column(
                    children: [
                      for (final item in visible)
                        AlertInboxRow(
                          key: ValueKey('row-${item.key}'),
                          item: item,
                          highlighted: item.key == highlightedKey,
                          onAck: onAck == null
                              ? null
                              : () => onAck!.call(item),
                          onSnooze: onSnooze == null
                              ? null
                              : () => onSnooze!.call(item),
                          onOpen:
                              onOpen == null ? null : () => onOpen!.call(item),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
        if (wide) return SingleChildScrollView(child: Center(child: body));
        return SingleChildScrollView(child: body);
      },
    );
  }
}

/// Metric snapshot line in the detail sheet (label + value, ≥11px
/// `textSecondary` — never `textMuted`, spec §9.2).
class _SnapshotLine extends StatelessWidget {
  final String label;
  final String value;

  const _SnapshotLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textPrimary,
                fontFamily: AppFonts.mono,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Alert Detail sheet content: metric snapshot + stale badge + actions.
/// [onOpenHost] navigates to the host (server details); [onAck]/[onSnooze]
/// triage without leaving the sheet.
class AlertDetailSheet extends StatelessWidget {
  final InboxItem item;
  final String? staleLabel;
  final Future<void> Function()? onAck;
  final Future<void> Function()? onSnooze;
  final void Function()? onOpenHost;

  const AlertDetailSheet({
    super.key,
    required this.item,
    this.staleLabel,
    this.onAck,
    this.onSnooze,
    this.onOpenHost,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppAlertTokens.color[item.traySeverity]!;
    return Semantics(
      label:
          '${AppAlertTokens.semanticLabel[item.traySeverity]} detail: ${item.entry.title}',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  severityIcon(item.traySeverity),
                  size: 20,
                  color: color,
                  semanticLabel:
                      AppAlertTokens.semanticLabel[item.traySeverity],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.entry.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                AlertSeverityPill(severity: item.traySeverity),
                if (item.stale)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Text(
                      'STALE — NOT RE-FIRED RECENTLY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'METRIC SNAPSHOT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            _SnapshotLine(label: 'Signal', value: item.entry.source),
            _SnapshotLine(label: 'Host', value: item.entry.serverName),
            _SnapshotLine(label: 'Status', value: item.entry.status),
            if (staleLabel != null)
              _SnapshotLine(label: 'Checked', value: staleLabel!),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onAck == null
                  ? null
                  : () async {
                      await onAck!.call();
                      if (context.mounted) Navigator.pop(context);
                    },
              icon: const Icon(Icons.check, size: 16),
              label: const Text(
                'ACKNOWLEDGE',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentCyan,
                foregroundColor: Colors.black,
                minimumSize: const Size(48, 48),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSnooze == null
                        ? null
                        : () async {
                            await onSnooze!.call();
                            if (context.mounted) Navigator.pop(context);
                          },
                    icon: const Icon(Icons.snooze, size: 16),
                    label: const Text(
                      'SNOOZE 1H',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      minimumSize: const Size(48, 48),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenHost == null
                        ? null
                        : () {
                            Navigator.pop(context);
                            onOpenHost!.call();
                          },
                    icon: const Icon(Icons.dns, size: 16),
                    label: const Text(
                      'OPEN HOST',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accentCyan,
                      side: BorderSide(
                        color: AppColors.accentCyan.withValues(alpha: 0.4),
                      ),
                      minimumSize: const Size(48, 48),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Show the detail sheet: modal bottom sheet on narrow layouts, centered
/// dialog on wide ones (Esc closes the dialog and returns focus, §9.6).
Future<void> showAlertDetailSheet(
  BuildContext context, {
  required InboxItem item,
  String? staleLabel,
  Future<void> Function()? onAck,
  Future<void> Function()? onSnooze,
  void Function()? onOpenHost,
}) {
  final sheet = AlertDetailSheet(
    item: item,
    staleLabel: staleLabel,
    onAck: onAck,
    onSnooze: onSnooze,
    onOpenHost: onOpenHost,
  );
  final wide = MediaQuery.of(context).size.width > 700;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.surface0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: sheet,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      side: BorderSide(color: AppColors.border),
    ),
    builder: (_) => SafeArea(child: sheet),
  );
}
