import 'package:flutter/material.dart';

/// Canonical design tokens for the MyControlPanel pitch-black theme.
///
/// Audit basis (2026-10-28, Kira): 213 `BorderRadius.circular` call sites
/// across lib/ cluster on just 10 distinct values (8px x99, 7px x27,
/// 12px x22, 6px x20, 10px x18, 4px x13, 16px x5, ...); `EdgeInsets.all`
/// clusters on 12/10/8/6; `fontSize` clusters on 10/11/12/9. These classes
/// freeze the blessed values so new code picks from the scale instead of
/// inventing a new radius. See `docs/design/01-design-tokens.md`.
@immutable
class AppSpacing {
  const AppSpacing._();

  /// 4pt grid. Named steps only — do not use raw doubles for card
  /// padding/margins in new code.
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;

  /// Standard gap between sibling controls inside a card body.
  static const double cardGap = 12.0;

  /// Standard gap between stacked cards / sections.
  static const double sectionGap = 16.0;
}

/// Canonical corner radii. The audit found 10 ad-hoc values in use;
/// new code must use one of these five.
@immutable
class AppRadii {
  const AppRadii._();

  /// Chips, badges, tiny containers (was: 3/4/6).
  static const double sm = 6.0;

  /// Buttons, icon tiles, inner containers (was: 7/8 — the dominant value).
  static const double md = 8.0;

  /// Nested surfaces, log viewer, server rows (was: 10/12).
  static const double lg = 12.0;

  /// Cards and sheets (PitchCard, cardTheme — was: 14/16).
  static const double xl = 16.0;

  /// Pills (was: 20).
  static const double pill = 20.0;

  static Radius get smRadius => const Radius.circular(sm);
  static Radius get mdRadius => const Radius.circular(md);
  static Radius get lgRadius => const Radius.circular(lg);
  static Radius get xlRadius => const Radius.circular(xl);
  static Radius get pillRadius => const Radius.circular(pill);

  static BorderRadius get smAll => BorderRadius.all(smRadius);
  static BorderRadius get mdAll => BorderRadius.all(mdRadius);
  static BorderRadius get lgAll => BorderRadius.all(lgRadius);
  static BorderRadius get xlAll => BorderRadius.all(xlRadius);
  static BorderRadius get pillAll => BorderRadius.all(pillRadius);
}

/// Canonical type sizes. The audit found `fontSize` clustering on
/// 8/9/10/11/12/13 with no scale; these names freeze the intent.
/// Weights/letter-spacing stay inline (w600-w800 + 0.3-0.8 tracking
/// for eyebrows) until the type ramp is ratified in
/// `docs/design/01-design-tokens.md`.
@immutable
class AppType {
  const AppType._();

  /// Dense metadata: log lines, badges, table cells.
  static const double caption = 9.0;

  /// Secondary rows, toggle labels, helper text (most common size in lib/).
  static const double body = 11.0;

  /// Primary row titles, section content.
  static const double title = 13.0;

  /// Card headers / screen titles.
  static const double heading = 16.0;
}

/// Metric thresholds. Today the server card hardcodes three different
/// critical/warn cutoffs at two call sites (cpu > 0.75, ram > 0.85,
/// disk > 0.8-as-warning); centralising them here keeps the demo card
/// and the live-agent card in agreement. See
/// `docs/design/02-server-status-card.md`.
@immutable
class AppThresholds {
  const AppThresholds._();

  static const double cpuCritical = 0.75;
  static const double ramCritical = 0.85;

  /// Disk degrades earlier (backups, docker layers) so it warns —
  /// not crits — at 0.80 and only crits when nearly full.
  static const double diskWarn = 0.80;
  static const double diskCritical = 0.95;
}
