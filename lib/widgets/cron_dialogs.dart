import 'package:flutter/material.dart';
import '../models/cron_entry.dart';
import '../models/server_connection.dart';
import '../services/agent_service.dart';
import '../services/cron_runs.dart';
import '../services/ssh_key_loader.dart';
import '../theme/app_theme.dart';
import 'pitch_card.dart';

/// Returns (proceed, passphrase). Skips the prompt entirely when the saved
/// key loads without one — an unencrypted key must never trigger a dialog.
Future<(bool, String?)> _resolvePassphrase(
  ServerConnection conn,
  Future<String?> Function() askPassphrase,
) async {
  if (conn.authMethod == AuthMethod.password) return (true, null);
  final pre = await SshKeyLoader.load(conn.credential);
  if (pre.keys != null) return (true, null);
  if (!pre.needsPassphrase) throw Exception(pre.error ?? 'key load failed');
  final pass = await askPassphrase();
  if (pass == null || pass.isEmpty) return (false, null);
  return (true, pass);
}

/// Tap a cronjob → LOG / EDIT. Shared by Overview, Cronjobs tab, Server Details.
Future<void> showCronActions(
  BuildContext context, {
  required CronEntry entry,
  required ServerConnection conn,
  required AgentService agent,
  required Future<String?> Function() askPassphrase,
  required VoidCallback onChanged,
  VoidCallback? onBadPassphrase,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      title: Row(children: [
        Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.accentPurple.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.schedule_outlined, size: 15, color: AppColors.accentPurple)),
        const SizedBox(width: 10),
        Expanded(child: Text(entry.command, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: AppFonts.mono))),
        IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted)),
      ]),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 4, children: [
            Text(entry.schedule, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accentCyan, fontFamily: AppFonts.mono)),
            Text(entry.source, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: AppFonts.mono)),
            Pill(text: entry.serverName.toUpperCase(), color: AppColors.accentBlue),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await Future.delayed(const Duration(milliseconds: 350));
                if (context.mounted) {
                  showCronLog(context, entry: entry, conn: conn, agent: agent, askPassphrase: askPassphrase, onBadPassphrase: onBadPassphrase);
                }
              },
              icon: const Icon(Icons.terminal, size: 14),
              label: const Text('VIEW LOG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 11)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await Future.delayed(const Duration(milliseconds: 350));
                if (context.mounted) {
                  showCronEdit(context, entry: entry, conn: conn, agent: agent, askPassphrase: askPassphrase, onChanged: onChanged, onBadPassphrase: onBadPassphrase);
                }
              },
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: const Text('EDIT SCHEDULE / COMMAND', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.textPrimary, side: const BorderSide(color: AppColors.border), padding: const EdgeInsets.symmetric(vertical: 11)),
            ),
          ),
        ]),
      ),
    ),
  );
}

Future<void> showCronLog(
  BuildContext context, {
  required CronEntry entry,
  required ServerConnection conn,
  required AgentService agent,
  required Future<String?> Function() askPassphrase,
  VoidCallback? onBadPassphrase,
}) async {
  String? log;
  String? error;
  bool loading = true;
  bool started = false;
  void noteBadPass(String e) {
    if (e.contains('Passphrase not accepted')) onBadPassphrase?.call();
  }
  // Kicked off post-frame (never during build): the fetch — and the
  // passphrase dialog it may open — must not run inside this builder.
  // setD is only called from post-frame callbacks or event handlers
  // (never during build), each guarded by the dialog context's mounted.
  Future<void> load(BuildContext c, void Function(void Function()) setD) async {
    if (!c.mounted) return;
    setD(() { loading = true; log = null; error = null; });
    try {
      final (proceed, pass) = await _resolvePassphrase(conn, askPassphrase);
      if (!c.mounted) return;
      if (!proceed) {
        setD(() { loading = false; error = 'Passphrase required — cancelled.'; });
        return;
      }
      final out = await agent.fetchCronLogs(conn, entry, keyPassphrase: pass);
      if (!c.mounted) return;
      setD(() { loading = false; log = out; });
    } catch (e) {
      if (!c.mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').split('\n').first;
      noteBadPass(msg);
      setD(() {
        loading = false;
        error = msg;
      });
    }
  }

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      final lastRun =
          log == null ? null : CronRuns.parse(command: entry.command, logText: log!);
      if (!started) {
        started = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ctx.mounted) load(ctx, setD);
        });
      }
      return AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
        title: Row(children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.accentCyan.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.terminal, size: 15, color: AppColors.accentCyan)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('LOG • ${entry.command}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: AppFonts.mono)),
            Text('${conn.name} • last 7 days', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            if (lastRun != null)
              Text(
                lastRun.caption(DateTime.now()),
                style: TextStyle(fontSize: 10, color: lastRun.known ? AppColors.success : AppColors.textMuted),
              ),
          ])),
          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted)),
        ]),
        content: SizedBox(
          width: 460,
          height: 380,
          child: loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.accentCyan))
              : error != null
                  ? SingleChildScrollView(child: SelectableText('Error: $error', style: const TextStyle(fontSize: 11, color: AppColors.critical, fontFamily: AppFonts.mono)))
                  : Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFF050505), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                      child: SingleChildScrollView(child: SelectableText(log!, style: const TextStyle(fontSize: 10, height: 1.4, color: Color(0xFFE4E4E7), fontFamily: AppFonts.mono))),
                    ),
        ),
        actions: [
          TextButton(
            onPressed: loading ? null : () => load(ctx, setD),
            child: const Text('REFRESH', style: TextStyle(color: AppColors.accentCyan, fontWeight: FontWeight.w800)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE', style: TextStyle(color: AppColors.textSecondary))),
        ],
      );
    }),
  );
}

