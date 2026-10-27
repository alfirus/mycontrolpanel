import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../models/alert_entry.dart';
import '../models/app_entry.dart';
import '../models/cron_entry.dart';
import '../models/mock_data.dart';
import '../models/server_connection.dart';
import '../services/agent_service.dart';
import '../services/ssh_key_loader.dart';
import '../widgets/cron_dialogs.dart';
import '../widgets/pitch_card.dart';

/// Full detail for one saved server: connection, live metrics, its cronjobs, actions.
class ServerDetailsScreen extends StatefulWidget {
  final String serverId;
  final VoidCallback? onOpenTerminal;
  const ServerDetailsScreen({super.key, required this.serverId, this.onOpenTerminal});

  @override
  State<ServerDetailsScreen> createState() => _ServerDetailsScreenState();
}

class _ServerDetailsScreenState extends State<ServerDetailsScreen> {
  final _agent = AgentService();
  ServerConnection? _conn;
  Map<String, dynamic>? _metrics;
  List<CronEntry> _crons = [];
  List<AppEntry> _apps = [];
  List<AlertEntry> _alerts = [];
  bool _loading = true;
  bool _metricsBusy = false;
  bool _cronsBusy = false;
  bool _appsBusy = false;
  bool _alertsBusy = false;
  String? _keyPass; // encrypted-key passphrase, asked once per visit
  bool _installing = false;
  String? _metricsError;
  String? _cronsError;
  String? _appsError;
  String? _alertsError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('server_connections');
    final list = raw == null ? <ServerConnection>[] : ServerConnection.decodeList(raw);
    final conn = list.where((e) => e.id == widget.serverId).firstOrNull;
    if (!mounted) return;
    setState(() { _conn = conn; _loading = false; });
    if (conn != null) {
      _refreshMetrics();
      _refreshCrons();
      _refreshApps();
      _refreshAlerts();
    }
  }

  Future<void> _refreshMetrics() async {
    final c = _conn;
    if (c == null) return;
    setState(() { _metricsBusy = true; _metricsError = null; });
    final m = await _agent.fetch(c.host);
    if (!mounted) return;
    setState(() {
      _metricsBusy = false;
      if (m != null) {
        _metrics = m;
      } else {
        _metricsError = 'Agent not reachable at ${c.host}:${AgentService.agentPort}';
      }
    });
  }

  Future<void> _refreshCrons() async {
    final c = _conn;
    if (c == null) return;
    setState(() { _cronsBusy = true; _cronsError = null; });
    try {
      final (proceed, pass) = await _keyPassphrase();
      if (!proceed) {
        if (mounted) setState(() => _cronsBusy = false);
        return;
      }
      final entries = await _agent.fetchCrons(c, keyPassphrase: pass);
      if (!mounted) return;
      setState(() { _crons = entries; _cronsBusy = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cronsBusy = false; _cronsError = e.toString().split('\n').first; });
    }
  }

  Future<void> _refreshApps() async {
    final c = _conn;
    if (c == null) return;
    setState(() { _appsBusy = true; _appsError = null; });
    try {
      final (proceed, pass) = await _keyPassphrase();
      if (!proceed) {
        if (mounted) setState(() => _appsBusy = false);
        return;
      }
      final entries = await _agent.fetchApps(c, keyPassphrase: pass);
      if (!mounted) return;
      setState(() { _apps = entries; _appsBusy = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _appsBusy = false; _appsError = e.toString().split('\n').first; });
    }
  }

  Future<void> _refreshAlerts() async {
    final c = _conn;
    if (c == null) return;
    setState(() { _alertsBusy = true; _alertsError = null; });
    try {
      final (proceed, pass) = await _keyPassphrase();
      if (!proceed) {
        if (mounted) setState(() => _alertsBusy = false);
        return;
      }
      final entries = await _agent.fetchAlerts(c, keyPassphrase: pass);
      if (!mounted) return;
      setState(() { _alerts = entries; _alertsBusy = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _alertsBusy = false; _alertsError = e.toString().split('\n').first; });
    }
  }

  /// Resolve key passphrase once per visit (cached for crons/apps/alerts/install).
  /// Returns (proceed, passphrase). proceed=false means user cancelled.
  Future<(bool, String?)> _keyPassphrase() async {
    final c = _conn;
    if (c == null || c.authMethod == AuthMethod.password) return (true, null);
    if (_keyPass != null) return (true, _keyPass);
    final pre = await SshKeyLoader.load(c.credential);
    if (pre.keys != null) return (true, null);
    if (!pre.needsPassphrase) throw Exception(pre.error ?? 'key load failed');
    final pass = await _askPassphrase();
    if (pass == null) return (false, null);
    _keyPass = pass;
    return (true, pass);
  }

  Future<String?> _askPassphrase() async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
        title: const Text('Key passphrase', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: TextField(controller: c, obscureText: true, autofocus: true, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: AppFonts.mono), decoration: InputDecoration(hintText: 'Passphrase', hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted), filled: true, fillColor: AppColors.surface2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL', style: TextStyle(color: AppColors.textSecondary))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black), child: const Text('UNLOCK')),
        ],
      ),
    );
  }

  Future<void> _installAgent() async {
    final c = _conn;
    if (c == null) return;
    // Re-entrancy guard (same as server cards): double-taps used to stack
    // duplicate passphrase dialogs, making Cancel/Install appear dead.
    if (_installing) return;
    setState(() => _installing = true);
    try {
      String? pass;
      if (c.authMethod != AuthMethod.password) {
        final (proceed, cached) = await _keyPassphrase();
        if (!proceed) return;
        pass = cached;
      }
    final lines = <String>[];
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        if (lines.isEmpty) {
          () async {
            AgentInstallResult? r;
            Object? crash;
            try {
              r = await _agent.install(c, (l) { lines.add(l); setD(() {}); }, keyPassphrase: pass);
            } catch (e) {
              crash = e;
            }
            if (!mounted) return;
            await _dismissDialog();
            if (!mounted) return;
            if (crash != null) {
              _showInstallLog('Unexpected error (please report):\n$crash');
              return;
            }
            final result = r!;
            if (result.success) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Agent installed ✓ — refreshing metrics…', style: TextStyle(fontSize: 12, color: AppColors.success))));
              _refreshMetrics();
            } else if (result.log == 'SSH_KEY_BAD_PASSPHRASE') {
              setState(() => _keyPass = null); // wrong passphrase — ask again next time
              _showInstallLog('Wrong key passphrase. Tap INSTALL AGENT to retry with the correct one, or use the manual install.');
            } else {
              _showInstallLog(result.log);
            }
          }();
        }
        return AlertDialog(
          backgroundColor: AppColors.surface1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
          title: Row(children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan)), const SizedBox(width: 10), Expanded(child: Text('Installing on ${c.host}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)))]),
          content: SizedBox(width: 340, height: 220, child: SingleChildScrollView(child: SelectableText(lines.join('\n'), style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontFamily: AppFonts.mono)))),
        );
      }),
    );
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  /// Pop the top dialog and wait for the transition to finish, so the
  /// next showDialog doesn't trip Navigator._debugLocked.
  Future<void> _dismissDialog() async {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
      await Future.delayed(const Duration(milliseconds: 350));
    }
  }

  void _showInstallLog(String log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
        title: const Text('Install log', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        content: SizedBox(
          width: 380, height: 300,
          child: SingleChildScrollView(child: SelectableText(log, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontFamily: AppFonts.mono))),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE', style: TextStyle(color: AppColors.textSecondary)))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pitchBlack,
      appBar: AppBar(
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, size: 18, color: AppColors.textSecondary)),
        title: Text(_conn?.name.toUpperCase() ?? 'SERVER', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textPrimary)),
        actions: [
          IconButton(tooltip: 'Refresh all', onPressed: () { _refreshMetrics(); _refreshCrons(); _refreshApps(); _refreshAlerts(); }, icon: const Icon(Icons.refresh, size: 17, color: AppColors.textSecondary)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentCyan))
          : _conn == null
              ? const Center(child: Text('Server not found (deleted?)', style: TextStyle(color: AppColors.textMuted)))
              : LayoutBuilder(builder: (ctx, constraints) {
                  final threeCol = constraints.maxWidth > 900;
                  final cards = [_connectionCard(), _metricsCard(), _actionsCard(), _alertsCard(), _appsCard(), _cronsCard()];
                  Widget col(Widget w) => threeCol ? Expanded(child: w) : w;
                  const gap = SizedBox(width: 12);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (threeCol) ...[
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [col(cards[0]), gap, col(cards[1]), gap, col(cards[2])]),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [col(cards[3]), gap, col(cards[4]), gap, col(cards[5])]),
                      ] else ...[
                        _connectionCard(),
                        _metricsCard(),
                        _actionsCard(),
                        _alertsCard(),
                        _appsCard(),
                        _cronsCard(),
                      ],
                      const SizedBox(height: 8),
                      const Center(child: Text('SERVER DETAILS • LIVE VIA SSH', style: TextStyle(fontSize: 9, letterSpacing: 0.7, color: AppColors.textDim, fontWeight: FontWeight.w600))),
                    ]),
                  );
                }),
    );
  }

  /// Push a full-list screen for a card that was capped at 10.
  void _openFullList(String title, List<Widget> items, {String? subtitle}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.pitchBlack,
          appBar: AppBar(
            leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, size: 18, color: AppColors.textSecondary)),
            title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textPrimary)),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (subtitle != null) ...[
                Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                const SizedBox(height: 10),
              ],
              ...items,
            ]),
          ),
        ),
      ),
    );
  }

  /// "VIEW ALL (N)" footer for capped cards.
  Widget _viewAllFooter(int total, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.3))),
          child: Center(child: Text('VIEW ALL ($total) →', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.accentCyan))),
        ),
      );

  Widget _connectionCard() {
    final c = _conn!;
    return PitchCard(
      title: 'CONNECTION',
      trailing: Pill(text: c.enabled ? 'ENABLED' : 'DISABLED', color: c.enabled ? AppColors.success : AppColors.textMuted),
      child: Column(children: [
        _kv('Host', '${c.host}:${c.port}'),
        _kv('Username', c.username),
        _kv('Auth', '${c.authMethod.name}${c.authMethod == AuthMethod.sshKey ? ' • key saved' : ''}'),
        _kv('Region', c.region),
        _kv('OS', c.os),
        _kv('Environment', c.env.name.toUpperCase()),
        if (c.tags != null && c.tags!.isNotEmpty) _kv('Tags', c.tags!),
      ]),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(children: [
          SizedBox(width: 100, child: Text(k, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
          Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: AppFonts.mono))),
        ]),
      );

  Widget _metricsCard() {
    final m = _metrics;
    return PitchCard(
      title: 'LIVE METRICS',
      subtitle: m != null ? 'agent :${AgentService.agentPort} • up ${m['uptime_days']}d' : 'via metrics agent',
      trailing: _metricsBusy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan))
          : InkWell(onTap: _refreshMetrics, child: const Row(children: [Icon(Icons.refresh, size: 12, color: AppColors.accentCyan), SizedBox(width: 3), Text('REFRESH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))])),
      child: m != null
          ? Column(children: [
              Row(children: [
                Expanded(child: MetricBar(label: 'CPU', value: (m['cpu'] as num).toDouble(), color: (m['cpu'] as num) > 0.75 ? AppColors.critical : AppColors.accentCyan)),
                const SizedBox(width: 10),
                Expanded(child: MetricBar(label: 'RAM', value: (m['ram'] as num).toDouble(), color: (m['ram'] as num) > 0.85 ? AppColors.critical : AppColors.accentBlue)),
                const SizedBox(width: 10),
                Expanded(child: MetricBar(label: 'DISK', value: (m['disk'] as num).toDouble(), color: (m['disk'] as num) > 0.8 ? AppColors.warning : AppColors.textSecondary)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('LIVE • ${((m['cpu'] as num).toDouble() * 100).toInt()}% CPU • ${((m['ram'] as num).toDouble() * 100).toInt()}% RAM • ${((m['disk'] as num).toDouble() * 100).toInt()}% DISK', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success)),
              ]),
            ])
          : Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderLight)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.sensors_off_outlined, size: 15, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_metricsError ?? 'No agent data yet.', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                ]),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _installing ? null : _installAgent,
                    icon: _installing ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.download, size: 13),
                    label: Text(_installing ? 'INSTALLING…' : 'INSTALL AGENT (ONE-CLICK)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 10)),
                  ),
                ),
              ]),
            ),
    );
  }

  Widget _cronsCard() {
    return PitchCard(
      title: 'CRONJOBS ON THIS SERVER',
      subtitle: '${_crons.length} jobs • crontab + /etc/crontab + /etc/cron.d',
      trailing: _cronsBusy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan))
          : InkWell(onTap: _refreshCrons, child: const Row(children: [Icon(Icons.refresh, size: 12, color: AppColors.accentCyan), SizedBox(width: 3), Text('RESCAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))])),
      child: _cronsBusy && _crons.isEmpty
          ? const Padding(padding: EdgeInsets.all(12), child: Row(children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan)), SizedBox(width: 8), Text('Scanning crontabs via SSH…', style: TextStyle(fontSize: 11, color: AppColors.textMuted))]))
          : _crons.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    const Icon(Icons.schedule_outlined, size: 15, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_cronsError ?? 'No crontab entries found on this server.', style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                  ]),
                )
              : Column(children: [
                  for (final e in _crons.take(10)) _cronTile(e),
                  if (_crons.length > 10)
                    _viewAllFooter(_crons.length, () => _openFullList(
                          'CRONJOBS • ${_conn!.name.toUpperCase()}',
                          [for (final e in _crons) _cronTile(e)],
                          subtitle: '${_crons.length} jobs • crontab + /etc/crontab + /etc/cron.d',
                        )),
                ]),
    );
  }

  void _openCron(CronEntry e) {
    final c = _conn;
    if (c == null) return;
    showCronActions(
      context,
      entry: e,
      conn: c,
      agent: _agent,
      askPassphrase: () async {
        final (proceed, pass) = await _keyPassphrase();
        return proceed ? pass : null;
      },
      onChanged: _refreshCrons,
    );
  }

  Widget _cronTile(CronEntry e) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openCron(e),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderLight)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(child: Text(e.command, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamily: AppFonts.mono), maxLines: 2, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, size: 14, color: AppColors.textDim),
              ]),
              const SizedBox(height: 5),
              Wrap(spacing: 6, runSpacing: 4, children: [
                Text(e.schedule, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.accentCyan, fontFamily: AppFonts.mono)),
                Text(e.source, style: const TextStyle(fontSize: 9, color: AppColors.textMuted, fontFamily: AppFonts.mono)),
                const Pill(text: 'SCHEDULED', color: AppColors.success),
              ]),
            ]),
          ),
        ),
      );

  Widget _appsCard() {
    return PitchCard(
      title: 'APPS ON THIS SERVER',
      subtitle: '${_apps.length} services • systemd + docker + ports',
      trailing: _appsBusy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan))
          : InkWell(onTap: _refreshApps, child: const Row(children: [Icon(Icons.refresh, size: 12, color: AppColors.accentCyan), SizedBox(width: 3), Text('RESCAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))])),
      child: _appsBusy && _apps.isEmpty
          ? const Padding(padding: EdgeInsets.all(12), child: Row(children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan)), SizedBox(width: 8), Text('Discovering services via SSH…', style: TextStyle(fontSize: 11, color: AppColors.textMuted))]))
          : _apps.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    const Icon(Icons.apps_outlined, size: 15, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_appsError ?? 'No services found on this server.', style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                  ]),
                )
              : Column(children: [
                  for (final a in _apps.take(10)) _appTile(a),
                  if (_apps.length > 10)
                    _viewAllFooter(_apps.length, () => _openFullList(
                          'APPS • ${_conn!.name.toUpperCase()}',
                          [for (final a in _apps) _appTile(a)],
                          subtitle: '${_apps.length} services • systemd + docker + ports',
                        )),
                ]),
    );
  }

  Widget _appTile(AppEntry a) {
    final color = a.source == 'docker' ? AppColors.accentBlue : a.source == 'port' ? AppColors.accentPurple : AppColors.success;
    final icon = a.source == 'docker' ? Icons.inventory_2_outlined : a.source == 'port' ? Icons.hub_outlined : Icons.settings_applications_outlined;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.borderLight)),
      child: Row(children: [
        Container(width: 30, height: 30, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7)), child: Icon(icon, size: 13, color: color)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(a.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 5),
            Pill(text: a.source.toUpperCase(), color: color),
          ]),
          const SizedBox(height: 2),
          Text(a.detail, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: AppFonts.mono), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        StatusDot(color: AppColors.success, pulse: false),
      ]),
    );
  }

  Widget _alertsCard() {
    final firing = _alerts.where((a) => a.status == 'firing').length;
    return PitchCard(
      title: 'ALERTS ON THIS SERVER',
      subtitle: _alerts.isEmpty ? 'no firing signals' : '$firing firing • ${_alerts.length} total',
      trailing: _alertsBusy
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan))
          : InkWell(onTap: _refreshAlerts, child: const Row(children: [Icon(Icons.refresh, size: 12, color: AppColors.accentCyan), SizedBox(width: 3), Text('RESCAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))])),
      child: _alertsBusy && _alerts.isEmpty
          ? const Padding(padding: EdgeInsets.all(12), child: Row(children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan)), SizedBox(width: 8), Text('Harvesting signals via SSH…', style: TextStyle(fontSize: 11, color: AppColors.textMuted))]))
          : _alerts.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    const Icon(Icons.check_circle, size: 15, color: AppColors.success),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_alertsError ?? 'Healthy — no failed units, disk OK, no brute force, load normal.', style: const TextStyle(fontSize: 11, color: AppColors.textMuted))),
                  ]),
                )
              : Column(children: [
                  for (final a in _alerts.take(10)) _alertTile(a),
                  if (_alerts.length > 10)
                    _viewAllFooter(_alerts.length, () => _openFullList(
                          'ALERTS • ${_conn!.name.toUpperCase()}',
                          [for (final a in _alerts) _alertTile(a)],
                          subtitle: '${_alerts.where((e) => e.status == 'firing').length} firing • ${_alerts.length} total',
                        )),
                ]),
    );
  }

  Widget _alertTile(AlertEntry a) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: a.severity == 'critical' ? AppColors.critical.withValues(alpha: 0.3) : AppColors.borderLight)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 28, height: 28, decoration: BoxDecoration(color: severityColor(a.severity).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)), child: Icon(a.severity == 'critical' ? Icons.error_outline : a.severity == 'warning' ? Icons.warning_amber : Icons.info_outline, size: 14, color: severityColor(a.severity))),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(a.source, style: const TextStyle(fontSize: 9, color: AppColors.textMuted, fontFamily: AppFonts.mono)),
          ])),
          const SizedBox(width: 6),
          Pill(text: a.status.toUpperCase(), color: a.status == 'firing' ? AppColors.critical : AppColors.success),
        ]),
      );

  Widget _actionsCard() {
    final c = _conn!;
    return PitchCard(
      title: 'ACTIONS',
      child: Column(children: [
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: widget.onOpenTerminal,
              icon: const Icon(Icons.terminal, size: 14),
              label: const Text('OPEN TERMINAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentCyan, side: const BorderSide(color: AppColors.accentCyan), padding: const EdgeInsets.symmetric(vertical: 10)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: 'ssh -p ${c.port} ${c.username}@${c.host}'));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('SSH command copied', style: TextStyle(fontSize: 12, color: AppColors.accentCyan)), duration: Duration(seconds: 2)));
              },
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('COPY SSH CMD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary, side: const BorderSide(color: AppColors.border), padding: const EdgeInsets.symmetric(vertical: 10)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () { _refreshMetrics(); _refreshCrons(); _refreshApps(); _refreshAlerts(); },
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('REFRESH ALL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary, side: const BorderSide(color: AppColors.border), padding: const EdgeInsets.symmetric(vertical: 10)),
            ),
          ),
        ]),
      ]),
    );
  }
}
