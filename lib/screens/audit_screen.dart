import 'package:flutter/material.dart';
import '../models/audit_entry.dart';
import '../services/audit_log.dart';
import '../theme/app_theme.dart';
import '../widgets/pitch_card.dart';

/// Full-screen AI audit trail: every tool call, decision, and outcome.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  List<AuditEntry> _entries = [];
  bool _loading = true;
  String _filter = 'all'; // all, approved, denied, blocked, auto
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AuditLog.read();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  List<AuditEntry> get _filtered =>
      _filter == 'all' ? _entries : _entries.where((e) => e.decision == _filter).toList();

  Color _decisionColor(String d) {
    switch (d) {
      case 'approved':
        return AppColors.success;
      case 'denied':
        return AppColors.critical;
      case 'blocked':
        return AppColors.warning;
      default:
        return AppColors.accentCyan;
    }
  }

  IconData _decisionIcon(String d) {
    switch (d) {
      case 'approved':
        return Icons.check_circle_outline;
      case 'denied':
        return Icons.cancel_outlined;
      case 'blocked':
        return Icons.block_outlined;
      default:
        return Icons.info_outline;
    }
  }

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pitchBlack,
      appBar: AppBar(
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, size: 18, color: AppColors.textSecondary)),
        title: const Text('AI AUDIT TRAIL', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            icon: const Icon(Icons.refresh, size: 17, color: AppColors.textSecondary),
          ),
          IconButton(
            tooltip: 'Clear all',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surface1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.border)),
                  title: const Text('Clear audit trail?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  content: const Text('All recorded tool runs will be deleted.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCEL', style: TextStyle(color: AppColors.textSecondary))),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: AppColors.critical, foregroundColor: Colors.white), child: const Text('CLEAR')),
                  ],
                ),
              );
              if (ok == true) {
                await AuditLog.clear();
                if (mounted) setState(() => _entries = []);
              }
            },
            icon: const Icon(Icons.delete_outline, size: 17, color: AppColors.textSecondary),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accentCyan))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, children: [
                  for (final f in ['all', 'approved', 'auto', 'denied', 'blocked'])
                    ChoiceChip(
                      label: Text(
                          '${f[0].toUpperCase()}${f.substring(1)}${f == 'all' ? ' (${_entries.length})' : ''}',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _filter == f ? Colors.black : AppColors.textSecondary)),
                      selected: _filter == f,
                      selectedColor: AppColors.accentCyan,
                      backgroundColor: AppColors.surface2,
                      side: BorderSide(color: _filter == f ? AppColors.accentCyan : AppColors.border),
                      onSelected: (_) => setState(() => _filter = f),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                ]),
                const SizedBox(height: 12),
                if (_filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('No audit entries yet.\nAsk the AI to check something — reads are logged too.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textMuted))),
                  )
                else
                  for (final e in _filtered) _auditTile(e),
                const SizedBox(height: 8),
                const Center(child: Text('CAPPED AT 200 NEWEST • STORED ON-DEVICE', style: TextStyle(fontSize: 9, letterSpacing: 0.7, color: AppColors.textDim, fontWeight: FontWeight.w600))),
              ]),
            ),
    );
  }

  Widget _auditTile(AuditEntry e) {
    final open = _expanded.contains(e.id);
    final c = _decisionColor(e.decision);
    return PitchCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      child: InkWell(
        onTap: () => setState(() => open ? _expanded.remove(e.id) : _expanded.add(e.id)),
        borderRadius: BorderRadius.circular(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 28, height: 28, decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(7), border: Border.all(color: c.withValues(alpha: 0.25))), child: Icon(_decisionIcon(e.decision), size: 14, color: c)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.tool, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: AppFonts.mono)),
              Text('${_timeAgo(e.time)} • ${e.provider} • ${e.model} • ${e.durationMs}ms', style: const TextStyle(fontSize: 9, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            Pill(text: e.decision.toUpperCase(), color: c),
            const SizedBox(width: 4),
            Icon(open ? Icons.expand_less : Icons.expand_more, size: 14, color: AppColors.textDim),
          ]),
          Text(e.result, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary), maxLines: open ? null : 2, overflow: open ? TextOverflow.visible : TextOverflow.ellipsis),
          if (open && e.args.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF050505), borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
              child: SelectableText(
                e.args.entries.map((a) => '${a.key}: ${a.value}').join('\n'),
                style: const TextStyle(fontSize: 10, color: AppColors.accentCyan, fontFamily: AppFonts.mono),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