Future<void> showCronEdit(
  BuildContext context, {
  required CronEntry entry,
  required ServerConnection conn,
  required AgentService agent,
  required Future<String?> Function() askPassphrase,
  required VoidCallback onChanged,
  VoidCallback? onBadPassphrase,
}) {
  final schedCtrl = TextEditingController(text: entry.schedule);
  final cmdCtrl = TextEditingController(text: entry.command);
  final formKey = GlobalKey<FormState>();
  bool saving = false;
  String? saveError;
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      Future<void> save() async {
        if (!(formKey.currentState?.validate() ?? false)) return;
        if (!ctx.mounted) return;
        setD(() { saving = true; saveError = null; });
        try {
          final (proceed, pass) = await _resolvePassphrase(conn, askPassphrase);
          if (!ctx.mounted) return;
          if (!proceed) {
            setD(() => saving = false);
            return;
          }
          await agent.updateCron(conn, entry, schedCtrl.text.trim(), cmdCtrl.text.trim(), keyPassphrase: pass);
          if (context.mounted) {
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Cronjob updated ✓ — rescanning…', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success))));
            onChanged();
          }
        } catch (e) {
          if (!ctx.mounted) return;
          final msg = e.toString().replaceFirst('Exception: ', '').split('\n').first;
          if (msg.contains('Passphrase not accepted')) onBadPassphrase?.call();
          setD(() {
            saving = false;
            saveError = msg;
          });
        }
      }

      return AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
        title: Row(children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)), child: const Icon(Icons.edit_outlined, size: 15, color: AppColors.warning)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('EDIT CRONJOB', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            Text('${conn.name} • ${entry.source}', style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: AppFonts.mono)),
          ])),
          IconButton(onPressed: saving ? null : () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted)),
        ]),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Schedule (5 fields or @macro)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                TextFormField(
                  controller: schedCtrl,
                  enabled: !saving,
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: AppFonts.mono),
                  decoration: InputDecoration(
                    hintText: '*/5 * * * *  or  @daily',
                    hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: AppFonts.mono),
                    filled: true, fillColor: AppColors.surface2,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentCyan)),
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Required';
                    if (t.startsWith('@')) {
                      const macros = {'@reboot', '@yearly', '@annually', '@monthly', '@weekly', '@daily', '@midnight', '@hourly'};
                      if (!macros.contains(t)) return 'Unknown @macro';
                      return null;
                    }
                    final parts = t.split(RegExp(r'\s+'));
                    if (parts.length != 5) return 'Need 5 fields: min hour dom month dow';
                    if (!parts.every((f) => RegExp(r'^[\d*,/\-]+$').hasMatch(f))) return 'Invalid characters in schedule';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                const Text('Command', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                TextFormField(
                  controller: cmdCtrl,
                  enabled: !saving,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: AppFonts.mono),
                  decoration: InputDecoration(
                    filled: true, fillColor: AppColors.surface2,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentCyan)),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                if (entry.source != 'crontab') ...[
                  const SizedBox(height: 8),
                  const Text('System file — the run-as user is preserved, a backup (*.mcp-bak) is written first.', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                ],
                if (saveError != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [const Icon(Icons.error_outline, size: 13, color: AppColors.critical), const SizedBox(width: 6), Expanded(child: Text(saveError!, style: const TextStyle(fontSize: 11, color: AppColors.critical)))]),
                ],
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('CANCEL', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700))),
          FilledButton(
            onPressed: saving ? null : save,
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black),
            child: saving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('SAVE TO SERVER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ],
      );
    }),
  );
}
