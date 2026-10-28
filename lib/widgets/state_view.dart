import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';

/// Shared async-surface state (spec: `docs/design/04-state-patterns.md`).
///
/// One widget for every loading / empty / error box in the app — GitHub,
/// CI/CD deploys, log tail, and the AI chat drawer. No bespoke per-screen
/// empty boxes after this.
enum PanelState { data, loading, empty, error }

class StateView extends StatelessWidget {
  /// Which frame to render. `data` renders nothing (caller shows content).
  final PanelState state;

  /// Empty/error iconography. Always carries [semanticLabel] — names, not colors.
  final IconData icon;

  /// 13px w700 primary — what is true.
  final String headline;

  /// 11px secondary — why + what to do. Never `textMuted` (fails contrast).
  final String body;

  /// Optional action label, e.g. 'OPEN SETTINGS', 'RETRY'. Rendered as a
  /// real `FilledButton` (48px min touch target), never a bare InkWell.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Semantic label for the icon / loading region (screen-reader name).
  final String? semanticLabel;

  /// Loading text announced via the live region (default 'Loading …').
  final String loadingLabel;

  /// Pass through from the calling segment (compact cards get tighter padding).
  final bool compact;

  const StateView({
    super.key,
    required this.state,
    this.icon = Icons.inbox_outlined,
    this.headline = '',
    this.body = '',
    this.actionLabel,
    this.onAction,
    this.semanticLabel,
    this.loadingLabel = 'Loading …',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (state == PanelState.data) return const SizedBox.shrink();
    if (state == PanelState.loading) return _loading(context);
    final isError = state == PanelState.error;
    return Semantics(
      label: semanticLabel ?? (isError ? 'Sync failed' : 'No data'),
      liveRegion: isError,
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isError ? AppColors.warning : AppColors.textSecondary,
              semanticLabel: semanticLabel ?? (isError ? 'Sync failed' : 'No data'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              headline,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppType.title,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: AppType.body,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentCyan,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(48, 48),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadii.mdAll,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _loading(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final spinner = reduceMotion
        ? const Icon(
            Icons.refresh,
            size: 14,
            color: AppColors.accentCyan,
            semanticLabel: 'Syncing',
          )
        : const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accentCyan,
            ),
          );
    return Semantics(
      label: loadingLabel,
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            spinner,
            const SizedBox(width: AppSpacing.sm),
            Text(
              loadingLabel,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppType.body,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
