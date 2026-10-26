import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../models/server_connection.dart';
import '../services/agent_service.dart';
import '../services/ssh_key_loader.dart';
import '../widgets/pitch_card.dart';

class TerminalLine {
  final String text;
  final Color color;
  final bool isCommand;
  TerminalLine(this.text, {this.color = AppColors.textPrimary, this.isCommand = false});
}

class TerminalScreen extends StatefulWidget {
  final String? initialServerId;
  final String? prefillCommand;
  const TerminalScreen({super.key, this.initialServerId, this.prefillCommand});

  @override
  State<TerminalScreen> createState() => TerminalScreenState();
}

class TerminalScreenState extends State<TerminalScreen> {
  List<ServerConnection> _servers = [];
  ServerConnection? _selected;
  bool _connected = false;
  bool _busy = false;
  SSHClient? _client;
  final List<TerminalLine> _lines = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  List<String> _history = [];
  int _historyIdx = -1;

  @override
  void initState() {
    super.initState();
    _print('MyControlPanel Terminal — in-app SSH + local shell', AppColors.accentCyan);
    _print('Type `help` for commands.', AppColors.textMuted);
    _load().then((_) {
      if (widget.prefillCommand != null) {
        _input.text = widget.prefillCommand!;
        _print('Install command loaded below — press Enter to run it on ${_selected?.host ?? 'the server'}.', AppColors.warning);
      }
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('server_connections');
    setState(() {
      _servers = raw == null ? [] : ServerConnection.decodeList(raw);
      if (_servers.isNotEmpty) {
        _selected = widget.initialServerId != null
            ? _servers.where((s) => s.id == widget.initialServerId).firstOrNull ?? _servers.first
            : _servers.first;
      }
    });
    if (_selected != null) _print('Target: ${_selected!.username}@${_selected!.host}:${_selected!.port} (${_selected!.authMethod.name})', AppColors.textSecondary);
  }

  void _print(String t, [Color c = AppColors.textPrimary, bool cmd = false]) {
    setState(() => _lines.add(TerminalLine(t, color: c, isCommand: cmd)));
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
    });
  }

  Future<void> _connect() async {
    final s = _selected;
    if (s == null) {
      _print('No server selected. Add one in Settings first.', AppColors.critical);
      return;
    }
    // Resolve auth: password OR saved key path / pasted key content.
    List<SSHKeyPair>? keyPairs;
    String? Function()? passwordCb;
    if (s.authMethod == AuthMethod.password) {
      passwordCb = () => s.credential;
      _print('\$ ssh ${s.username}@${s.host} -p ${s.port}', AppColors.textMuted, true);
    } else {
      _print('\$ ssh -i <saved key> ${s.username}@${s.host} -p ${s.port}', AppColors.textMuted, true);
      _print('Loading saved key...', AppColors.textMuted);
      var loaded = await SshKeyLoader.load(s.credential);
      if (loaded.needsPassphrase) {
        final pass = await _askPassphrase();
        if (pass == null) { _print('Cancelled.', AppColors.textMuted); return; }
        loaded = await SshKeyLoader.load(s.credential, passphrase: pass);
      }
      if (loaded.keys == null) {
        _print('Key failed: ${loaded.error}', AppColors.critical);
        _print('Fix: Settings → edit server → paste key CONTENT (not path), or use folder button below to pick the .pem.', AppColors.warning);
        return;
      }
      keyPairs = loaded.keys;
      _print('Key loaded (${keyPairs!.length} identity) — connecting...', AppColors.textMuted);
    }
    setState(() => _busy = true);
    try {
      final socket = await SSHSocket.connect(s.host, s.port, timeout: const Duration(seconds: 10));
      _client = SSHClient(socket,
          username: s.username,
          onPasswordRequest: passwordCb,
          identities: keyPairs ?? const []);
      await _client!.authenticated.timeout(const Duration(seconds: 15));
      setState(() { _connected = true; _busy = false; });
      _print('Connected to ${s.host} ✓ (${s.authMethod == AuthMethod.password ? 'password' : 'key'})', AppColors.success);
      _print('Tip: type `install-agent`, paste the command, or run any shell command.', AppColors.textMuted);
    } catch (e) {
      setState(() => _busy = false);
      _print('SSH failed: $e', AppColors.critical);
      if (e.toString().contains('publickey') || e.toString().contains('auth')) {
        _print('Auth rejected: check the key matches ~/.ssh/authorized_keys on the server.', AppColors.warning);
      }
    }
  }

