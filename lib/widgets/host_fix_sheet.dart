// SPDX-License-Identifier: MIT
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/alert_entry.dart';
import '../services/audit_log.dart';
import '../services/run_actions.dart';
import '../theme/app_theme.dart';
import 'single_toast.dart';

/// Runs one approved host-fix command over SSH. Injected so the
/// approve-first flow is widget-testable without a live server.
typedef HostFixRunner = Future<String> Function(String command);

/// One-click remediation for a firing alert, behind the same
/// approve-first pattern as the run detail sheet: tapping a fix reveals
/// an inline confirm step with dry-run preview copy — nothing executes
/// without the second tap. Approved runs are audit-logged and the
/// result lands on the single-toast rail.
Future<void> showHostFixSheet({
  required BuildContext context,
  required AlertEntry alert,
  required HostFixRunner runner,
  required VoidCallback onChanged,
  String auditProvider = 'local',
  String auditModel = 'host-fix-sheet',
}) {
  final actions = HostFixes.actionsFor(alert);
  HostFixAction? pending;
  bool busy = false;
  String? error;

  Future<void> execute(
    BuildContext ctx,
    void Function(void Function()) setD,
    HostFixAction action,
  ) async {
    final unit = HostFixes.unitFor(alert);
    setD(() { busy = true; error = null; });
    final sw = Stopwatch()..start();
    try {
      final out = await runner(HostFixes.commandFor(action, unit: unit));
      sw.stop();
      if (!ctx.mounted) return;
      unawaited(AuditLog.record(
        tool: 'host_fix.${action.name}',
        args: {
          'server': alert.serverName,
          'alert': alert.title,
          if (unit != null) 'unit': unit,
        },
        decision: 'approved',
        result: out,
        provider: auditProvider,
        model: auditModel,
        durationMs: sw.elapsedMilliseconds,
      ));
      Navigator.pop(ctx, true);
      showSingleToast(
        context,
        '${HostFixes.label(action)} on ${alert.serverName} ✓',
        foreground: AppColors.success,
      );
      onChanged();
    } catch (e) {
      sw.stop();
      if (!ctx.mounted) return;
      unawaited(AuditLog.record(
        tool: 'host_fix.${action.name}',
        args: {
          'server': alert.serverName,
          'alert': alert.title,
          if (unit != null) 'unit': unit,
        },
        decision: 'approved',
        result: 'failed: ${e.toString().split('\n').first}',
        provider: auditProvider,
        model: auditModel,
        durationMs: sw.elapsedMilliseconds,
      ));
      setD(() {
        busy = false;
        error = e.toString().replaceFirst('Exception: ', '').split('\n').first;
      });
    }
  }

  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      return AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border)),
        title: Row(children: [
          Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7)),
              child: const Icon(Icons.build_outlined,
                  size: 15, color: AppColors.warning)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(alert.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Text(
                    '${alert.severity.toUpperCase()} • ${alert.serverName}',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textMuted)),
              ])),
          IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted)),
        ]),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (actions.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                    'No one-click fix for this alert — resolve it from the terminal.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(error!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.critical)),
              ),
            if (pending != null && !busy)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(HostFixes.confirmText(pending!, alert),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.warning)),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('CLOSE',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMuted))),
          for (final a in actions)
            pending == a
                ? FilledButton(
                    onPressed: busy ? null : () => execute(ctx, setD, a),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentCyan,
                        foregroundColor: Colors.black),
                    child: busy
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : Text('CONFIRM ${HostFixes.label(a)}',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                  )
                : OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => setD(() { pending = a; error = null; }),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accentCyan,
                        side: const BorderSide(
                            color: AppColors.accentCyan)),
                    child: Text(HostFixes.label(a),
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
        ],
      );
    }),
  );
}
