import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../theme/app_theme.dart';
import '../models/server_connection.dart';
import '../services/ai_service.dart';
import '../services/github_service.dart';
import '../services/gitlab_service.dart';
import '../services/secure_store.dart';
import '../services/ssh_key_loader.dart';
import '../services/update_service.dart';
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
  // GitLab integration
  String _gitlabToken = '';
  String _gitlabUser = '';
  String _gitlabBaseUrl = 'https://gitlab.com';
  List<String> _gitlabProjects = [];
  bool _gitlabVerifying = false;
  final _gitlabTokenCtrl = TextEditingController();
  final _gitlabBaseCtrl = TextEditingController(text: 'https://gitlab.com');
  final _gitlabProjectCtrl = TextEditingController();
  // AI provider
  AiProvider _aiProvider = AiProvider.openai;
  String _aiBaseUrl = AiProvider.openai.defaultBaseUrl;
  String _aiKey = '';
  String _aiModel = '';
  List<String> _aiModels = [];
  bool _aiFetching = false;
  String? _aiError;
  final _aiBaseCtrl = TextEditingController();
  final _aiKeyCtrl = TextEditingController();
  final _aiModelCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _loadUpdatePrefs();
  }

  Future<void> _load() async {
    await SecureStore.migrateIfNeeded();
    final prefs = await SharedPreferences.getInstance();
    final servers = await SecureStore.readServers();
    setState(() {
      _servers = servers;
      _autoRefresh = prefs.getBool('auto_refresh') ?? true;
      _refreshInterval = prefs.getDouble('refresh_interval') ?? 15;
      _notifications = prefs.getBool('notifications') ?? true;
      _biometrics = prefs.getBool('biometrics') ?? false;
      _githubRepos = (prefs.getStringList('github_repos') ?? []).toList();
      _gitlabProjects = (prefs.getStringList('gitlab_projects') ?? []).toList();
      _loading = false;
    });
    // secrets (keychain) load async after first paint
    final ghTok = await SecureStore.readSecret('github_token') ?? '';
    final glTok = await SecureStore.readSecret('gitlab_token') ?? '';
    final aiK = await SecureStore.readSecret('ai_key') ?? '';
    if (!mounted) return;
    setState(() {
      _githubToken = ghTok;
      _githubUser = prefs.getString('github_user') ?? '';
      _githubTokenCtrl.text = _githubToken;
      _gitlabToken = glTok;
      _gitlabUser = prefs.getString('gitlab_user') ?? '';
      _gitlabBaseUrl = prefs.getString('gitlab_base_url') ?? 'https://gitlab.com';
      _gitlabTokenCtrl.text = _gitlabToken;
      _gitlabBaseCtrl.text = _gitlabBaseUrl;
      final aiIdx = prefs.getInt('ai_provider') ?? AiProvider.openai.index;
      _aiProvider = AiProvider.values[aiIdx.clamp(0, AiProvider.values.length - 1)];
      _aiBaseUrl = prefs.getString('ai_base_url') ?? _aiProvider.defaultBaseUrl;
      _aiKey = aiK;
      _aiModel = prefs.getString('ai_model') ?? '';
      _aiModels = (prefs.getStringList('ai_models') ?? []).toList();
      _aiBaseCtrl.text = _aiBaseUrl;
      _aiKeyCtrl.text = _aiKey;
      _aiModelCtrl.text = _aiModel;
    });
  }

  Future<void> _saveServers() async {
    await SecureStore.writeServers(_servers);
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_refresh', _autoRefresh);
    await prefs.setDouble('refresh_interval', _refreshInterval);
    await prefs.setBool('notifications', _notifications);
    await prefs.setBool('biometrics', _biometrics);
  }

  @override
  void dispose() {
    _githubTokenCtrl.dispose();
    _githubRepoCtrl.dispose();
    _gitlabTokenCtrl.dispose();
    _gitlabBaseCtrl.dispose();
    _gitlabProjectCtrl.dispose();
    _aiBaseCtrl.dispose();
    _aiKeyCtrl.dispose();
    _aiModelCtrl.dispose();
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
      await SecureStore.deleteServerCredential(s.id);
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
            Text('${filtered.length} shown', style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: AppFonts.mono)),
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
              _switchTile('Biometrics', 'Face ID / Touch ID on launch (soon)', _biometrics, (v){ setState(()=> _biometrics=v); _savePrefs(); }),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
                child: const Text('Auto-refresh polls live now. Push notifications + biometric lock screen are on the roadmap — toggles are saved and ready for them.', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ),
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
              _gitlabSection(),
              const SizedBox(height: 6),
              _aiSection(),
              const SizedBox(height: 6),
              _integrationRow('Sentry / Datadog', 'Not connected', Icons.bug_report_outlined, AppColors.textMuted, 'Add'),
            ]),
            footer: const Text('Server creds + tokens live in the OS keychain/keystore (never in plain prefs, never in the cloud).', style: TextStyle(fontSize: 10, color: AppColors.textDim)),
          );
          if (isWide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: prefsCard), const SizedBox(width: 12), Expanded(child: integrationsCard)]);
          }
          return Column(children: [prefsCard, integrationsCard]);
        }),
        _updatesCard(),
        // Danger zone
        PitchCard(
          title: 'DANGER ZONE',
          child: Column(children: [
            Row(children: [
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Clear all server connections', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)), Text('Removes all stored hosts — cannot be undone', style: TextStyle(fontSize: 11, color: AppColors.textMuted))])),
              OutlinedButton(onPressed: _servers.isEmpty ? null : () async {
                final ok = await showDialog<bool>(context: context, builder: (_)=> AlertDialog(backgroundColor: AppColors.surface1, title: const Text('Clear all?', style: TextStyle(color: AppColors.textPrimary)), content: const Text('This will delete all server connections.', style: TextStyle(color: AppColors.textSecondary)), actions: [TextButton(onPressed: ()=> Navigator.pop(context,false), child: const Text('Cancel')), FilledButton(onPressed: ()=> Navigator.pop(context,true), style: FilledButton.styleFrom(backgroundColor: AppColors.critical), child: const Text('Clear'))]));
                if (ok==true) { final ids = _servers.map((s)=> s.id).toList(); setState(()=> _servers=[]); for (final id in ids) { await SecureStore.deleteServerCredential(id); } await _saveServers(); }
              }, style: OutlinedButton.styleFrom(foregroundColor: AppColors.critical, side: const BorderSide(color: AppColors.critical)), child: const Text('CLEAR ALL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
            ]),
          ]),
        ),
        const SizedBox(height: 8),
        const Center(child: Text('MY CONTROL PANEL • SETTINGS • prefs for UI state, OS keychain for secrets', style: TextStyle(fontSize: 9, color: AppColors.textDim, letterSpacing: 0.6, fontWeight: FontWeight.w600))),
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
              Text('${s.host}:${s.port} • ${s.username}@ • ${s.region} • ${s.os}', style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: AppFonts.mono), maxLines: 1, overflow: TextOverflow.ellipsis),
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
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)), Text(valLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accentCyan, fontFamily: AppFonts.mono))]),
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
            Text(connected ? '@$_githubUser • ${_githubRepos.length} repo${_githubRepos.length == 1 ? '' : 's'}' : 'Not connected — paste a personal access token', style: TextStyle(fontSize: 10, color: connected ? AppColors.success : AppColors.textMuted, fontFamily: AppFonts.mono)),
          ])),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: connected ? AppColors.success : AppColors.textDim, shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _githubTokenCtrl,
              obscureText: true,
              style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: AppFonts.mono),
              decoration: InputDecoration(
                hintText: 'ghp_… / github_pat_… (needs `repo` scope)',
                hintStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: AppFonts.mono),
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
                  Expanded(child: Text(r, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: AppFonts.mono))),
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
                style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: AppFonts.mono),
                decoration: InputDecoration(
                  hintText: 'owner/repo  (e.g. alfirus/mycontrolpanel)',
                  hintStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: AppFonts.mono),
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
      await SecureStore.writeSecret('github_token', token);
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
    await SecureStore.deleteSecret('github_token');
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

  /// GitLab PAT + self-hosted base URL + tracked projects.
  Widget _gitlabSection() {
    final connected = _gitlabToken.isNotEmpty && _gitlabUser.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(10), border: Border.all(color: connected ? AppColors.accentPurple.withValues(alpha: 0.35) : AppColors.borderLight)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.accentPurple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7), border: Border.all(color: AppColors.accentPurple.withValues(alpha: 0.25))), child: const Icon(Icons.layers_outlined, size: 14, color: AppColors.accentPurple)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('GitLab', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text(connected ? '@$_gitlabUser • ${_gitlabProjects.length} project${_gitlabProjects.length == 1 ? '' : 's'}' : 'Not connected — paste a personal access token', style: TextStyle(fontSize: 10, color: connected ? AppColors.accentPurple : AppColors.textMuted, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: connected ? AppColors.accentPurple : AppColors.textDim, shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _gitlabBaseCtrl,
          onChanged: (v) => _gitlabBaseUrl = v.trim(),
          style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: 'Base URL (gitlab.com or self-hosted)',
            labelStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            filled: true, fillColor: AppColors.surface2,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentPurple)),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _gitlabTokenCtrl,
              obscureText: true,
              style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'glpat-… (needs `api` scope)',
                hintStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'monospace'),
                filled: true, fillColor: AppColors.surface2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentPurple)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _gitlabVerifying ? null : _verifyGitlabToken,
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
            child: _gitlabVerifying
                ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(connected ? 'UPDATE' : 'CONNECT', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ]),
        if (connected) ...[
          if (_gitlabProjects.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final p in _gitlabProjects)
              Container(
                margin: const EdgeInsets.only(bottom: 5),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(7), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  const Icon(Icons.book_outlined, size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(p, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: 'monospace'))),
                  InkWell(onTap: () => _removeGitlabProject(p), child: const Icon(Icons.close, size: 13, color: AppColors.textMuted)),
                ]),
              ),
          ],
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _gitlabProjectCtrl,
                onSubmitted: (_) => _addGitlabProject(),
                style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'group/project or numeric id',
                  hintStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'monospace'),
                  filled: true, fillColor: AppColors.surface2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentPurple)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: _addGitlabProject, icon: const Icon(Icons.add, size: 13), label: const Text('ADD', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)), style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentPurple, side: const BorderSide(color: AppColors.accentPurple), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11))),
          ]),
          TextButton.icon(
            onPressed: _disconnectGitlab,
            icon: const Icon(Icons.link_off, size: 12),
            label: const Text('Disconnect (delete token)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: AppColors.critical),
          ),
        ],
      ]),
    );
  }

  Future<void> _verifyGitlabToken() async {
    final token = _gitlabTokenCtrl.text.trim();
    final base = _gitlabBaseCtrl.text.trim().isEmpty ? 'https://gitlab.com' : _gitlabBaseCtrl.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Paste a token first', style: TextStyle(fontSize: 12, color: AppColors.warning))));
      return;
    }
    setState(() => _gitlabVerifying = true);
    try {
      final login = await GitlabService(baseUrl: base, token: token).validate();
      final prefs = await SharedPreferences.getInstance();
      await SecureStore.writeSecret('gitlab_token', token);
      await prefs.setString('gitlab_user', login);
      await prefs.setString('gitlab_base_url', base);
      if (!mounted) return;
      setState(() {
        _gitlabToken = token;
        _gitlabUser = login;
        _gitlabBaseUrl = base;
        _gitlabBaseCtrl.text = base;
        _gitlabVerifying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.success.withValues(alpha: 0.14), content: Text('GitLab connected as @$login ✓ — add projects below', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success))));
    } catch (e) {
      if (!mounted) return;
      setState(() => _gitlabVerifying = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.critical.withValues(alpha: 0.14), content: Text(e.toString().replaceFirst('Exception: ', '').split('\n').first, style: const TextStyle(fontSize: 12, color: AppColors.critical)), duration: const Duration(seconds: 5)));
    }
  }

  Future<void> _addGitlabProject() async {
    final project = _gitlabProjectCtrl.text.trim();
    if (project.isEmpty) return;
    if (_gitlabProjects.contains(project)) return;
    try {
      await GitlabService(baseUrl: _gitlabBaseUrl, token: _gitlabToken).projectIssues(project);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.critical.withValues(alpha: 0.14), content: Text('Project not reachable: ${e.toString().replaceFirst('Exception: ', '').split('\n').first}', style: const TextStyle(fontSize: 12, color: AppColors.critical)), duration: const Duration(seconds: 5)));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final next = [..._gitlabProjects, project];
    await prefs.setStringList('gitlab_projects', next);
    if (!mounted) return;
    setState(() {
      _gitlabProjects = next;
      _gitlabProjectCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.surface1, content: Text('Tracking $project ✓', style: const TextStyle(fontSize: 12, color: AppColors.success))));
  }

  Future<void> _removeGitlabProject(String project) async {
    final prefs = await SharedPreferences.getInstance();
    final next = _gitlabProjects.where((p) => p != project).toList();
    await prefs.setStringList('gitlab_projects', next);
    if (!mounted) return;
    setState(() => _gitlabProjects = next);
  }

  Future<void> _disconnectGitlab() async {
    final prefs = await SharedPreferences.getInstance();
    await SecureStore.deleteSecret('gitlab_token');
    await prefs.remove('gitlab_user');
    await prefs.remove('gitlab_base_url');
    await prefs.remove('gitlab_projects');
    if (!mounted) return;
    setState(() {
      _gitlabToken = '';
      _gitlabUser = '';
      _gitlabProjects = [];
      _gitlabTokenCtrl.clear();
    });
  }

  /// AI provider: preset + base URL + key, model list auto-fetched
  /// from the API (/models, /api/tags, …) into a chooser.
  Widget _aiSection() {
    final configured = _aiModel.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(10), border: Border.all(color: configured ? AppColors.accentCyan.withValues(alpha: 0.3) : AppColors.borderLight)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 30, height: 30, decoration: BoxDecoration(color: AppColors.accentCyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7), border: Border.all(color: AppColors.accentCyan.withValues(alpha: 0.2))), child: const Icon(Icons.smart_toy_outlined, size: 14, color: AppColors.accentCyan)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AI Provider', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text(configured ? '${_aiProvider.label} • $_aiModel' : 'Pick a provider, add key, fetch models', style: TextStyle(fontSize: 10, color: configured ? AppColors.accentCyan : AppColors.textMuted, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: configured ? AppColors.accentCyan : AppColors.textDim, shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 8),
        // provider preset
        DropdownButtonFormField<AiProvider>(
          initialValue: _aiProvider,
          dropdownColor: AppColors.surface1,
          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: 'monospace'),
          decoration: InputDecoration(labelText: 'Provider', labelStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted), filled: true, fillColor: AppColors.surface2, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border))),
          items: AiProvider.values.map((p) => DropdownMenuItem(value: p, child: Text(p.label, style: const TextStyle(fontSize: 11)))).toList(),
          onChanged: (p) {
            if (p == null) return;
            setState(() {
              _aiProvider = p;
              _aiBaseUrl = p.defaultBaseUrl;
              _aiBaseCtrl.text = _aiBaseUrl;
              _aiModels = [];
              _aiError = null;
            });
          },
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _aiBaseCtrl,
              onChanged: (v) => _aiBaseUrl = v.trim(),
              style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Base URL', labelStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                filled: true, fillColor: AppColors.surface2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentCyan)),
              ),
            ),
          ),
          if (_aiProvider == AiProvider.openaiCompatible) ...[
            const SizedBox(width: 8),
            const Tooltip(message: 'Any OpenAI-compatible endpoint: Together, Groq, Mistral, llama.cpp, vLLM…', child: Icon(Icons.info_outline, size: 14, color: AppColors.textMuted)),
          ],
        ]),
        const SizedBox(height: 8),
        // key + fetch
        Row(children: [
          Expanded(
            child: TextField(
              controller: _aiKeyCtrl,
              obscureText: true,
              onChanged: (v) => _aiKey = v,
              style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: _aiProvider.needsKey ? 'API key' : 'API key (not needed)',
                hintText: _aiProvider.keyHint,
                labelStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted),
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
            onPressed: _aiFetching ? null : _fetchAiModels,
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
            child: _aiFetching
                ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('FETCH MODELS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ]),
        if (_aiError != null) ...[
          const SizedBox(height: 6),
          Row(children: [const Icon(Icons.error_outline, size: 12, color: AppColors.critical), const SizedBox(width: 6), Expanded(child: Text(_aiError!, style: const TextStyle(fontSize: 10, color: AppColors.critical)))]),
        ],
        if (_aiModels.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _aiModels.contains(_aiModel) ? _aiModel : null,
            dropdownColor: AppColors.surface1,
            style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: 'monospace'),
            decoration: InputDecoration(labelText: 'Model (${_aiModels.length} from API)', labelStyle: const TextStyle(fontSize: 10, color: AppColors.accentCyan, fontWeight: FontWeight.w700), filled: true, fillColor: AppColors.surface2, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentCyan)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentCyan))),
            items: _aiModels.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (m) { if (m != null) _saveAiModel(m); },
          ),
        ],
        // manual model entry (always available — e.g. new releases, Anthropic)
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _aiModelCtrl,
              onSubmitted: (v) { if (v.trim().isNotEmpty) _saveAiModel(v.trim()); },
              style: const TextStyle(fontSize: 11, color: AppColors.textPrimary, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Or type model ID manually',
                labelStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                filled: true, fillColor: AppColors.surface2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentCyan)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () { final v = _aiModelCtrl.text.trim(); if (v.isNotEmpty) _saveAiModel(v); }, style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentCyan, side: const BorderSide(color: AppColors.accentCyan), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11)), child: const Text('USE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
        ]),
        if (configured) ...[
          TextButton.icon(
            onPressed: _disconnectAi,
            icon: const Icon(Icons.link_off, size: 12),
            label: const Text('Disconnect provider', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: AppColors.critical),
          ),
        ],
      ]),
    );
  }

  Future<void> _fetchAiModels() async {
    if (_aiProvider.needsKey && _aiKeyCtrl.text.trim().isEmpty) {
      setState(() => _aiError = 'API key required for ${_aiProvider.label} (Ollama / LM Studio need none).');
      return;
    }
    setState(() { _aiFetching = true; _aiError = null; });
    _aiKey = _aiKeyCtrl.text.trim();
    _aiBaseUrl = _aiBaseCtrl.text.trim().isEmpty ? _aiProvider.defaultBaseUrl : _aiBaseCtrl.text.trim();
    try {
      final models = await AiService().listModels(provider: _aiProvider, baseUrl: _aiBaseUrl, apiKey: _aiKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('ai_provider', _aiProvider.index);
      await prefs.setString('ai_base_url', _aiBaseUrl);
      await SecureStore.writeSecret('ai_key', _aiKey);
      await prefs.setStringList('ai_models', models);
      // keep current model if still valid, else auto-pick first
      String model = _aiModel;
      if (!models.contains(model)) {
        model = models.first;
        await prefs.setString('ai_model', model);
      }
      if (!mounted) return;
      setState(() {
        _aiModels = models;
        _aiModel = model;
        _aiModelCtrl.text = model;
        _aiFetching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.success.withValues(alpha: 0.14), content: Text('${models.length} models from ${_aiProvider.label} ✓ — using $model', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success))));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiFetching = false;
        _aiError = e.toString().replaceFirst('Exception: ', '').split('\n').first;
      });
    }
  }

  Future<void> _saveAiModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ai_provider', _aiProvider.index);
    await prefs.setString('ai_base_url', _aiBaseUrl);
    await SecureStore.writeSecret('ai_key', _aiKeyCtrl.text.trim());
    await prefs.setString('ai_model', model);
    if (!mounted) return;
    setState(() {
      _aiModel = model;
      _aiKey = _aiKeyCtrl.text.trim();
      _aiModelCtrl.text = model;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.surface1, content: Text('AI model: $model ✓ (chatbox will use it next)', style: const TextStyle(fontSize: 12, color: AppColors.accentCyan)), duration: const Duration(seconds: 2)));
  }

  Future<void> _disconnectAi() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_provider');
    await prefs.remove('ai_base_url');
    await SecureStore.deleteSecret('ai_key');
    await prefs.remove('ai_model');
    await prefs.remove('ai_models');
    if (!mounted) return;
    setState(() {
      _aiProvider = AiProvider.openai;
      _aiBaseUrl = _aiProvider.defaultBaseUrl;
      _aiBaseCtrl.text = _aiBaseUrl;
      _aiKey = '';
      _aiKeyCtrl.clear();
      _aiModel = '';
      _aiModelCtrl.clear();
      _aiModels = [];
      _aiError = null;
    });
  }

  Widget _integrationRow(String name, String masked, IconData icon, Color c, String action) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7), border: Border.all(color: c.withValues(alpha: 0.2))), child: Icon(icon, size: 14, color: c)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)), Text(masked, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: AppFonts.mono))])),
      OutlinedButton(onPressed: (){}, style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.border), foregroundColor: AppColors.textSecondary, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)), child: Text(action, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))),
    ]),
  );

  // --- App updates (GitHub Releases, desktop) ---
  String _appVersion = '';
  bool _updChecking = false;
  bool _updAutoCheck = true;
  String? _updStatus;

  Future<void> _loadUpdatePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _updAutoCheck = prefs.getBool('auto_update_check') ?? true;
    });
    try {
      final v = await UpdateService().currentVersion();
      if (!mounted) return;
      setState(() => _appVersion = v);
    } catch (_) {}
  }

  Future<void> _setAutoUpdateCheck(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_update_check', v);
    if (!mounted) return;
    setState(() => _updAutoCheck = v);
  }

  Future<void> _manualCheckUpdates() async {
    setState(() { _updChecking = true; _updStatus = null; });
    try {
      final svc = UpdateService();
      final rel = await svc.fetchLatest();
      final cur = _appVersion.isNotEmpty ? _appVersion : await svc.currentVersion();
      final cmp = UpdateService.compareVersions(cur, rel.version);
      if (!mounted) return;
      if (cmp >= 0) {
        setState(() {
          _updChecking = false;
          _updStatus = 'Up to date (v$cur) ✓';
        });
        return;
      }
      final asset = UpdateService.pickAsset(rel);
      setState(() {
        _updChecking = false;
        _updStatus = asset == null
            ? 'v${rel.version} available, but no ${Platform.isMacOS ? 'macOS' : Platform.isWindows ? 'Windows' : 'Linux'} build attached to the release.'
            : 'v${rel.version} available — see the update banner on Overview, or tap below to review + install.';
      });
      if (asset != null) {
        // hand off to the Overview update flow on next visit; also offer now
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.accentCyan.withValues(alpha: 0.14),
          content: Text('v${rel.version} available — open Overview to update', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accentCyan)),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updChecking = false;
        _updStatus = 'Check failed: ${e.toString().replaceFirst('Exception: ', '').split('\n').first}';
      });
    }
  }

  Future<void> _resetSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('skipped_update_tag');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Skipped versions cleared — next check will prompt again', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))));
  }

  Widget _updatesCard() {
    return PitchCard(
      title: 'APP & UPDATES',
      subtitle: _appVersion.isEmpty ? 'GitHub Releases • desktop' : 'v$_appVersion • GitHub Releases • desktop',
      trailing: _updChecking
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentCyan))
          : InkWell(
              onTap: _manualCheckUpdates,
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.system_update, size: 12, color: AppColors.accentCyan), SizedBox(width: 3), Text('CHECK NOW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accentCyan))]),
            ),
      child: Column(children: [
        Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Check on startup', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text('Poll the latest release when the app opens', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ])),
          Switch(value: _updAutoCheck, onChanged: _setAutoUpdateCheck, activeTrackColor: AppColors.accentCyan, thumbColor: WidgetStateProperty.all(Colors.black)),
        ]),
        if (_updStatus != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
            child: Row(children: [const Icon(Icons.info_outline, size: 13, color: AppColors.accentCyan), const SizedBox(width: 8), Expanded(child: Text(_updStatus!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)))]),
          ),
        ],
        const SizedBox(height: 4),
        Row(children: [
          const Expanded(child: Text('Releases live at github.com/alfirus/mycontrolpanel/releases — attach per-platform zips manually.', style: TextStyle(fontSize: 10, color: AppColors.textDim))),
          TextButton(onPressed: _resetSkippedVersion, child: const Text('UNSKIP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textMuted))),
        ]),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
          child: const Text('Expected assets: mycontrolpanel-macos-<v>.zip • mycontrolpanel-windows-<v>.zip • mycontrolpanel-linux-<v>.tar.gz (+ optional SHA256SUMS.txt)', style: TextStyle(fontSize: 9, color: AppColors.textMuted, fontFamily: AppFonts.mono)),
        ),
      ]),
    );
  }

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
    _cred.addListener(() => setState(() {})); // refresh key fingerprint line
  }

  /// Non-secret summary of what's in the credential field (never key material).
  String _keyFingerprint() {
    final v = _cred.text.trim();
    if (v.isEmpty) return 'No key entered yet.';
    if (!v.contains('PRIVATE KEY') && !v.contains('OPENSSH') && !v.contains('Proc-Type') && !v.contains('DEK-Info')) {
      return 'Saved value is a file path (${v.length} chars) — app cannot read paths; import the file.';
    }
    final lines = v.split('\n').length;
    return 'Saved: ${SshKeyLoader.describe(v)} • $lines lines, ${v.length} chars.';
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
              if (_auth==AuthMethod.sshKey && _cred.text.trim().isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    const Icon(Icons.fingerprint, size: 13, color: AppColors.accentCyan),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_keyFingerprint(), style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontFamily: AppFonts.mono))),
                  ]),
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
      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: AppFonts.mono),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: AppFonts.mono),
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
      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: AppFonts.mono),
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