  /// Prompts for an encrypted-key passphrase inside the app.
  Future<String?> _askPassphrase() async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
        title: const Text('Key passphrase', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: TextField(controller: c, obscureText: true, autofocus: true, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: AppFonts.mono), decoration: InputDecoration(hintText: 'Passphrase for private key', hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted), filled: true, fillColor: AppColors.surface2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentCyan)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL', style: TextStyle(color: AppColors.textSecondary))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black), child: const Text('UNLOCK')),
        ],
      ),
    );
  }

  /// Let user pick a .pem via file dialog (grants sandbox read access),
  /// then saves the CONTENT into the server's credential.
  Future<void> _pickKeyFile() async {
    final s = _selected;
    if (s == null) return;
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return;
    String? pem;
    final f = files.first;
    try {
      pem = utf8.decode(await f.readAsBytes());
    } catch (e) {
      _print('Cannot read picked file: $e', AppColors.critical);
      return;
    }
    if (pem == null || !pem.contains('PRIVATE KEY')) {
      _print('Picked file is not a private key.', AppColors.critical);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('server_connections');
    if (raw == null) return;
    final list = ServerConnection.decodeList(raw);
    final idx = list.indexWhere((e) => e.id == s.id);
    if (idx == -1) return;
    list[idx] = list[idx].copyWith(credential: pem.trim(), authMethod: AuthMethod.sshKey);
    await prefs.setString('server_connections', ServerConnection.encodeList(list));
    setState(() => _selected = list[idx]);
    _print('Key imported (${f.name}) and saved to ${s.name} ✓ — tap CONNECT.', AppColors.success);
  }

  void _disconnect() {
    try { _client?.close(); } catch (_) {}
    _client = null;
    setState(() => _connected = false);
    _print('Disconnected.', AppColors.textMuted);
  }

  Future<void> _run(String raw) async {
    final cmd = raw.trim();
    if (cmd.isEmpty) return;
    _print('${_connected ? '${_selected!.username}@${_selected!.host}' : 'local'} \$ $cmd', AppColors.accentCyan, true);
    _history.add(cmd);
    _historyIdx = _history.length;
    _input.clear();
    if (cmd == 'help') {
      _print('Commands: connect | disconnect | install-agent | clear | copy <n> | run on server after connect', AppColors.textSecondary);
      return;
    }
    if (cmd == 'clear') { setState(() => _lines.clear()); return; }
    if (cmd == 'connect') { await _connect(); return; }
    if (cmd == 'disconnect') { _disconnect(); return; }
    if (cmd == 'install-agent') {
      _input.text = AgentService.manualInstallScript();
      _print('Install command loaded into input — press Enter to run${_connected ? '' : ' (connect first)'}', AppColors.warning);
      return;
    }
    // Guard: the agent installer must run ON the server, never locally.
    // Local macOS app-sandbox blocks sudo -> "/bin/sh: /usr/bin/sudo: Operation not permitted".
    final isInstaller = cmd.contains('mcp-agent') || cmd.contains('base64 -d');
    if (isInstaller && !(_connected && _client != null)) {
      _print('STOP — this command installs on the SERVER, not this Mac.', AppColors.critical);
      _print('The Mac app sandbox blocks sudo (that is the "Operation not permitted" error).', AppColors.warning);
      _print('Steps: 1) type `connect` + Enter  2) wait for "Connected ✓"  3) press ↑ to recall, Enter to run.', AppColors.textSecondary);
      _input.text = cmd; // keep it in the input for after connect
      return;
    }
    if (cmd.startsWith('sudo ') && !(_connected && _client != null)) {
      _print('Blocked: `sudo` is not permitted in the Mac app sandbox.', AppColors.critical);
      _print('Run sudo commands on the server instead: `connect` first.', AppColors.warning);
      return;
    }
    if (_connected && _client != null) {
      await _runRemote(cmd);
    } else {
      await _runLocal(cmd);
    }
  }

  Future<void> _runRemote(String cmd) async {
    setState(() => _busy = true);
    try {
      final session = await _client!.execute(cmd);
      final out = await session.stdout.cast<List<int>>().transform(utf8.decoder).join().timeout(const Duration(seconds: 60));
      final err = await session.stderr.cast<List<int>>().transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
      setState(() => _busy = false);
      if (out.trim().isNotEmpty) _print(out.trimRight(), AppColors.textPrimary);
      if (err.trim().isNotEmpty) _print(err.trimRight(), AppColors.warning);
      _print('[exit ${session.exitCode}]', AppColors.textDim);
    } catch (e) {
      setState(() => _busy = false);
      _print('Error: $e', AppColors.critical);
      if (e.toString().contains('closed')) setState(() => _connected = false);
    }
  }

  Future<void> _runLocal(String cmd) async {
    if (!(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      _print('Local shell only on desktop. Connect to a server first (`connect`).', AppColors.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      final parts = _split(cmd);
      final res = await Process.run(parts.first, parts.skip(1).toList(), runInShell: true).timeout(const Duration(seconds: 30));
      setState(() => _busy = false);
      final out = (res.stdout as String).trimRight();
      final err = (res.stderr as String).trimRight();
      if (out.isNotEmpty) _print(out, AppColors.textPrimary);
      if (err.isNotEmpty) {
        _print(err, AppColors.warning);
        if (err.contains('Operation not permitted') && (cmd.contains('sudo') || cmd.contains('mcp-agent'))) {
          _print('That is the macOS sandbox blocking sudo — run this on the server: `connect` first.', AppColors.critical);
        }
      }
      _print('[exit ${res.exitCode}]', AppColors.textDim);
    } catch (e) {
      setState(() => _busy = false);
      _print('Error: $e', AppColors.critical);
    }
  }

  List<String> _split(String cmd) {
    // minimal quote-aware split
    final out = <String>[];
    final buf = StringBuffer();
    var quote = '';
    for (var i = 0; i < cmd.length; i++) {
      final ch = cmd[i];
      if (quote.isNotEmpty) {
        if (ch == quote) { quote = ''; } else { buf.write(ch); }
      } else if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == ' ') {
        if (buf.isNotEmpty) { out.add(buf.toString()); buf.clear(); }
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out.isEmpty ? ['echo'] : out;
  }

  @override
  void dispose() {
    try { _client?.close(); } catch (_) {}
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)), child: const Icon(Icons.terminal, size: 16, color: AppColors.accentCyan)),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TERMINAL', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textPrimary)),
            Text('In-app SSH + local shell • build in here', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: _connected ? AppColors.success.withValues(alpha: 0.12) : AppColors.surface1, borderRadius: BorderRadius.circular(20), border: Border.all(color: _connected ? AppColors.success : AppColors.border)),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: _connected ? AppColors.success : AppColors.textMuted, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(_connected ? 'SSH LIVE' : 'NOT CONNECTED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _connected ? AppColors.success : AppColors.textMuted)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        PitchCard(
          title: 'SESSION',
          child: Column(children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<ServerConnection>(
                  initialValue: _selected,
                  dropdownColor: AppColors.surface1,
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: AppFonts.mono),
                  decoration: InputDecoration(filled: true, fillColor: AppColors.surface1, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border))),
                  items: _servers.map((s) => DropdownMenuItem(value: s, child: Text('${s.name} (${s.host})', style: const TextStyle(fontSize: 11)))).toList(),
                  onChanged: (v) { if (_connected) _disconnect(); setState(() => _selected = v); },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Import key file (.pem) into selected server',
                onPressed: _busy ? null : _pickKeyFile,
                icon: const Icon(Icons.folder_open, size: 16),
                style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary, backgroundColor: AppColors.surface2, padding: const EdgeInsets.all(12)),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _busy ? null : (_connected ? _disconnect : _connect),
                icon: Icon(_connected ? Icons.link_off : Icons.link, size: 13),
                label: Text(_connected ? 'DISCONNECT' : 'CONNECT', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(backgroundColor: _connected ? AppColors.critical : AppColors.accentCyan, foregroundColor: _connected ? Colors.white : Colors.black, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              _quickBtn('install-agent', 'Install agent cmd'),
              _quickBtn('curl -s http://127.0.0.1:9108/metrics', 'Check :9108'),
              _quickBtn('sudo systemctl status mcp-agent --no-pager', 'Service status'),
              _quickBtn('clear', 'Clear'),
            ]),
          ]),
        ),
        PitchCard(
          title: 'CONSOLE',
          subtitle: _connected ? 'remote ${_selected?.host}' : 'local shell (desktop) — connect for remote',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Copy all', icon: const Icon(Icons.copy, size: 13, color: AppColors.textMuted), onPressed: () { Clipboard.setData(ClipboardData(text: _lines.map((l) => l.text).join('\n'))); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: AppColors.surface1, content: Text('Console copied', style: TextStyle(fontSize: 12, color: AppColors.textPrimary)), duration: Duration(seconds: 1))); }),
            IconButton(tooltip: 'Clear', icon: const Icon(Icons.delete_outline, size: 13, color: AppColors.textMuted), onPressed: () => setState(() => _lines.clear())),
          ]),
          child: Column(children: [
            Container(
              height: 380,
              decoration: BoxDecoration(color: const Color(0xFF050505), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
              child: _lines.isEmpty
                  ? const Center(child: Text('No output yet — connect, then run a command.', style: TextStyle(fontSize: 11, color: AppColors.textDim, fontFamily: AppFonts.mono)))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(10),
                      itemCount: _lines.length,
                      itemBuilder: (_, i) {
                        final l = _lines[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: SelectableText(l.text, style: TextStyle(fontSize: 11, height: 1.4, color: l.color, fontFamily: AppFonts.mono, fontWeight: l.isCommand ? FontWeight.w700 : FontWeight.w400)),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Text(_connected ? '${_selected!.username}@${_selected!.host}:\$' : 'local\$', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accentCyan, fontFamily: AppFonts.mono)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _input, focusNode: _focus,
                  onSubmitted: _run,
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontFamily: AppFonts.mono),
                  decoration: InputDecoration(
                    hintText: _connected ? 'Run on ${_selected?.host}... (↑/↓ history)' : 'connect, or run local command...',
                    hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamily: AppFonts.mono),
                    filled: true, fillColor: AppColors.surface2,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accentCyan)),
                  ),
                  onTapOutside: (_) {},
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : () => _run(_input.text),
                style: FilledButton.styleFrom(backgroundColor: AppColors.accentCyan, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.all(12)),
                child: _busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.play_arrow, size: 16),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _quickBtn(String cmd, String label) => InkWell(
        onTap: () { _input.text = cmd; _focus.requestFocus(); },
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: AppColors.surface1, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)), child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
      );
}
