// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';

import 'package:my_control_panel/services/update_service.dart';

/// Staged-rollout channel logic (Aisyah, DevOps).
/// Pure functions only — no network, no platform channels.
void main() {
  ReleaseInfo rel(String tag) =>
      ReleaseInfo(tag: tag, name: tag, notes: '', assets: const []);

  group('UpdateChannel.fromTag', () {
    test('clean tags are stable', () {
      expect(UpdateChannel.fromTag('v1.0.0'), UpdateChannel.stable);
      expect(UpdateChannel.fromTag('v2.3.4'), UpdateChannel.stable);
    });

    test('suffixed tags are beta', () {
      expect(UpdateChannel.fromTag('v1.0.0-alpha.1'), UpdateChannel.beta);
      expect(UpdateChannel.fromTag('v1.0.0-beta.1'), UpdateChannel.beta);
    });

    test('ReleaseInfo.isPrerelease agrees with the channel', () {
      expect(rel('v1.0.0').isPrerelease, isFalse);
      expect(rel('v1.0.0-beta.1').isPrerelease, isTrue);
    });
  });

  group('UpdateChannel.includePrerelease', () {
    test('stable never includes pre-releases, beta does', () {
      expect(UpdateChannel.stable.includePrerelease, isFalse);
      expect(UpdateChannel.beta.includePrerelease, isTrue);
    });
  });

  group('UpdateService.pickLatestForChannel', () {
    final newestFirst = [
      rel('v1.1.0-beta.1'),
      rel('v1.0.0'),
      rel('v1.0.0-beta.2'),
    ];

    test('beta takes the newest of either track', () {
      expect(
        UpdateService.pickLatestForChannel(newestFirst, UpdateChannel.beta)
            ?.tag,
        'v1.1.0-beta.1',
      );
    });

    test('stable skips pre-releases', () {
      expect(
        UpdateService.pickLatestForChannel(newestFirst, UpdateChannel.stable)
            ?.tag,
        'v1.0.0',
      );
    });

    test('stable with only pre-releases yields null (no offer)', () {
      expect(
        UpdateService.pickLatestForChannel(
          [rel('v1.1.0-beta.1')],
          UpdateChannel.stable,
        ),
        isNull,
      );
    });

    test('empty input yields null, blank tags are skipped', () {
      expect(
        UpdateService.pickLatestForChannel(const [], UpdateChannel.beta),
        isNull,
      );
      expect(
        UpdateService.pickLatestForChannel(
          [rel(''), rel('v1.0.0')],
          UpdateChannel.stable,
        )?.tag,
        'v1.0.0',
      );
    });
  });

  group('UpdateService.releaseFromJson', () {
    test('parses tag/name/assets, drops nameless assets', () {
      final info = UpdateService.releaseFromJson({
        'tag_name': 'v1.0.0-beta.1',
        'name': 'MyControlPanel v1.0.0-beta.1 (beta)',
        'body': 'notes',
        'assets': [
          {
            'name': 'mycontrolpanel-linux-1.0.0-beta.1.tar.gz',
            'browser_download_url': 'https://example.com/a',
            'size': 42,
          },
          {'name': '', 'browser_download_url': '', 'size': 0},
        ],
      });
      expect(info.tag, 'v1.0.0-beta.1');
      expect(info.version, '1.0.0-beta.1');
      expect(info.isPrerelease, isTrue);
      expect(info.assets, hasLength(1));
      expect(info.assets.single.size, 42);
    });

    test('missing assets key yields an empty asset list', () {
      final info = UpdateService.releaseFromJson({'tag_name': 'v1.0.0'});
      expect(info.assets, isEmpty);
      expect(info.isPrerelease, isFalse);
    });
  });
}
