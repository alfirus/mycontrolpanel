// Mock data for all 10 segments - pitch black control center
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum Status { operational, degraded, down, maintenance }
enum CronStatus { success, failed, running, skipped }
enum AppEnv { prod, staging, dev }

class ServerInfo {
  final String id, name, ip, region, os;
  final double cpu, ram, disk, latencyMs;
  final Status status;
  final int uptimeDays;
  final List<double> sparkline;
  const ServerInfo({required this.id, required this.name, required this.ip, required this.region, required this.os, required this.cpu, required this.ram, required this.disk, required this.latencyMs, required this.status, required this.uptimeDays, required this.sparkline});
}

class CronJob {
  final String name, schedule;
  final DateTime lastRun, nextRun;
  final CronStatus status;
  final String duration;
  final String server;
  const CronJob({required this.name, required this.schedule, required this.lastRun, required this.nextRun, required this.status, required this.duration, required this.server});
}

class AppInfo {
  final String name, version;
  final AppEnv env;
  final Status status;
  final double errorRate, rps;
  final int containers;
  final String region;
  const AppInfo({required this.name, required this.version, required this.env, required this.status, required this.errorRate, required this.rps, required this.containers, required this.region});
}

class GithubItem {
  final String title, repo, author;
  final int number;
  final String state; // open, closed, merged
  final List<String> labels;
  final DateTime updatedAt;
  final int comments;
  final List<String> assignees;
  const GithubItem({required this.title, required this.repo, required this.author, required this.number, required this.state, required this.labels, required this.updatedAt, required this.comments, this.assignees = const []});
}

class AlertItem {
  final String title, source, severity; // critical, warning, info
  final DateTime time;
  final String status; // firing, resolved, ack
  const AlertItem({required this.title, required this.source, required this.severity, required this.time, required this.status});
}

class DeployItem {
  final String app, version, env, actor;
  final DateTime time;
  final String status; // success, failed, running
  final String duration;
  final int? runId; // GitHub Actions run id (live data only)
  final String? ghRepo; // Full `owner/repo` for rerun (live GH runs only)
  final String vcs; // 'github' or 'gitlab'
  final String? glProject; // GitLab project path (live data only)
  final int? pipelineId; // GitLab pipeline id (live data only)
  const DeployItem({required this.app, required this.version, required this.env, required this.actor, required this.time, required this.status, required this.duration, this.runId, this.ghRepo, this.vcs = 'github', this.glProject, this.pipelineId});

  /// Copy with the full GitHub repo attached (stamped at fetch time so
  /// the timeline can re-run without re-resolving short names).
  DeployItem withRepo(String repo) => DeployItem(
        app: app,
        version: version,
        env: env,
        actor: actor,
        time: time,
        status: status,
        duration: duration,
        runId: runId,
        ghRepo: repo,
        vcs: vcs,
        glProject: glProject,
        pipelineId: pipelineId,
      );
}

class LogLine {
  final DateTime time;
  final String level, source, message;
  const LogLine({required this.time, required this.level, required this.source, required this.message});
}

class SecurityItem {
  final String title, severity, category;
  final String status;
  final DateTime detectedAt;
  const SecurityItem({required this.title, required this.severity, required this.category, required this.status, required this.detectedAt});
}

