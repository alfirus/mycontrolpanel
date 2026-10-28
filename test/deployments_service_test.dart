import 'package:flutter_test/flutter_test.dart';
import 'package:my_control_panel/models/mock_data.dart';
import 'package:my_control_panel/services/deployments_service.dart';

DeployItem run(String app, int hour,
        {String status = 'success', String vcs = 'github'}) =>
    DeployItem(
      app: app,
      version: '#1 • abc1234',
      env: 'main',
      actor: 'ci',
      time: DateTime(2026, 10, 28, hour),
      status: status,
      duration: '10s',
      vcs: vcs,
    );

void main() {
  final ghOld = run('a', 9);
  final ghNew = run('b', 12);
  final glMid = run('c', 10, status: 'failed', vcs: 'gitlab');

  group('DeploymentsService.merge', () {
    test('merges both sources newest-first', () {
      final merged = DeploymentsService.merge([ghOld, ghNew], [glMid]);
      expect(merged.map((r) => r.app), ['b', 'c', 'a']);
    });

    test('empty inputs merge to empty', () {
      expect(DeploymentsService.merge([], []), isEmpty);
    });

    test('does not mutate the source lists', () {
      final gh = [ghNew, ghOld];
      DeploymentsService.merge(gh, [glMid]);
      expect(gh.map((r) => r.app), ['b', 'a']);
    });
  });

  group('DeploymentsService.timeline', () {
    test('caps at the limit, newest first', () {
      final many = List.generate(
          20, (i) => run('app$i', i % 24, vcs: i.isEven ? 'github' : 'gitlab'));
      final page =
          DeploymentsService.timeline(many, const [], limit: 12);
      expect(page, hasLength(12));
      for (var i = 0; i + 1 < page.length; i++) {
        expect(
            page[i].time.isAfter(page[i + 1].time) ||
                page[i].time.isAtSameMomentAs(page[i + 1].time),
            isTrue);
      }
    });

    test('default limit matches the timeline page (12)', () {
      final many = List.generate(30, (i) => run('app$i', i % 24));
      expect(DeploymentsService.timeline(many, const []), hasLength(12));
    });
  });

  group('DeploymentsService.failures', () {
    test('keeps failed runs only, newest first', () {
      final failed = DeploymentsService.failures([ghOld, ghNew, glMid]);
      expect(failed.map((r) => r.app), ['c']);
    });

    test('empty when nothing failed', () {
      expect(DeploymentsService.failures([ghOld, ghNew]), isEmpty);
    });
  });

  group('DeploymentsService.onlyVcs', () {
    test('filters to one VCS', () {
      final all = [ghOld, ghNew, glMid];
      expect(DeploymentsService.onlyVcs(all, 'gitlab').map((r) => r.app),
          ['c']);
      expect(DeploymentsService.onlyVcs(all, 'github').map((r) => r.app),
          ['a', 'b']);
    });

    test('unknown filter returns everything (demo rows stay visible)', () {
      final all = [ghOld, glMid];
      expect(DeploymentsService.onlyVcs(all, 'all'), hasLength(2));
    });
  });

  group('DeploymentsService.summary', () {
    test('reports counts per source', () {
      expect(DeploymentsService.summary([ghOld, ghNew], [glMid]),
          '3 runs (GH:2 • GL:1)');
    });

    test('single source omits the other', () {
      expect(DeploymentsService.summary([ghOld], []), '1 run (GH:1)');
    });

    test('empty timeline reports no runs', () {
      expect(DeploymentsService.summary([], []), 'No runs yet');
    });
  });
}
