import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PitchCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? footer;
  final VoidCallback? onTap;
  final double? height;
  const PitchCard({super.key, required this.child, this.padding, this.margin, this.title, this.subtitle, this.trailing, this.footer, this.onTap, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface0,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            splashColor: AppColors.borderLight,
            child: Padding(
              padding: padding ?? const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(title!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(subtitle!, style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w400)),
                            ]
                          ]),
                        ),
                        if (trailing != null) trailing!,
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                  ],
                  child,
                  if (footer != null) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    footer!,
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String label;
  final String count;
  final IconData icon;
  final Color accent;
  const SectionHeader({super.key, required this.label, required this.count, required this.icon, required this.accent});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8), border: Border.all(color: accent.withValues(alpha: 0.2))),
        child: Icon(icon, size: 14, color: accent),
      ),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
        child: Text(count, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

class StatusDot extends StatelessWidget {
  final Color color;
  final bool pulse;
  const StatusDot({super.key, required this.color, this.pulse = true});
  @override
  Widget build(BuildContext context) {
    return Stack(alignment: Alignment.center, children: [
      if (pulse) Container(width: 16, height: 16, decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle)),
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)])),
    ]);
  }
}

class MetricBar extends StatelessWidget {
  final String label;
  final double value; // 0-1
  final Color color;
  const MetricBar({super.key, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
        Text('${(value * 100).toInt()}%', style: TextStyle(color: value > 0.8 ? AppColors.critical : value > 0.6 ? AppColors.warning : AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: value, minHeight: 4, backgroundColor: AppColors.surface2, valueColor: AlwaysStoppedAnimation(color)),
      ),
    ]);
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final Color? bg;
  const Pill({super.key, required this.text, required this.color, this.bg});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: bg ?? color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.22))),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
    );
  }
}
