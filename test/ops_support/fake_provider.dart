// SPDX-License-Identifier: MIT
/// Canned provider outcomes for lifecycle tests (Zara).
///
/// Keeps `ops_lifecycle_test.dart` hermetic: no subprocesses, no OS
/// scheduler calls — the consent gate and preflight paths are driven
/// by these fakes.
library;

import 'package:my_control_panel/ops/check_runner.dart';

abstract class FakeProviders {
  static ProviderResult ok() => const ProviderResult(
        exitCode: 0,
        stdout:
            '{"version":1,"status":"ok","exitCode":0}',
        stderr: '',
        durationMs: 3,
      );

  static ProviderResult consentOff() => const ProviderResult(
        exitCode: 2,
        stdout: '{"version":1,"status":"skipped","exitCode":2,'
            '"reason":"background_alerts consent OFF — headless tick skipped"}',
        stderr: '',
        durationMs: 2,
      );

  static ProviderResult totalFailure() => const ProviderResult(
        exitCode: 1,
        stdout: '',
        stderr: 'tick provider failed to launch: agent :9108 unreachable',
        durationMs: 1,
      );
}
