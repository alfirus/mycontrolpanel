// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:my_control_panel/services/error_reporting.dart';
import 'package:my_control_panel/services/release_health.dart';

/// Release-health plumbing (Aisyah, DevOps).
/// Pure functions only — no keychain/prefs/network touches.
void main() {
  group('ErrorReporting.buildRelease', () {
    test('combines package, version and build number', () {
      expect(
        ErrorReporting.buildRelease(
          packageName: 'com.mycontrolpanel.my_control_panel',
          version: '1.0.0-beta.1',
          buildNumber: '1',
        ),
        'com.mycontrolpanel.my_control_panel@1.0.0-beta.1+1',
      );
    });

    test('omits the build suffix when blank', () {
      expect(
        ErrorReporting.buildRelease(
          packageName: 'com.example.app',
          version: '1.0.0',
        ),
        'com.example.app@1.0.0',
      );
    });

    test('trims whitespace', () {
      expect(
        ErrorReporting.buildRelease(
          packageName: '  com.example.app ',
          version: ' 1.0.0 ',
          buildNumber: ' 2 ',
        ),
        'com.example.app@1.0.0+2',
      );
    });
  });

  group('ErrorReporting.resolveEnvironment', () {
    test('tag beta builds report beta', () {
      expect(ErrorReporting.resolveEnvironment('beta'), 'beta');
      expect(ErrorReporting.resolveEnvironment(' Beta '), 'beta');
    });

    test('stable tags report production', () {
      expect(ErrorReporting.resolveEnvironment('stable'), 'production');
    });

    test('everything else is development (never pollutes the SLO)', () {
      expect(ErrorReporting.resolveEnvironment(''), 'development');
      expect(ErrorReporting.resolveEnvironment('production'), 'development');
      expect(ErrorReporting.resolveEnvironment('debug'), 'development');
    });
  });

  group('ReleaseHealth.shouldSendHeartbeat', () {
    test('first ever heartbeat is due', () {
      expect(
        ReleaseHealth.shouldSendHeartbeat(lastSentMs: 0, nowMs: 1000),
        isTrue,
      );
    });

    test('respects the 24 h interval', () {
      const hour = 3600 * 1000;
      expect(
        ReleaseHealth.shouldSendHeartbeat(
            lastSentMs: 1000, nowMs: 1000 + 23 * hour),
        isFalse,
      );
      expect(
        ReleaseHealth.shouldSendHeartbeat(
            lastSentMs: 1000, nowMs: 1000 + 24 * hour),
        isTrue,
      );
    });

    test('clock skew backwards never fires', () {
      expect(
        ReleaseHealth.shouldSendHeartbeat(lastSentMs: 2000, nowMs: 1000),
        isFalse,
      );
    });

    test('custom intervals are honored', () {
      expect(
        ReleaseHealth.shouldSendHeartbeat(
          lastSentMs: 0,
          nowMs: 1,
          interval: Duration.zero,
        ),
        isTrue,
      );
    });
  });

  group('ReleaseHealth.heartbeatPayload', () {
    test('carries release and environment tags', () {
      expect(
        ReleaseHealth.heartbeatPayload(
          release: 'com.example.app@1.0.0+1',
          environment: 'beta',
        ),
        {
          'release': 'com.example.app@1.0.0+1',
          'environment': 'beta',
        },
      );
    });
  });

  group('ReleaseHealth storage keys', () {
    test('heartbeat timestamp lives under its own prefs key', () {
      expect(
        ReleaseHealth.lastHeartbeatKey,
        'release_health_last_heartbeat_ms',
      );
      // Must not collide with the Sentry consent/DSN keys.
      expect(ReleaseHealth.lastHeartbeatKey, isNot(ErrorReporting.consentKey));
      expect(ReleaseHealth.lastHeartbeatKey, isNot(ErrorReporting.dsnKey));
    });
  });
}