// --- Mock datasets ---
final mockServers = [
  const ServerInfo(id: 'srv-01', name: 'prod-core-01', ip: '10.0.1.10', region: 'us-east-1', os: 'Ubuntu 24.04', cpu: 0.42, ram: 0.68, disk: 0.51, latencyMs: 12, status: Status.operational, uptimeDays: 127, sparkline: [20, 35, 30, 45, 38, 52, 40, 48, 42]),
  const ServerInfo(id: 'srv-02', name: 'prod-core-02', ip: '10.0.1.11', region: 'us-east-1', os: 'Ubuntu 24.04', cpu: 0.78, ram: 0.82, disk: 0.63, latencyMs: 18, status: Status.degraded, uptimeDays: 127, sparkline: [40, 55, 65, 70, 78, 72, 80, 75, 78]),
  const ServerInfo(id: 'srv-03', name: 'prod-worker-01', ip: '10.0.2.20', region: 'eu-west-1', os: 'Debian 12', cpu: 0.22, ram: 0.34, disk: 0.28, latencyMs: 44, status: Status.operational, uptimeDays: 89, sparkline: [15, 20, 18, 22, 25, 20, 22, 18, 22]),
  const ServerInfo(id: 'srv-04', name: 'staging-01', ip: '10.0.10.5', region: 'us-east-1', os: 'Ubuntu 24.04', cpu: 0.11, ram: 0.29, disk: 0.41, latencyMs: 9, status: Status.maintenance, uptimeDays: 12, sparkline: [10, 12, 11, 9, 13, 11, 10, 11]),
  const ServerInfo(id: 'srv-05', name: 'db-primary', ip: '10.0.1.50', region: 'us-east-1', os: 'Ubuntu 22.04', cpu: 0.55, ram: 0.91, disk: 0.74, latencyMs: 2, status: Status.operational, uptimeDays: 312, sparkline: [50, 52, 55, 53, 58, 60, 55, 57, 55]),
];

final mockCrons = [
  CronJob(name: 'billing-sync', schedule: '0 * * * *', lastRun: DateTime.now().subtract(const Duration(minutes: 12)), nextRun: DateTime.now().add(const Duration(minutes: 48)), status: CronStatus.success, duration: '1.2s', server: 'prod-worker-01'),
  CronJob(name: 'purge-sessions', schedule: '0 3 * * *', lastRun: DateTime.now().subtract(const Duration(hours: 5)), nextRun: DateTime.now().add(const Duration(hours: 19)), status: CronStatus.failed, duration: '0.8s', server: 'prod-core-01'),
  CronJob(name: 'report-daily', schedule: '30 6 * * *', lastRun: DateTime.now().subtract(const Duration(hours: 2)), nextRun: DateTime.now().add(const Duration(hours: 22)), status: CronStatus.success, duration: '4.3s', server: 'prod-worker-01'),
  CronJob(name: 'health-ping', schedule: '*/5 * * * *', lastRun: DateTime.now().subtract(const Duration(minutes: 2)), nextRun: DateTime.now().add(const Duration(minutes: 3)), status: CronStatus.running, duration: '—', server: 'prod-core-02'),
  CronJob(name: 'cert-renew-check', schedule: '0 0 * * 0', lastRun: DateTime.now().subtract(const Duration(days: 1)), nextRun: DateTime.now().add(const Duration(days: 6)), status: CronStatus.skipped, duration: '0.2s', server: 'prod-core-01'),
  CronJob(name: 'backup-db', schedule: '0 2 * * *', lastRun: DateTime.now().subtract(const Duration(hours: 6)), nextRun: DateTime.now().add(const Duration(hours: 18)), status: CronStatus.success, duration: '62s', server: 'db-primary'),
];

final mockApps = [
  const AppInfo(name: 'api-gateway', version: 'v2.14.3', env: AppEnv.prod, status: Status.operational, errorRate: 0.12, rps: 3420, containers: 6, region: 'us-east-1'),
  const AppInfo(name: 'api-gateway', version: 'v2.15.0-rc1', env: AppEnv.staging, status: Status.degraded, errorRate: 1.8, rps: 210, containers: 2, region: 'us-east-1'),
  const AppInfo(name: 'web-dashboard', version: 'v1.9.0', env: AppEnv.prod, status: Status.operational, errorRate: 0.02, rps: 890, containers: 3, region: 'eu-west-1'),
  const AppInfo(name: 'worker-queue', version: 'v0.8.11', env: AppEnv.prod, status: Status.operational, errorRate: 0.45, rps: 1200, containers: 8, region: 'us-east-1'),
  const AppInfo(name: 'auth-service', version: 'v1.2.7', env: AppEnv.prod, status: Status.operational, errorRate: 0.05, rps: 2100, containers: 4, region: 'us-east-1'),
];

