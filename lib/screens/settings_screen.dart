import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../theme/app_theme.dart';
import '../models/server_connection.dart';
import '../services/github_service.dart';
import '../services/ssh_key_loader.dart';
import '../widgets/pitch_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<ServerConnection> _servers = [];
  bool _loading = true;
  String _search = '';
  // App settings
  bool _autoRefresh = true;
  double _refreshInterval = 15;
  bool _notifications = true;
  bool _biometrics = false;
  String _selectedTheme = 'Pitch Black';
  // GitHub integration
  String _githubToken = '';
  String _githubUser = '';
  List<String> _githubRepos = [];
  bool _githubVerifying = false;
  final _githubTokenCtrl = TextEditingController();
  final _githubRepoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('server_connections');
    setState(() {
      if (raw != null) _servers = ServerConnection.decodeList(raw);
      _autoRefresh = prefs.getBool('auto_refresh') ?? true;
      _refreshInterval = prefs.getDouble('refresh_interval') ?? 15;
      _notifications = prefs.getBool('notifications') ?? true;
      _githubToken = prefs.getString('github_token') ?? '';
      _githubUser = prefs.getString('github_user') ?? '';
      _githubRepos = (prefs.getStringList('github_repos') ?? []).toList();
      _githubTokenCtrl.text = _githubToken;
      _loading = false;
    });
  }

  Future<void> _saveServers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_connections', ServerConnection.encodeList(_servers));
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_refresh', _autoRefresh);
    await prefs.setDouble('refresh_interval', _refreshInterval);
    await prefs.setBool('notifications', _notifications);
  }

  @override
  void dispose() {
    _githubTokenCtrl.dispose();
    _githubRepoCtrl.dispose();
    super.dispose();
  }

  void _addOrEdit({ServerConnection? existing}) async {
    final result = await showDialog<ServerConnection>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => _ServerDialog(existing: existing),
    );
    if (result != null) {
      setState(() {
        if (existing != null) {
          final idx = _servers.indexWhere((s)=> s.id==existing.id);
          if (idx!=-1) _servers[idx]=result;
        } else {
          _servers.add(result);
        }
      });
      await _saveServers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.surface1, content: Text(existing!=null ? 'Updated ${result.name}' : 'Added ${result.name}', style: const TextStyle(color: AppColors.textPrimary)), duration: const Duration(seconds: 2)));
    }
  }

  Future<void> _delete(ServerConnection s) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
      title: const Text('Remove server?', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
      content: Text('Delete ${s.name} (${s.host})? This cannot be undone.', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(context,false), child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
        FilledButton(onPressed: ()=> Navigator.pop(context,true), style: FilledButton.styleFrom(backgroundColor: AppColors.critical), child: const Text('Delete')),
      ],
    ));
    if (ok==true) {
      setState(()=> _servers.removeWhere((e)=> e.id==s.id));
      await _saveServers();
    }
  }

  /// Real SSH test: authenticates with password or saved key, runs `echo OK`.
  Future<void> _testConnection(ServerConnection s) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: AppColors.accentCyan)));
    String? error;
    try {
      List<SSHKeyPair>? keys;
      String? Function()? passwordCb;
      if (s.authMethod == AuthMethod.password) {
        passwordCb = () => s.credential;
      } else {
        final loaded = await SshKeyLoader.load(s.credential);
        if (loaded.keys == null) {
          error = loaded.needsPassphrase
              ? 'Key is encrypted — connect from Terminal tab to enter passphrase.'
              : (loaded.error ?? 'Key load failed.');
        } else {
          keys = loaded.keys;
        }
      }
      if (error == null) {
        final socket = await SSHSocket.connect(s.host, s.port, timeout: const Duration(seconds: 10));
        final client = SSHClient(socket, username: s.username, onPasswordRequest: passwordCb, identities: keys ?? const []);
        await client.authenticated.timeout(const Duration(seconds: 15));
        final session = await client.execute('echo OK');
        final out = await session.stdout.cast<List<int>>().transform(const Utf8Decoder()).join().timeout(const Duration(seconds: 10));
        final ok = session.exitCode == 0 && out.trim() == 'OK';
        client.close();
        if (!ok) error = 'SSH ok but remote command failed (exit ${session.exitCode}).';
      }
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '').split('\n').first;
      if (error!.length > 160) error = '${error!.substring(0, 160)}…';
    }
    if (!mounted) return;
    Navigator.pop(context);
    final success = error == null;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: success ? AppColors.success.withValues(alpha: 0.14) : AppColors.critical.withValues(alpha: 0.14),
      content: Row(children: [
        Icon(success ? Icons.check_circle : Icons.error_outline, size: 14, color: success ? AppColors.success : AppColors.critical),
        const SizedBox(width: 8),
        Expanded(child: Text(success ? 'SSH to ${s.host}:${s.port} ✓ (${s.authMethod.name})' : 'SSH failed: $error', style: TextStyle(color: success ? AppColors.success : AppColors.critical, fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
      duration: Duration(seconds: success ? 3 : 6),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.accentCyan));
    final filtered = _search.isEmpty ? _servers : _servers.where((s)=> s.name.toLowerCase().contains(_search.toLowerCase()) || s.host.toLowerCase().contains(_search.toLowerCase())).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)), child: const Icon(Icons.settings_outlined, size: 16, color: AppColors.textSecondary)),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SETTINGS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textPrimary)),
            Text('Manage server connections & app preferences', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
          const Spacer(),
          FilledButton.icon(onPressed: ()=> _addOrEdit(), icon: const Icon(Icons.add, size: 14), label: const Text('ADD SERVER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)), style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))),
        ]),
        const SizedBox(height: 12),
        // Server connections — primary
        PitchCard(
          title: 'SERVER CONNECTIONS',
          subtitle: '${_servers.length} configured • ${_servers.where((s)=>s.enabled).length} enabled • tap card to edit',
          trailing: SizedBox(width: 180, height: 32, child: TextField(onChanged: (v)=> setState(()=> _search=v), style: const TextStyle(fontSize: 12, color: AppColors.textPrimary), decoration: InputDecoration(hintText: 'Search name or host…', hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted), prefixIcon: const Icon(Icons.search, size: 14, color: AppColors.textMuted), filled: true, fillColor: AppColors.surface2, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentCyan)), isDense: true))),
          child: _servers.isEmpty
            ? _emptyState()
            : Column(children: [
                for (final s in filtered) _serverTile(s),
                if (filtered.isEmpty && _search.isNotEmpty)
                  const Padding(padding: EdgeInsets.all(16), child: Text('No matches for search', style: TextStyle(fontSize: 12, color: AppColors.textMuted))),
              ]),
          footer: _servers.isEmpty ? null : Row(children: [
            OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.upload, size: 12), label: const Text('EXPORT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)), style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary, side: const BorderSide(color: AppColors.border), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.download, size: 12), label: const Text('IMPORT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)), style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary, side: const BorderSide(color: AppColors.border), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
            const Spacer(),
            Text('${filtered.length} shown', style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'monospace')),
          ]),
        ),
        // Two-col for app prefs + integrations
        LayoutBuilder(builder: (_, c) {
          final isWide = c.maxWidth > 700;
          final prefsCard = PitchCard(
            title: 'APP PREFERENCES',
            child: Column(children: [
              _switchTile('Auto-refresh', 'Poll servers every interval', _autoRefresh, (v){ setState(()=> _autoRefresh=v); _savePrefs(); }),
              _sliderTile('Refresh interval', '${_refreshInterval.toInt()}s', _refreshInterval, 5, 60, (v){ setState(()=> _refreshInterval=v); _savePrefs(); }),
              _switchTile('Notifications', 'Alert on critical incidents', _notifications, (v){ setState(()=> _notifications=v); _savePrefs(); }),
              _switchTile('Biometrics', 'Require Face ID / Touch ID', _biometrics, (v)=> setState(()=> _biometrics=v)),
              const SizedBox(height: 4),
              Row(children: [
                const Text('Theme', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const Spacer(),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)), child: Row(children: [Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.pitchBlack, shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: AppColors.textMuted))),), const SizedBox(width: 6), Text(_selectedTheme, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))])),
              ]),
            ]),
          );
          final integrationsCard = PitchCard(
            title: 'INTEGRATIONS',
            subtitle: 'Tokens stored locally on this device',
            child: Column(children: [
              _githubSection(),
              const SizedBox(height: 6),
              _integrationRow('AI Provider', 'sk-••••••••••••', Icons.smart_toy_outlined, AppColors.accentCyan, 'Configure'),
              _integrationRow('Sentry / Datadog', 'Not connected', Icons.bug_report_outlined, AppColors.textMuted, 'Add'),
            ]),
            footer: const Text('Server creds + tokens live in SharedPreferences on-device (no cloud). Move secrets to flutter_secure_storage for production.', style: TextStyle(fontSize: 10, color: AppColors.textDim)),
          );
          if (isWide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: prefsCard), const SizedBox(width: 12), Expanded(child: integrationsCard)]);
          }
          return Column(children: [prefsCard, integrationsCard]);
        }),
        // Danger zone
        PitchCard(
          title: 'DANGER ZONE',
          child: Column(children: [
            Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Clear all server connections', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)), Text('Removes all stored hosts — cannot be undone', style: TextStyle(fontSize: 11, color: AppColors.textMuted))])),
              OutlinedButton(onPressed: _servers.isEmpty ? null : () async {
                final ok = await showDialog<bool>(context: context, builder: (_)=> AlertDialog(backgroundColor: AppColors.surface1, title: const Text('Clear all?', style: TextStyle(color: AppColors.textPrimary)), content: const Text('This will delete all server connections.', style: TextStyle(color: AppColors.textSecondary)), actions: [TextButton(onPressed: ()=> Navigator.pop(context,false), child: const Text('Cancel')), FilledButton(onPressed: ()=> Navigator.pop(context,true), style: FilledButton.styleFrom(backgroundColor: AppColors.critical), child: const Text('Clear'))]));
                if (ok==true) { setState(()=> _servers=[]); await _saveServers(); }
              }, style: OutlinedButton.styleFrom(foregroundColor: AppColors.critical, side: const BorderSide(color: AppColors.critical)), child: const Text('CLEAR ALL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
            ]),
          ]),
        ),
        const SizedBox(height: 8),
        const Center(child: Text('MY CONTROL PANEL • SETTINGS • stored locally via SharedPreferences', style: TextStyle(fontSize: 9, color: AppColors.textDim, letterSpacing: 0.6, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _emptyState() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.borderLight, style: BorderStyle.solid)),
    child: Column(children: [
      Container(width: 48, height: 48, decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)), child: const Icon(Icons.dns_outlined, size: 20, color: AppColors.textMuted)),
      const SizedBox(height: 10),
      const Text('No servers yet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      const SizedBox(height: 4),
      const Text('Add your first server to start monitoring — SSH, API token, or password.', style: TextStyle(fontSize: 11, color: AppColors.textMuted), textAlign: TextAlign.center),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: ()=> _addOrEdit(), icon: const Icon(Icons.add, size: 14), label: const Text('ADD SERVER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)), style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black)),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)), child: const Text('Tip: uses SSH (port 22) or API (443/3000). Test connection before saving.', style: TextStyle(fontSize: 10, color: AppColors.textMuted))),
    ]),
  );

  Widget _serverTile(ServerConnection s) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(10), border: Border.all(color: s.enabled ? AppColors.borderLight : AppColors.border)),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: ()=> _addOrEdit(existing: s),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(width: 34, height: 34, decoration: BoxDecoration(color: s.enabled ? AppColors.accentCyan.withValues(alpha: 0.12) : AppColors.surface2, borderRadius: BorderRadius.circular(7), border: Border.all(color: s.enabled ? AppColors.accentCyan.withValues(alpha: 0.22) : AppColors.border)), child: Icon(s.env==ServerEnv.prod ? Icons.cloud : s.env==ServerEnv.staging ? Icons.science_outlined : Icons.developer_mode, size: 16, color: s.enabled ? AppColors.accentCyan : AppColors.textMuted)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(s.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: s.enabled ? AppColors.textPrimary : AppColors.textMuted)),
                const SizedBox(width: 6),
                Pill(text: s.env.name.toUpperCase(), color: s.env==ServerEnv.prod ? AppColors.success : s.env==ServerEnv.staging ? AppColors.warning : AppColors.textMuted, bg: s.env==ServerEnv.prod ? AppColors.success.withValues(alpha: 0.12) : AppColors.warning.withValues(alpha: 0.12)),
                if (!s.enabled) ...[const SizedBox(width: 5), const Pill(text: 'DISABLED', color: AppColors.textMuted)],
              ]),
              const SizedBox(height: 2),
              Text('${s.host}:${s.port} • ${s.username}@ • ${s.region} • ${s.os}', style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(children: [
                Icon(s.authMethod==AuthMethod.password ? Icons.password : s.authMethod==AuthMethod.sshKey ? Icons.key : Icons.token_outlined, size: 10, color: AppColors.textDim),
                const SizedBox(width: 4),
                Text(s.authMethod.name, style: const TextStyle(fontSize: 9, color: AppColors.textDim, fontWeight: FontWeight.w600)),
                if (s.tags!=null && s.tags!.isNotEmpty) ...[const SizedBox(width: 6), Text('• ${s.tags}', style: const TextStyle(fontSize: 9, color: AppColors.textDim))],
              ]),
            ])),
            const SizedBox(width: 8),
            Column(children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.bolt, size: 14, color: AppColors.accentCyan), tooltip: 'Test', onPressed: ()=> _testConnection(s), style: IconButton.styleFrom(backgroundColor: AppColors.accentCyan.withValues(alpha: 0.12), padding: const EdgeInsets.all(6), minimumSize: const Size(28,28))),
                const SizedBox(width: 4),
                IconButton(icon: Icon(s.enabled ? Icons.visibility : Icons.visibility_off, size: 14, color: AppColors.textSecondary), tooltip: s.enabled ? 'Disable' : 'Enable', onPressed: () async { setState(()=> _servers[_servers.indexWhere((e)=>e.id==s.id)] = s.copyWith(enabled: !s.enabled)); await _saveServers(); }, style: IconButton.styleFrom(backgroundColor: AppColors.surface2, padding: const EdgeInsets.all(6), minimumSize: const Size(28,28))),
                const SizedBox(width: 4),
                IconButton(icon: const Icon(Icons.delete_outline, size: 14, color: AppColors.critical), tooltip: 'Delete', onPressed: ()=> _delete(s), style: IconButton.styleFrom(backgroundColor: AppColors.critical.withValues(alpha: 0.12), padding: const EdgeInsets.all(6), minimumSize: const Size(28,28))),
              ]),
              Text(timeAgo(s.createdAt), style: const TextStyle(fontSize: 9, color: AppColors.textDim)),
            ]),
          ]),
        ),
      ),
    ),
  );

  String timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inSeconds<60) return '${d.inSeconds}s ago';
    if (d.inMinutes<60) return '${d.inMinutes}m ago';
    if (d.inHours<24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  Widget _switchTile(String title, String subtitle, bool val, ValueChanged<bool> onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)), Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.textMuted))])),
      Switch(value: val, onChanged: onChanged, activeTrackColor: AppColors.accentCyan, thumbColor: WidgetStateProperty.all(Colors.black)),
    ]),
  );

  Widget _sliderTile(String title, String valLabel, double val, double min, double max, ValueChanged<double> onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)), Text(valLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accentCyan, fontFamily: 'monospace'))]),
      Slider(value: val, min: min, max: max, divisions: 11, activeColor: AppColors.accentCyan, inactiveColor: AppColors.surface2, onChanged: onChanged),
    ]),
  );

  /// GitHub PAT + tracked repos. Verifies via GET /user, stores locally.
  Widget _githubSection() {
    final connected = _githubToken.isNotEmpty && _githubUser.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(10), border: Border.all(color: connected ? AppColors.success.withValues(alpha: 0.3) : AppColors.borderLight)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.textPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7), border: Border.all(color: AppColors.border)), child: const Icon(Icons.code, size: 14, color: AppColors.textPrimary)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('GitHub', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text(connected ? '@$_githubUser • ${_githubRepos.length} repo${_githubRepos.length == 1 ? '' : 's'}' : 'Not connected — paste a personal access token', style: TextStyle(fontSize: 10, color: connected ? AppColors.success : AppColors.textMuted, fontFamily: 'monospace')),
          ])),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: connected ? AppColors.success : AppColors.textDim, shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _githubTokenCtrl,
              obscureText: true,
              style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'ghp_… / github_pat_… (needs `repo` scope)',
                hintStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'monospace'),
                filled: true, fillColor: AppColors.surface2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentCyan)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _githubVerifying ? null : _verifyGithubToken,
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
            child: _githubVerifying
                ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : Text(connected ? 'UPDATE' : 'CONNECT', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ]),
        if (connected) ...[
          if (_githubRepos.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final r in _githubRepos)
              Container(
                margin: const EdgeInsets.only(bottom: 5),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(7), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  const Icon(Icons.book_outlined, size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(r, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: 'monospace'))),
                  InkWell(onTap: () => _removeGithubRepo(r), child: const Icon(Icons.close, size: 13, color: AppColors.textMuted)),
                ]),
              ),
          ],
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _githubRepoCtrl,
                onSubmitted: (_) => _addGithubRepo(),
                style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'owner/repo  (e.g. alfirus/mycontrolpanel)',
                  hintStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'monospace'),
                  filled: true, fillColor: AppColors.surface2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentCyan)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _addGithubRepo, icon: const Icon(Icons.add, size: 13), label: const Text('ADD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)), style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentCyan, side: const BorderSide(color: AppColors.accentCyan), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11))),
          ]),
          TextButton.icon(
            onPressed: _disconnectGithub,
            icon: const Icon(Icons.link_off, size: 12),
            label: const Text('Disconnect (delete token)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: AppColors.critical),
          ),
        ],
      ]),
    );
  }

  Future<void> _verifyGithubToken() async {
    final token = _githubTokenCtrl.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Paste a token first', style: TextStyle(fontSize: 12, color: AppColors.warning))));
      return;
    }
    setState(() => _githubVerifying = true);
    try {
      final login = await GithubService(token).validate();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('github_token', token);
      await prefs.setString('github_user', login);
      if (!mounted) return;
      setState(() {
        _githubToken = token;
        _githubUser = login;
        _githubVerifying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.success.withValues(alpha: 0.14), content: Text('GitHub connected as @$login ✓ — add repos below', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success))));
    } catch (e) {
      if (!mounted) return;
      setState(() => _githubVerifying = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.critical.withValues(alpha: 0.14), content: Text(e.toString().replaceFirst('Exception: ', '').split('\n').first, style: const TextStyle(fontSize: 12, color: AppColors.critical)), duration: const Duration(seconds: 5)));
    }
  }

  Future<void> _addGithubRepo() async {
    final repo = _githubRepoCtrl.text.trim();
    if (!RegExp(r'^[\w.\-]+/[\w.\-]+$').hasMatch(repo)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Use owner/repo format', style: TextStyle(fontSize: 12, color: AppColors.warning))));
      return;
    }
    if (_githubRepos.contains(repo)) return;
    // verify repo is reachable with the token before adding
    try {
      await GithubService(_githubToken).repoIssues(repo);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.critical.withValues(alpha: 0.14), content: Text('Repo not reachable: ${e.toString().replaceFirst('Exception: ', '').split('\n').first}', style: const TextStyle(fontSize: 12, color: AppColors.critical)), duration: const Duration(seconds: 5)));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final next = [..._githubRepos, repo];
    await prefs.setStringList('github_repos', next);
    if (!mounted) return;
    setState(() {
      _githubRepos = next;
      _githubRepoCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.surface1, content: Text('Tracking $repo ✓', style: const TextStyle(fontSize: 12, color: AppColors.success))));
  }

  Future<void> _removeGithubRepo(String repo) async {
    final prefs = await SharedPreferences.getInstance();
    final next = _githubRepos.where((r) => r != repo).toList();
    await prefs.setStringList('github_repos', next);
    if (!mounted) return;
    setState(() => _githubRepos = next);
  }

  Future<void> _disconnectGithub() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('github_token');
    await prefs.remove('github_user');
    await prefs.remove('github_repos');
    if (!mounted) return;
    setState(() {
      _githubToken = '';
      _githubUser = '';
      _githubRepos = [];
      _githubTokenCtrl.clear();
    });
  }

  Widget _integrationRow(String name, String masked, IconData icon, Color c, String action) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7), border: Border.all(color: c.withValues(alpha: 0.2))), child: Icon(icon, size: 14, color: c)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)), Text(masked, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'monospace'))])),
      OutlinedButton(onPressed: (){}, style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.border), foregroundColor: AppColors.textSecondary, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)), child: Text(action, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
    ]),
  );

  void _export() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Export copied to clipboard (JSON)', style: TextStyle(color: AppColors.textPrimary, fontSize: 12))));
  }
  void _import() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Import: paste JSON (coming soon)', style: TextStyle(color: AppColors.textPrimary, fontSize: 12))));
  }
}

