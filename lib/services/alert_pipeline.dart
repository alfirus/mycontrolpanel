/// Background alert-anomaly pipeline hooks for the Alerts engine.
///
/// [DiskForecaster], [LoadSpikeForecaster] and [AnomalyBaseline] already
/// exist as pure detectors; [AlertWatch] diffs foreground state. This file
/// is the missing middle: a per-host coordinator that feeds fresh samples
/// into those detectors every poll tick, turns their verdicts into
/// [AlertEntry] hooks with severity + source attribution, and fans out to
/// a notification hook with cooldown dedup.
///
/// Wiring contract (for Zara's polling job / control-center refresh):
/// one [AlertPipeline] per host, call [evaluate] once per tick with the
/// latest samples, pass an [onNotify] to deliver (foreground snackbar
/// today, flutter_local_notifications + workmanager when the background
/// step lands). Detectors keep their own history — the pipeline is cheap
/// to hold and safe to recreate (recreation just re-warms detectors).
library;

import '../models/alert_entry.dart';
import 'anomaly_baseline.dart';
import 'forecast_alerts.dart';

/// Delivery sink: (title, body). Implemented by the UI layer.
typedef PipelineNotify = void Function(String title, String body);

/// Per-host anomaly → alert coordinator.
class AlertPipeline {
  final String serverId;
  final String serverName;
  final DiskForecaster disk;
  final LoadSpikeForecaster load;
  final AnomalyBaseline cpuAnomaly;

  /// Minimum gap before the same rule re-notifies for the same host.
  final Duration resendCooldown;

  /// Warn at/under this ETA (hours) to the 80% line.
  final double warnEtaHours;

  /// Critical at/under this ETA (hours) to the 90% line.
  final double criticalEtaHours;

  final Map<String, int> _lastSentMs = {};

  AlertPipeline({
    required this.serverId,
    required this.serverName,
    DiskForecaster? diskForecaster,
    LoadSpikeForecaster? loadForecaster,
    AnomalyBaseline? cpuBaseline,
    this.resendCooldown = const Duration(hours: 6),
    this.warnEtaHours = 72,
    this.criticalEtaHours = 48,
  })  : disk = diskForecaster ?? const DiskForecaster(),
        load = loadForecaster ?? LoadSpikeForecaster(),
        cpuAnomaly =
            cpuBaseline ?? AnomalyBaseline('$serverId/cpu');

  /// Feed one poll tick; returns alert hooks worth surfacing.
  /// [diskHistory] is disk ratios 0..1 as [TrendPoint]s (t in hours).
  List<AlertEntry> evaluate({
    required List<TrendPoint> diskHistory,
    required double load1,
    required double cpuSample,
    required int nowMs,
    PipelineNotify? onNotify,
  }) {
    final out = <AlertEntry>[];
    void emit(String rule, AlertEntry a) {
      final last = _lastSentMs[rule];
      if (last != null && nowMs - last < resendCooldown.inMilliseconds) {
        return;
      }
      _lastSentMs[rule] = nowMs;
      out.add(a);
      onNotify?.call(a.title, '${a.serverName} · ${a.severity}');
    }

    final fc = disk.forecast(diskHistory);
    if (fc.hoursToCritical != null &&
        fc.hoursToCritical! <= criticalEtaHours) {
      emit(
        'disk-critical',
        AlertEntry(
          title:
              'Disk filling: ~${fc.hoursToCritical!.toStringAsFixed(0)}h to 90%',
          source: 'ml-pipeline/disk',
          severity: 'critical',
          serverId: serverId,
          serverName: serverName,
        ),
      );
    } else if (fc.hoursToWarn != null && fc.hoursToWarn! <= warnEtaHours) {
      emit(
        'disk-warn',
        AlertEntry(
          title: 'Disk growth: ~${fc.hoursToWarn!.toStringAsFixed(0)}h to 80%',
          source: 'ml-pipeline/disk',
          severity: 'warning',
          serverId: serverId,
          serverName: serverName,
        ),
      );
    }

    if (load.update(load1) == LoadVerdict.spiking) {
      emit(
        'load-spike',
        AlertEntry(
          title: 'Load spike on $serverName (1-min ${load1.toStringAsFixed(2)})',
          source: 'ml-pipeline/load',
          severity: 'warning',
          serverId: serverId,
          serverName: serverName,
        ),
      );
    }

    final anomaly = cpuAnomaly.update(cpuSample);
    if (anomaly.isAnomaly) {
      emit(
        'cpu-anomaly',
        AlertEntry(
          title:
              'CPU anomaly on $serverName (score ${anomaly.score.toStringAsFixed(1)})',
          source: 'ml-pipeline/cpu',
          severity: 'warning',
          serverId: serverId,
          serverName: serverName,
        ),
      );
    }
    return out;
  }
}