final mockIssues = [
  GithubItem(title: 'Fix cron retry backoff not respecting maxRetries', repo: 'mycontrolpanel/api', author: 'alfirusahmad', number: 142, state: 'open', labels: ['bug', 'cron'], updatedAt: DateTime.now().subtract(const Duration(hours: 2)), comments: 4),
  GithubItem(title: 'Add pitch black theme toggle for dashboard', repo: 'mycontrolpanel/control-center', author: 'sarah-chen', number: 88, state: 'open', labels: ['enhancement', 'ui'], updatedAt: DateTime.now().subtract(const Duration(hours: 5)), comments: 7),
  GithubItem(title: 'CI: flaky test in deploy pipeline', repo: 'mycontrolpanel/infra', author: 'bot-ci', number: 201, state: 'open', labels: ['ci', 'flaky'], updatedAt: DateTime.now().subtract(const Duration(days: 1)), comments: 2),
];

final mockPRs = [
  GithubItem(title: 'feat: live log tail with websocket streaming', repo: 'mycontrolpanel/control-center', author: 'alfirusahmad', number: 91, state: 'open', labels: ['feature'], updatedAt: DateTime.now().subtract(const Duration(minutes: 40)), comments: 3),
  GithubItem(title: 'fix: server sparkline overflow on small screens', repo: 'mycontrolpanel/control-center', author: 'sarah-chen', number: 90, state: 'open', labels: ['bug', 'ui'], updatedAt: DateTime.now().subtract(const Duration(hours: 1)), comments: 1),
  GithubItem(title: 'chore: bump fl_chart to 0.71', repo: 'mycontrolpanel/control-center', author: 'renovate', number: 89, state: 'open', labels: ['dependencies'], updatedAt: DateTime.now().subtract(const Duration(hours: 8)), comments: 0),
];

final mockTasks = [
  GithubItem(title: 'Design security watch segment - cert expiry', repo: 'Projects / Control Center', author: 'You', number: 12, state: 'open', labels: ['design'], updatedAt: DateTime.now().subtract(const Duration(hours: 3)), comments: 0),
  GithubItem(title: 'Wire AI chatbox to backend proxy', repo: 'Projects / Control Center', author: 'You', number: 13, state: 'open', labels: ['ai', 'backend'], updatedAt: DateTime.now().subtract(const Duration(days: 1)), comments: 5),
];

final mockAlerts = [
  AlertItem(title: 'High CPU on prod-core-02 (78% > 75% threshold)', source: 'Prometheus • cpu_usage', severity: 'warning', time: DateTime.now().subtract(const Duration(minutes: 8)), status: 'firing'),
  AlertItem(title: 'Cron purge-sessions failed - exit 1', source: 'Cron Monitor • prod-core-01', severity: 'critical', time: DateTime.now().subtract(const Duration(minutes: 12)), status: 'firing'),
  AlertItem(title: ' elevated 5xx on api-gateway staging', source: 'Sentry • error_rate', severity: 'warning', time: DateTime.now().subtract(const Duration(minutes: 34)), status: 'ack'),
  AlertItem(title: 'DB replica lag 2.4s', source: 'Datadog • replication', severity: 'info', time: DateTime.now().subtract(const Duration(hours: 1)), status: 'resolved'),
  AlertItem(title: 'Disk 74% on db-primary', source: 'Node Exporter', severity: 'info', time: DateTime.now().subtract(const Duration(hours: 2)), status: 'firing'),
];

final mockDeploys = [
  DeployItem(app: 'api-gateway', version: 'v2.14.3', env: 'prod', actor: 'alfirusahmad', time: DateTime.now().subtract(const Duration(minutes: 22)), status: 'success', duration: '1m 42s'),
  DeployItem(app: 'worker-queue', version: 'v0.8.11', env: 'prod', actor: 'github-actions', time: DateTime.now().subtract(const Duration(hours: 1)), status: 'success', duration: '2m 05s'),
  DeployItem(app: 'api-gateway', version: 'v2.15.0-rc1', env: 'staging', actor: 'sarah-chen', time: DateTime.now().subtract(const Duration(hours: 3)), status: 'failed', duration: '0m 48s'),
  DeployItem(app: 'web-dashboard', version: 'v1.9.0', env: 'prod', actor: 'alfirusahmad', time: DateTime.now().subtract(const Duration(hours: 6)), status: 'success', duration: '1m 12s'),
  DeployItem(app: 'auth-service', version: 'v1.2.7', env: 'prod', actor: 'github-actions', time: DateTime.now().subtract(const Duration(days: 1)), status: 'success', duration: '58s'),
  DeployItem(app: 'infra', version: 'tf-apply #412', env: 'prod', actor: 'terraform-cloud', time: DateTime.now().subtract(const Duration(days: 1, hours: 4)), status: 'running', duration: '—'),
];