class _ServerDialog extends StatefulWidget {
  final ServerConnection? existing;
  const _ServerDialog({this.existing});
  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name, _host, _port, _user, _cred, _tags;
  AuthMethod _auth = AuthMethod.password;
  ServerEnv _env = ServerEnv.prod;
  String _region = 'us-east-1';
  String _os = 'Ubuntu 24.04';
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _host = TextEditingController(text: e?.host ?? '');
    _port = TextEditingController(text: e?.port.toString() ?? '22');
    _user = TextEditingController(text: e?.username ?? 'root');
    _cred = TextEditingController(text: e?.credential ?? '');
    _tags = TextEditingController(text: e?.tags ?? '');
    _auth = e?.authMethod ?? AuthMethod.password;
    _env = e?.env ?? ServerEnv.prod;
    _region = e?.region ?? 'us-east-1';
    _os = e?.os ?? 'Ubuntu 24.04';
  }
  @override
  void dispose() {
    _name.dispose(); _host.dispose(); _port.dispose(); _user.dispose(); _cred.dispose(); _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      backgroundColor: AppColors.surface0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.accentCyan.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.25))), child: Icon(isEdit ? Icons.edit_outlined : Icons.add, size: 16, color: AppColors.accentCyan)),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(isEdit ? 'EDIT SERVER' : 'ADD SERVER', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: AppColors.textPrimary)), Text(isEdit ? 'Update connection details' : 'Connect a new server to monitor', style: const TextStyle(fontSize: 11, color: AppColors.textMuted))]),
                const Spacer(),
                IconButton(onPressed: ()=> Navigator.pop(context), icon: const Icon(Icons.close, size: 16, color: AppColors.textMuted)),
              ]),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              _field('Server name *', _name, 'prod-core-01', Icons.badge_outlined, validator: (v)=> v==null||v.trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(flex: 3, child: _field('Host / IP *', _host, '10.0.1.10 or prod.example.com', Icons.language, validator: (v)=> v==null||v.trim().isEmpty ? 'Required' : null)),
                const SizedBox(width: 10),
                Expanded(child: _field('Port *', _port, '22', Icons.numbers, keyboard: TextInputType.number, validator: (v){ if(v==null||v.isEmpty) return 'Req'; final p=int.tryParse(v); if(p==null||p<1||p>65535) return '1-65535'; return null; })),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _dropdown('Region', _region, ['us-east-1','eu-west-1','ap-southeast-1','us-west-2'], (v)=> setState(()=> _region=v!))),
                const SizedBox(width: 10),
                Expanded(child: _dropdown('OS', _os, ['Ubuntu 24.04','Ubuntu 22.04','Debian 12','RHEL 9','Amazon Linux 2023'], (v)=> setState(()=> _os=v!))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _dropdown('Environment', _env.name, ServerEnv.values.map((e)=>e.name).toList(), (v)=> setState(()=> _env=ServerEnv.values.firstWhere((e)=>e.name==v)))),
                const SizedBox(width: 10),
                Expanded(child: _field('Username *', _user, 'root', Icons.person_outline, validator: (v)=> v==null||v.isEmpty ? 'Required' : null)),
              ]),
              const SizedBox(height: 10),
              const Text('Authentication', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              SegmentedButton<AuthMethod>(
                segments: const [
                  ButtonSegment(value: AuthMethod.password, label: Text('Password', style: TextStyle(fontSize: 11)), icon: Icon(Icons.password, size: 12)),
                  ButtonSegment(value: AuthMethod.sshKey, label: Text('SSH Key', style: TextStyle(fontSize: 11)), icon: Icon(Icons.key, size: 12)),
                  ButtonSegment(value: AuthMethod.apiToken, label: Text('API Token', style: TextStyle(fontSize: 11)), icon: Icon(Icons.token, size: 12)),
                ],
                selected: {_auth},
                onSelectionChanged: (s)=> setState(()=> _auth=s.first),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states)=> states.contains(WidgetState.selected) ? AppColors.accentCyan : AppColors.surface1),
                  foregroundColor: WidgetStateProperty.resolveWith((states)=> states.contains(WidgetState.selected) ? Colors.black : AppColors.textSecondary),
                  side: WidgetStateProperty.all(const BorderSide(color: AppColors.border)),
                ),
              ),
              const SizedBox(height: 10),
              _field(
                _auth==AuthMethod.password ? 'Password *' : _auth==AuthMethod.sshKey ? 'SSH private key *' : 'API Token *',
                _cred,
                _auth==AuthMethod.password ? '••••••••' : _auth==AuthMethod.sshKey ? 'Tap folder icon to import, or paste full key' : 'ghp_ / Bearer token',
                _auth==AuthMethod.password ? Icons.lock_outline : Icons.key_outlined,
                obscure: _auth==AuthMethod.password && _obscure,
                suffix: _auth==AuthMethod.password
                    ? IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 14, color: AppColors.textMuted), onPressed: ()=> setState(()=> _obscure=!_obscure))
                    : _auth==AuthMethod.sshKey
                        ? IconButton(tooltip: 'Import key file', icon: const Icon(Icons.folder_open, size: 16, color: AppColors.accentCyan), onPressed: _importKeyFile)
                        : null,
                validator: (v)=> v==null||v.isEmpty ? 'Required' : null,
              ),
              if (_auth==AuthMethod.sshKey)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.warning.withValues(alpha: 0.2))),
                  child: const Text('Sandbox note: typed paths (e.g. ~/.ssh/...) cannot be read by the app. Use the folder icon to import — key content is stored, path stops mattering.', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                ),
              const SizedBox(height: 10),
              _field('Tags (optional)', _tags, 'prod, api, critical', Icons.label_outline),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: ()=> Navigator.pop(context), style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.border), foregroundColor: AppColors.textSecondary, padding: const EdgeInsets.symmetric(vertical: 12)), child: const Text('CANCEL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: _submit, style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12)), child: Text(isEdit ? 'SAVE CHANGES' : 'ADD SERVER', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)))),
              ]),
              const SizedBox(height: 8),
              const Center(child: Text('Stored locally • encrypted on device', style: TextStyle(fontSize: 9, color: AppColors.textDim))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, String hint, IconData icon, {bool obscure=false, Widget? suffix, String? Function(String?)? validator, TextInputType? keyboard}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textSecondary)),
    const SizedBox(height: 4),
    TextFormField(
      controller: c, obscureText: obscure, validator: validator, keyboardType: keyboard,
      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: 'monospace'),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: 'monospace'),
        prefixIcon: Icon(icon, size: 14, color: AppColors.textMuted),
        suffixIcon: suffix,
        filled: true, fillColor: AppColors.surface1,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentCyan)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.critical)),
      ),
    ),
  ]);

  Widget _dropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.textSecondary)),
    const SizedBox(height: 4),
    DropdownButtonFormField<String>(
      initialValue: value,
      onChanged: onChanged,
      dropdownColor: AppColors.surface1,
      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: 'monospace'),
      decoration: InputDecoration(filled: true, fillColor: AppColors.surface1, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border))),
      items: items.map((e)=> DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 11)))).toList(),
    ),
  ]);

  /// Import a key file's CONTENT into the credential field
  /// (sandbox-safe: the picker grants read access, typed paths don't).
  Future<void> _importKeyFile() async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return;
    try {
      final pem = utf8.decode(await files.first.readAsBytes()).trim();
      if (!pem.contains('PRIVATE KEY') && !pem.contains('OPENSSH')) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Not a private key file', style: TextStyle(fontSize: 12, color: AppColors.critical))));
        return;
      }
      setState(() => _cred.text = pem);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.surface1, content: Text('Imported ${files.first.name} ✓ — save the server, then Test/CONNECT', style: const TextStyle(fontSize: 12, color: AppColors.success))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.surface1, content: Text('Import failed: $e', style: const TextStyle(fontSize: 12, color: AppColors.critical))));
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final id = widget.existing?.id ?? const Uuid().v4();
    final s = ServerConnection(
      id: id, name: _name.text.trim(), host: _host.text.trim(), port: int.parse(_port.text.trim()), username: _user.text.trim(),
      authMethod: _auth, credential: _cred.text, region: _region, os: _os, env: _env, tags: _tags.text.trim().isEmpty ? null : _tags.text.trim(), createdAt: widget.existing?.createdAt ?? DateTime.now(), enabled: widget.existing?.enabled ?? true,
    );
    Navigator.pop(context, s);
  }
}