final mockLogs = [
  LogLine(time: DateTime.now().subtract(const Duration(seconds: 12)), level: 'INFO', source: 'api-gateway', message: 'GET /api/v1/servers 200 12ms - ip 10.0.1.42'),
  LogLine(time: DateTime.now().subtract(const Duration(seconds: 18)), level: 'WARN', source: 'worker-queue', message: 'Job billing-sync retry 1/3 - rate limited by stripe'),
  LogLine(time: DateTime.now().subtract(const Duration(seconds: 22)), level: 'ERROR', source: 'cron', message: 'purge-sessions failed: pq: connection timeout (10.0.1.50:5432)'),
  LogLine(time: DateTime.now().subtract(const Duration(seconds: 31)), level: 'INFO', source: 'auth-service', message: 'token refresh ok user=alfirusahmad jti=a1b2c3'),
  LogLine(time: DateTime.now().subtract(const Duration(seconds: 44)), level: 'INFO', source: 'api-gateway', message: 'POST /api/v1/deploy 201 342ms'),
  LogLine(time: DateTime.now().subtract(const Duration(seconds: 58)), level: 'DEBUG', source: 'db-primary', message: 'checkpoint complete: wrote 412 buffers (2.1s)'),
  LogLine(time: DateTime.now().subtract(const Duration(minutes: 1, seconds: 12)), level: 'INFO', source: 'web-dashboard', message: 'render dashboard 86ms island=servers'),
  LogLine(time: DateTime.now().subtract(const Duration(minutes: 1, seconds: 30)), level: 'ERROR', source: 'api-gateway', message: 'upstream timeout service=worker-queue 5000ms'),
];

final mockSecurity = [
  SecurityItem(title: 'TLS cert expires in 8 days - *.mycontrolpanel.com', severity: 'warning', category: 'Certificates', status: 'open', detectedAt: DateTime.now().subtract(const Duration(hours: 4))),
  SecurityItem(title: '5 failed SSH logins from 45.33.12.8 (brute force)', severity: 'critical', category: 'Access', status: 'open', detectedAt: DateTime.now().subtract(const Duration(minutes: 20))),
  SecurityItem(title: 'CVE-2026-1234 - lodash 4.17.20 (moderate)', severity: 'info', category: 'Dependencies', status: 'open', detectedAt: DateTime.now().subtract(const Duration(days: 1))),
  SecurityItem(title: 'Public S3 bucket detected: mycontrolpanel-backups', severity: 'critical', category: 'Config', status: 'ack', detectedAt: DateTime.now().subtract(const Duration(hours: 2))),
  SecurityItem(title: '2FA not enabled for user sarah-chen', severity: 'info', category: 'IAM', status: 'open', detectedAt: DateTime.now().subtract(const Duration(days: 2))),
];

// Helpers
Color statusColor(Status s) {
  switch (s) {
    case Status.operational: return AppColors.success;
    case Status.degraded: return AppColors.warning;
    case Status.down: return AppColors.critical;
    case Status.maintenance: return AppColors.textMuted;
  }
}

Color cronColor(CronStatus s) {
  switch (s) {
    case CronStatus.success: return AppColors.success;
    case CronStatus.failed: return AppColors.critical;
    case CronStatus.running: return AppColors.info;
    case CronStatus.skipped: return AppColors.textMuted;
  }
}

Color severityColor(String sev) {
  switch (sev) {
    case 'critical': return AppColors.critical;
    case 'warning': return AppColors.warning;
    default: return AppColors.info;
  }
}

String timeAgo(DateTime dt) {
  final d = DateTime.now().difference(dt);
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}
